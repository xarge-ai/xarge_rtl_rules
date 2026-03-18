# Copyright 2024 Xarge AI
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Corsair register-generation rules.

Public entrypoints:

- corsair_generate: Bazel-native CSR generation rule with deterministic build outputs
- corsair_publish: runnable helper that copies generated outputs into repo-local check-in paths
- corsair_snapshot_manifest: emits a manifest describing generated build outputs
- corsair_generate_raw: compatibility rule for direct csrconfig + declared outs/out_dirs
- corsair_workflow: advanced Python API-oriented rule for custom workflows
"""

load("@rules_python//python:defs.bzl", "PyInfo")
load("//rtl:providers.bzl", "VerilogInfo")

CorsairInfo = provider(
    doc = "Metadata describing outputs created by a Corsair generation target.",
    fields = {
        "files": "Dictionary mapping generated relative file paths to File artifacts.",
        "directories": "Dictionary mapping generated relative directory paths to tree artifacts.",
        "file_categories": "Dictionary mapping generated relative file paths to semantic categories.",
        "directory_categories": "Dictionary mapping generated relative directory paths to semantic categories.",
        "all_files": "depset of all generated file outputs.",
        "all_directories": "depset of all generated directory outputs.",
        "rtl": "depset of generated RTL module outputs.",
        "sv": "depset of generated SystemVerilog package outputs.",
        "vh": "depset of generated Verilog/SystemVerilog header outputs.",
        "c": "depset of generated C header outputs.",
        "py": "depset of generated Python module outputs.",
        "docs": "depset of generated documentation files.",
        "doc_dirs": "depset of generated documentation directories.",
        "data": "depset of generated JSON/YAML/TXT dump files.",
    },
)

_RUNNER = Label("//corsair/runner:workflow_runner")

_DEFAULT_BASE_ADDRESS = 0
_DEFAULT_DATA_WIDTH = 32
_DEFAULT_ADDRESS_WIDTH = 16
_DEFAULT_REGISTER_RESET = "sync_pos"
_DEFAULT_ADDRESS_ALIGNMENT = "data_width"
_DEFAULT_INTERFACE = "axil"
_DEFAULT_READ_FILLER = 0
_DEFAULT_TITLE = "Register map"

_RTL_LANGS = ["verilog", "vhdl"]
_INTERFACES = ["axil", "apb", "amm", "lb"]
_REGISTER_RESETS = ["sync_pos", "sync_neg", "async_pos", "async_neg"]
_FORCE_NAME_CASES = ["lower", "upper", "none"]

_STANDARD_SECTION_ORDER = [
    "rtl",
    "sv_pkg",
    "verilog_header",
    "c_header",
    "python_module",
    "markdown",
    "asciidoc",
    "json_dump",
    "yaml_dump",
    "txt_dump",
]

_CONFIG_KEY_ORDER = [
    "base_address",
    "data_width",
    "address_width",
    "register_reset",
    "address_increment",
    "address_alignment",
    "force_name_case",
]

_SECTION_KEY_ORDER = [
    "generator",
    "path",
    "read_filler",
    "interface",
    "prefix",
    "title",
    "print_images",
    "image_dir",
    "print_conventions",
    "bridge_type",
]

_TARGET_GENERATOR_INFO = {
    "Verilog": struct(category = "rtl", creates_verilog = True, creates_dir = False),
    "Vhdl": struct(category = "rtl", creates_verilog = False, creates_dir = False),
    "LbBridgeVerilog": struct(category = "rtl", creates_verilog = True, creates_dir = False),
    "LbBridgeVhdl": struct(category = "rtl", creates_verilog = False, creates_dir = False),
    "SystemVerilogPackage": struct(category = "sv", creates_verilog = True, creates_dir = False),
    "VerilogHeader": struct(category = "headers", creates_verilog = True, creates_dir = False),
    "CHeader": struct(category = "c", creates_verilog = False, creates_dir = False),
    "Python": struct(category = "python", creates_verilog = False, creates_dir = False),
    "Markdown": struct(category = "docs", creates_verilog = False, creates_dir = True),
    "Asciidoc": struct(category = "docs", creates_verilog = False, creates_dir = True),
    "Json": struct(category = "data", creates_verilog = False, creates_dir = False),
    "Yaml": struct(category = "data", creates_verilog = False, creates_dir = False),
    "Txt": struct(category = "data", creates_verilog = False, creates_dir = False),
}

_DOC_GENERATORS = ["Markdown", "Asciidoc"]

_PUBLISH_CATEGORY_DIRS = {
    "rtl": "hw",
    "sv": "hw",
    "headers": "hw",
    "c": "sw",
    "python": "sw",
    "docs": "doc",
    "data": "doc",
}

def _empty_category_buckets():
    return {
        "rtl": [],
        "sv": [],
        "headers": [],
        "c": [],
        "python": [],
        "docs": [],
        "data": [],
    }

def _default_prefix(name):
    chars = []
    for i in range(len(name)):
        ch = name[i]
        if (("a" <= ch) and (ch <= "z")) or (("A" <= ch) and (ch <= "Z")) or (("0" <= ch) and (ch <= "9")):
            chars.append(ch.upper())
        else:
            chars.append("_")
    return "".join(chars)

def _path_dir(path):
    parts = path.rsplit("/", 1)
    if len(parts) == 2:
        return parts[0]
    return ""

def _path_join(dirname, basename):
    if dirname:
        return dirname + "/" + basename
    return basename

def _validate_relative_path(path, attr_name):
    if not path:
        fail("%s must not be empty." % attr_name)
    if path.startswith("/"):
        fail("%s must be a relative path, got '%s'." % (attr_name, path))
    if path == ".." or path.startswith("../") or "/../" in path or path.endswith("/.."):
        fail("%s must stay within the Bazel output tree, got '%s'." % (attr_name, path))

def _validate_optional_output_path(path, attr_name):
    if path:
        _validate_relative_path(path, attr_name)

def _validate_workspace_relative_path(path, attr_name):
    if not path:
        fail("%s must not be empty." % attr_name)
    if path.startswith("/"):
        fail("%s must be a relative path, got '%s'." % (attr_name, path))
    if path == ".." or path.startswith("../") or "/../" in path or path.endswith("/.."):
        fail("%s must stay within the workspace tree, got '%s'." % (attr_name, path))

def _validate_keyword_or_int(value, attr_name, allowed_keywords):
    if not value:
        return
    if value in allowed_keywords:
        return
    for ch in value:
        if ch < "0" or ch > "9":
            fail(
                "%s must be one of %s, a non-negative integer, or None." % (
                    attr_name,
                    allowed_keywords,
                ),
            )

def _bool_to_config(value):
    return "true" if value else "false"

def _render_config_value(value):
    if type(value) == "bool":
        return _bool_to_config(value)
    return str(value)

def _render_csrconfig(globcfg, section_order, sections):
    lines = []
    lines.append("[globcfg]")
    for key in _CONFIG_KEY_ORDER:
        if key in globcfg:
            lines.append("%s = %s" % (key, _render_config_value(globcfg[key])))

    for section_name in section_order:
        params = sections[section_name]
        lines.append("")
        lines.append("[%s]" % section_name)
        for key in _SECTION_KEY_ORDER:
            if key in params:
                lines.append("%s = %s" % (key, _render_config_value(params[key])))
        for key in sorted(params.keys()):
            if key not in _SECTION_KEY_ORDER:
                lines.append("%s = %s" % (key, _render_config_value(params[key])))

    return "\n".join(lines) + "\n"

def _json_escape(value):
    return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

def _render_json(value, indent = ""):
    _ignore = indent
    return json.encode_indent(value)

def _shell_quote(value):
    return "'" + value.replace("'", "'\"'\"'") + "'"

def _package_bin_dir(ctx):
    if ctx.label.package:
        return ctx.bin_dir.path + "/" + ctx.label.package
    return ctx.bin_dir.path

def _declared_name(path, package_bin_dir):
    prefix = package_bin_dir + "/"
    if path.startswith(prefix):
        return path[len(prefix):]
    return path

def _validate_unique_output_names(file_outputs, dir_outputs):
    shared = [name for name in dir_outputs if name in file_outputs]
    if shared:
        fail(
            "Corsair rule output names must be unique across file and directory outputs: %s" %
            ", ".join(sorted(shared)),
        )

def _collect_declared_outputs(ctx):
    package_bin_dir = _package_bin_dir(ctx)

    file_outputs = {}
    for out in ctx.outputs.outs:
        name = _declared_name(out.path, package_bin_dir)
        if name in file_outputs:
            fail("Duplicate file output '%s' declared in outs." % name)
        file_outputs[name] = out

    dir_outputs = {}
    for name in ctx.attr.out_dirs:
        if name in dir_outputs:
            fail("Duplicate directory output '%s' declared in out_dirs." % name)
        dir_outputs[name] = ctx.actions.declare_directory(name)

    if not file_outputs and not dir_outputs:
        fail("Corsair rule requires at least one declared output in outs or out_dirs.")

    _validate_unique_output_names(file_outputs, dir_outputs)
    return file_outputs, dir_outputs

def _categorize_outputs(file_outputs, dir_outputs):
    categories = _empty_category_buckets()
    directory_categories = {"docs": []}
    verilog_srcs = []
    include_dirs = {}
    file_category_map = {}
    directory_category_map = {}

    for relpath in sorted(file_outputs.keys()):
        out = file_outputs[relpath]
        lower = relpath.lower()
        category = "data"
        is_verilog = False
        if lower.endswith("_pkg.sv"):
            category = "sv"
            is_verilog = True
        elif lower.endswith(".vh") or lower.endswith(".svh"):
            category = "headers"
            is_verilog = True
            include_dirs[_path_dir(relpath) or "."] = True
        elif lower.endswith(".h"):
            category = "c"
        elif lower.endswith(".py"):
            category = "python"
        elif lower.endswith(".md") or lower.endswith(".adoc"):
            category = "docs"
        elif lower.endswith(".json") or lower.endswith(".yaml") or lower.endswith(".yml") or lower.endswith(".txt"):
            category = "data"
        elif lower.endswith(".v") or lower.endswith(".sv"):
            category = "rtl"
            is_verilog = True
        elif lower.endswith(".vhd"):
            category = "rtl"

        categories[category].append(out)
        file_category_map[relpath] = category
        if is_verilog:
            verilog_srcs.append(out)

    for relpath in sorted(dir_outputs.keys()):
        out = dir_outputs[relpath]
        directory_categories["docs"].append(out)
        directory_category_map[relpath] = "docs"

    return struct(
        categories = categories,
        directory_categories = directory_categories,
        verilog_srcs = verilog_srcs,
        include_dirs = sorted(include_dirs.keys()),
        file_category_map = file_category_map,
        directory_category_map = directory_category_map,
    )

def _run_runner_action(ctx, args, direct_inputs, outputs, mnemonic, progress_message):
    py_toolchain = ctx.toolchains["@rules_python//python:toolchain_type"].py3_runtime

    ctx.actions.run(
        executable = ctx.executable._runner,
        arguments = [args],
        inputs = depset(
            direct = direct_inputs,
            transitive = [
                ctx.attr._runner[PyInfo].transitive_sources,
                py_toolchain.files,
            ],
        ),
        outputs = outputs,
        mnemonic = mnemonic,
        progress_message = progress_message,
    )

def _new_file_plan(relpath, section_name, params, category, creates_verilog):
    return struct(
        relpath = relpath,
        section_name = section_name,
        params = params,
        category = category,
        creates_verilog = creates_verilog,
    )

def _validate_native_csrconfig_conflicts(ctx):
    if not ctx.file.csrconfig:
        return

    conflicts = []
    if ctx.attr.base_address != _DEFAULT_BASE_ADDRESS:
        conflicts.append("base_address")
    if ctx.attr.data_width != _DEFAULT_DATA_WIDTH:
        conflicts.append("data_width")
    if ctx.attr.address_width != _DEFAULT_ADDRESS_WIDTH:
        conflicts.append("address_width")
    if ctx.attr.register_reset != _DEFAULT_REGISTER_RESET:
        conflicts.append("register_reset")
    if ctx.attr.address_increment:
        conflicts.append("address_increment")
    if ctx.attr.address_alignment != _DEFAULT_ADDRESS_ALIGNMENT:
        conflicts.append("address_alignment")
    if ctx.attr.force_name_case:
        conflicts.append("force_name_case")
    if ctx.attr.interface != _DEFAULT_INTERFACE:
        conflicts.append("interface")
    if ctx.attr.read_filler != _DEFAULT_READ_FILLER:
        conflicts.append("read_filler")
    if ctx.attr.prefix:
        conflicts.append("prefix")
    if ctx.attr.title != _DEFAULT_TITLE:
        conflicts.append("title")
    if not ctx.attr.print_images:
        conflicts.append("print_images")
    if ctx.attr.image_dir:
        conflicts.append("image_dir")
    if not ctx.attr.print_conventions:
        conflicts.append("print_conventions")
    if ctx.attr.targets:
        conflicts.append("targets")

    if conflicts:
        fail(
            "corsair_generate with csrconfig only accepts Bazel-native output selection and naming hints. " +
            "These attrs must remain at defaults: %s. " % ", ".join(sorted(conflicts)) +
            "Use corsair_generate_raw for arbitrary native csrconfig layouts."
        )

def _resolve_effective_output_path(override_path, default_path, attr_name):
    path = override_path if override_path else default_path
    _validate_relative_path(path, attr_name)
    return path

def _validate_standard_attr_usage(ctx):
    if ctx.attr.rtl_lang not in _RTL_LANGS:
        fail("rtl_lang must be one of %s." % _RTL_LANGS)
    if ctx.attr.interface not in _INTERFACES:
        fail("interface must be one of %s." % _INTERFACES)
    if ctx.attr.register_reset not in _REGISTER_RESETS:
        fail("register_reset must be one of %s." % _REGISTER_RESETS)
    if ctx.attr.force_name_case and ctx.attr.force_name_case not in _FORCE_NAME_CASES:
        fail("force_name_case must be one of %s or None." % _FORCE_NAME_CASES)

    _validate_keyword_or_int(ctx.attr.address_increment, "address_increment", ["none", "data_width"])
    _validate_keyword_or_int(ctx.attr.address_alignment, "address_alignment", ["none", "data_width"])

    has_docs = ctx.attr.markdown or ctx.attr.asciidoc
    has_prefix_outputs = ctx.attr.sv_pkg or ctx.attr.verilog_header or ctx.attr.c_header

    if not ctx.attr.rtl:
        if ctx.attr.rtl_out:
            fail("rtl_out requires rtl = True.")
        if ctx.attr.module_name:
            fail("module_name requires rtl = True.")
        if ctx.attr.interface != _DEFAULT_INTERFACE:
            fail("interface can only be customized when rtl = True.")
        if ctx.attr.read_filler != _DEFAULT_READ_FILLER:
            fail("read_filler can only be customized when rtl = True.")
        if ctx.attr.rtl_lang != "verilog":
            fail("rtl_lang can only be customized when rtl = True.")

    if not ctx.attr.sv_pkg and ctx.attr.sv_pkg_out:
        fail("sv_pkg_out requires sv_pkg = True.")
    if not ctx.attr.verilog_header and ctx.attr.verilog_header_out:
        fail("verilog_header_out requires verilog_header = True.")
    if not ctx.attr.c_header and ctx.attr.c_header_out:
        fail("c_header_out requires c_header = True.")
    if not ctx.attr.python_module and ctx.attr.python_out:
        fail("python_out requires python_module = True.")
    if not ctx.attr.markdown and ctx.attr.markdown_out:
        fail("markdown_out requires markdown = True.")
    if not ctx.attr.asciidoc and ctx.attr.asciidoc_out:
        fail("asciidoc_out requires asciidoc = True.")
    if not ctx.attr.json_dump and ctx.attr.json_out:
        fail("json_out requires json_dump = True.")
    if not ctx.attr.yaml_dump and ctx.attr.yaml_out:
        fail("yaml_out requires yaml_dump = True.")
    if not ctx.attr.txt_dump and ctx.attr.txt_out:
        fail("txt_out requires txt_dump = True.")

    if not has_docs:
        if ctx.attr.title != _DEFAULT_TITLE:
            fail("title requires markdown = True or asciidoc = True.")
        if not ctx.attr.print_images:
            fail("print_images requires markdown = True or asciidoc = True.")
        if ctx.attr.image_dir:
            fail("image_dir requires markdown = True or asciidoc = True.")
        if not ctx.attr.print_conventions:
            fail("print_conventions requires markdown = True or asciidoc = True.")
    elif ctx.attr.image_dir and not ctx.attr.print_images:
        fail("image_dir requires print_images = True.")

    if not has_prefix_outputs and ctx.attr.prefix:
        fail("prefix requires sv_pkg = True, verilog_header = True, or c_header = True.")

    if ctx.attr.rtl_lang == "vhdl" and ctx.attr.verilog_header:
        fail("verilog_header is only supported when rtl_lang = 'verilog'.")

    if not (
        ctx.attr.rtl or
        ctx.attr.sv_pkg or
        ctx.attr.verilog_header or
        ctx.attr.c_header or
        ctx.attr.python_module or
        ctx.attr.markdown or
        ctx.attr.asciidoc or
        ctx.attr.json_dump or
        ctx.attr.yaml_dump or
        ctx.attr.txt_dump or
        ctx.attr.targets
    ):
        fail("corsair_generate requires at least one enabled output or an extra target.")

    for attr_name in [
        "rtl_out",
        "sv_pkg_out",
        "verilog_header_out",
        "c_header_out",
        "python_out",
        "markdown_out",
        "asciidoc_out",
        "json_out",
        "yaml_out",
        "txt_out",
    ]:
        _validate_optional_output_path(getattr(ctx.attr, attr_name), attr_name)

    if ctx.attr.image_dir:
        _validate_relative_path(ctx.attr.image_dir, "image_dir")

def _parse_extra_target_entries(section_name, entries):
    params = {}
    for entry in entries:
        parts = entry.split("=", 1)
        if len(parts) != 2 or not parts[0]:
            fail("targets['%s'] entries must be KEY=VALUE strings, got '%s'." % (section_name, entry))
        key = parts[0]
        value = parts[1]
        if key in params:
            fail("targets['%s'] repeated key '%s'." % (section_name, key))
        params[key] = value

    if "generator" not in params:
        fail("targets['%s'] must declare a generator." % section_name)
    if "path" not in params:
        fail("targets['%s'] must declare a path." % section_name)
    if params["generator"] not in _TARGET_GENERATOR_INFO:
        fail(
            "targets['%s'] uses unsupported generator '%s'. Supported built-ins: %s." % (
                section_name,
                params["generator"],
                sorted(_TARGET_GENERATOR_INFO.keys()),
            ),
        )

    _validate_relative_path(params["path"], "targets['%s'].path" % section_name)

    image_dir_relpath = None
    if params["generator"] in _DOC_GENERATORS:
        print_images = True
        if "print_images" in params:
            lowered = params["print_images"].lower()
            if lowered in ["false", "f", "no", "n", "0"]:
                print_images = False
            elif lowered in ["true", "t", "yes", "y", "1"]:
                print_images = True
            else:
                fail("targets['%s'].print_images must be a boolean string." % section_name)
        if "image_dir" in params:
            _validate_relative_path(params["image_dir"], "targets['%s'].image_dir" % section_name)
            image_dir = params["image_dir"]
        else:
            image_dir = "regs_img"
        if print_images:
            image_dir_relpath = _path_join(_path_dir(params["path"]), image_dir)

    return struct(
        params = params,
        info = _TARGET_GENERATOR_INFO[params["generator"]],
        image_dir_relpath = image_dir_relpath,
    )

def _add_output_file(plan, relpath, category, creates_verilog, section_name, params):
    if relpath in plan.file_plans:
        fail("Generated file path '%s' was declared more than once." % relpath)
    if relpath in plan.dir_plans:
        fail("Generated output path '%s' cannot be both a file and a directory." % relpath)
    plan.file_plans[relpath] = _new_file_plan(relpath, section_name, params, category, creates_verilog)

def _add_output_dir(plan, relpath, category):
    if relpath in plan.file_plans:
        fail("Generated output path '%s' cannot be both a file and a directory." % relpath)
    plan.dir_plans[relpath] = category

def _new_native_plan():
    return struct(
        file_plans = {},
        dir_plans = {},
        sections = {},
        section_order = [],
    )

def _build_native_plan(ctx):
    _validate_standard_attr_usage(ctx)
    _validate_native_csrconfig_conflicts(ctx)

    plan = _new_native_plan()
    regmap_basename = ctx.file.regmap.basename
    module_name = ctx.attr.module_name if ctx.attr.module_name else ctx.label.name
    prefix = ctx.attr.prefix if ctx.attr.prefix else _default_prefix(ctx.label.name)
    image_dir = ctx.attr.image_dir if ctx.attr.image_dir else ctx.label.name + "_img"

    if ctx.attr.rtl:
        rtl_ext = "v" if ctx.attr.rtl_lang == "verilog" else "vhd"
        rtl_path = _resolve_effective_output_path(
            ctx.attr.rtl_out,
            "%s.%s" % (module_name, rtl_ext),
            "rtl_out",
        )
        params = {
            "generator": "Verilog" if ctx.attr.rtl_lang == "verilog" else "Vhdl",
            "path": rtl_path,
        }
        if ctx.attr.interface != _DEFAULT_INTERFACE:
            params["interface"] = ctx.attr.interface
        if ctx.attr.read_filler != _DEFAULT_READ_FILLER:
            params["read_filler"] = ctx.attr.read_filler
        _add_output_file(plan, rtl_path, "rtl", ctx.attr.rtl_lang == "verilog", "rtl", params)
        plan.sections["rtl"] = params
        plan.section_order.append("rtl")

    if ctx.attr.sv_pkg:
        sv_pkg_path = _resolve_effective_output_path(
            ctx.attr.sv_pkg_out,
            "%s_pkg.sv" % ctx.label.name,
            "sv_pkg_out",
        )
        params = {
            "generator": "SystemVerilogPackage",
            "path": sv_pkg_path,
            "prefix": prefix,
        }
        _add_output_file(plan, sv_pkg_path, "sv", True, "sv_pkg", params)
        plan.sections["sv_pkg"] = params
        plan.section_order.append("sv_pkg")

    if ctx.attr.verilog_header:
        verilog_header_path = _resolve_effective_output_path(
            ctx.attr.verilog_header_out,
            "%s.vh" % ctx.label.name,
            "verilog_header_out",
        )
        params = {
            "generator": "VerilogHeader",
            "path": verilog_header_path,
            "prefix": prefix,
        }
        _add_output_file(plan, verilog_header_path, "headers", True, "verilog_header", params)
        plan.sections["verilog_header"] = params
        plan.section_order.append("verilog_header")

    if ctx.attr.c_header:
        c_header_path = _resolve_effective_output_path(
            ctx.attr.c_header_out,
            "%s.h" % ctx.label.name,
            "c_header_out",
        )
        params = {
            "generator": "CHeader",
            "path": c_header_path,
            "prefix": prefix,
        }
        _add_output_file(plan, c_header_path, "c", False, "c_header", params)
        plan.sections["c_header"] = params
        plan.section_order.append("c_header")

    if ctx.attr.python_module:
        python_path = _resolve_effective_output_path(
            ctx.attr.python_out,
            "%s.py" % ctx.label.name,
            "python_out",
        )
        params = {
            "generator": "Python",
            "path": python_path,
        }
        _add_output_file(plan, python_path, "python", False, "python_module", params)
        plan.sections["python_module"] = params
        plan.section_order.append("python_module")

    if ctx.attr.markdown:
        markdown_path = _resolve_effective_output_path(
            ctx.attr.markdown_out,
            "%s.md" % ctx.label.name,
            "markdown_out",
        )
        params = {
            "generator": "Markdown",
            "path": markdown_path,
            "image_dir": image_dir,
        }
        if ctx.attr.title != _DEFAULT_TITLE:
            params["title"] = ctx.attr.title
        if not ctx.attr.print_images:
            params["print_images"] = False
        if not ctx.attr.print_conventions:
            params["print_conventions"] = False
        _add_output_file(plan, markdown_path, "docs", False, "markdown", params)
        plan.sections["markdown"] = params
        plan.section_order.append("markdown")
        if ctx.attr.print_images:
            _add_output_dir(plan, _path_join(_path_dir(markdown_path), image_dir), "docs")

    if ctx.attr.asciidoc:
        asciidoc_path = _resolve_effective_output_path(
            ctx.attr.asciidoc_out,
            "%s.adoc" % ctx.label.name,
            "asciidoc_out",
        )
        params = {
            "generator": "Asciidoc",
            "path": asciidoc_path,
            "image_dir": image_dir,
        }
        if ctx.attr.title != _DEFAULT_TITLE:
            params["title"] = ctx.attr.title
        if not ctx.attr.print_images:
            params["print_images"] = False
        if not ctx.attr.print_conventions:
            params["print_conventions"] = False
        _add_output_file(plan, asciidoc_path, "docs", False, "asciidoc", params)
        plan.sections["asciidoc"] = params
        plan.section_order.append("asciidoc")
        if ctx.attr.print_images:
            _add_output_dir(plan, _path_join(_path_dir(asciidoc_path), image_dir), "docs")

    if ctx.attr.json_dump:
        json_path = _resolve_effective_output_path(
            ctx.attr.json_out,
            "%s.json" % ctx.label.name,
            "json_out",
        )
        params = {
            "generator": "Json",
            "path": json_path,
        }
        _add_output_file(plan, json_path, "data", False, "json_dump", params)
        plan.sections["json_dump"] = params
        plan.section_order.append("json_dump")

    if ctx.attr.yaml_dump:
        yaml_path = _resolve_effective_output_path(
            ctx.attr.yaml_out,
            "%s_dump.yaml" % ctx.label.name,
            "yaml_out",
        )
        if yaml_path.split("/")[-1] == regmap_basename:
            fail("yaml_dump output '%s' collides with the regmap basename '%s'." % (yaml_path, regmap_basename))
        params = {
            "generator": "Yaml",
            "path": yaml_path,
        }
        _add_output_file(plan, yaml_path, "data", False, "yaml_dump", params)
        plan.sections["yaml_dump"] = params
        plan.section_order.append("yaml_dump")

    if ctx.attr.txt_dump:
        txt_path = _resolve_effective_output_path(
            ctx.attr.txt_out,
            "%s.txt" % ctx.label.name,
            "txt_out",
        )
        params = {
            "generator": "Txt",
            "path": txt_path,
        }
        _add_output_file(plan, txt_path, "data", False, "txt_dump", params)
        plan.sections["txt_dump"] = params
        plan.section_order.append("txt_dump")

    for section_name in sorted(ctx.attr.targets.keys()):
        if section_name in plan.sections:
            fail("targets may not override built-in section '%s'." % section_name)
        extra = _parse_extra_target_entries(section_name, ctx.attr.targets[section_name])
        _add_output_file(
            plan,
            extra.params["path"],
            extra.info.category,
            extra.info.creates_verilog,
            section_name,
            extra.params,
        )
        if extra.image_dir_relpath:
            _add_output_dir(plan, extra.image_dir_relpath, "docs")
        plan.sections[section_name] = extra.params
        plan.section_order.append(section_name)

    globcfg = {}
    if ctx.attr.base_address != _DEFAULT_BASE_ADDRESS:
        globcfg["base_address"] = ctx.attr.base_address
    if ctx.attr.data_width != _DEFAULT_DATA_WIDTH:
        globcfg["data_width"] = ctx.attr.data_width
    if ctx.attr.address_width != _DEFAULT_ADDRESS_WIDTH:
        globcfg["address_width"] = ctx.attr.address_width
    if ctx.attr.register_reset != _DEFAULT_REGISTER_RESET:
        globcfg["register_reset"] = ctx.attr.register_reset
    if ctx.attr.address_increment:
        globcfg["address_increment"] = ctx.attr.address_increment
    if ctx.attr.address_alignment != _DEFAULT_ADDRESS_ALIGNMENT:
        globcfg["address_alignment"] = ctx.attr.address_alignment
    if ctx.attr.force_name_case:
        globcfg["force_name_case"] = ctx.attr.force_name_case

    return struct(
        file_plans = plan.file_plans,
        dir_plans = plan.dir_plans,
        config_text = _render_csrconfig(globcfg, plan.section_order, plan.sections),
    )

def _declare_native_outputs(ctx, plan):
    file_outputs = {}
    dir_outputs = {}
    for relpath in sorted(plan.file_plans.keys()):
        file_outputs[relpath] = ctx.actions.declare_file(relpath)
    for relpath in sorted(plan.dir_plans.keys()):
        dir_outputs[relpath] = ctx.actions.declare_directory(relpath)
    return file_outputs, dir_outputs

def _make_corsair_info(file_outputs, dir_outputs, categorized):
    return CorsairInfo(
        files = file_outputs,
        directories = dir_outputs,
        file_categories = categorized.file_category_map,
        directory_categories = categorized.directory_category_map,
        all_files = depset(file_outputs.values()),
        all_directories = depset(dir_outputs.values()),
        rtl = depset(categorized.categories["rtl"]),
        sv = depset(categorized.categories["sv"]),
        vh = depset(categorized.categories["headers"]),
        c = depset(categorized.categories["c"]),
        py = depset(categorized.categories["python"]),
        docs = depset(categorized.categories["docs"]),
        doc_dirs = depset(categorized.directory_categories["docs"]),
        data = depset(categorized.categories["data"]),
    )

def _make_output_groups(file_outputs, dir_outputs, categorized):
    return OutputGroupInfo(
        rtl = depset(categorized.categories["rtl"]),
        sv = depset(categorized.categories["sv"]),
        headers = depset(categorized.categories["headers"] + categorized.categories["c"]),
        c = depset(categorized.categories["c"]),
        python = depset(categorized.categories["python"]),
        docs = depset(categorized.categories["docs"] + categorized.directory_categories["docs"]),
        data = depset(categorized.categories["data"]),
        all_generated = depset(file_outputs.values() + dir_outputs.values()),
    )

def _maybe_make_verilog_info(file_outputs, categorized):
    if not categorized.verilog_srcs:
        return None
    return VerilogInfo(
        srcs = depset(categorized.verilog_srcs),
        transitive_srcs = depset(categorized.verilog_srcs),
        includes = depset(categorized.include_dirs),
        defines = depset([]),
    )

def _corsair_generate_native_impl(ctx):
    plan = _build_native_plan(ctx)
    file_outputs, dir_outputs = _declare_native_outputs(ctx, plan)

    config_file = ctx.actions.declare_file(ctx.label.name + "__corsair.csrconfig")
    ctx.actions.write(config_file, plan.config_text)

    args = ctx.actions.args()
    args.add("--mode", "config")
    args.add("--regmap", ctx.file.regmap.path)
    args.add("--csrconfig", config_file.path)
    if ctx.file.csrconfig:
        args.add("--override-csrconfig", ctx.file.csrconfig.path)

    for relpath in sorted(file_outputs.keys()):
        args.add("--output", "%s=%s" % (relpath, file_outputs[relpath].path))
    for relpath in sorted(dir_outputs.keys()):
        args.add("--output-dir", "%s=%s" % (relpath, dir_outputs[relpath].path))

    outputs = file_outputs.values() + dir_outputs.values()
    direct_inputs = [ctx.file.regmap, config_file]
    if ctx.file.csrconfig:
        direct_inputs.append(ctx.file.csrconfig)

    _run_runner_action(
        ctx = ctx,
        args = args,
        direct_inputs = direct_inputs,
        outputs = outputs,
        mnemonic = "CorsairGenerate",
        progress_message = "Generating Corsair outputs for %s" % ctx.label.name,
    )

    categorized = _categorize_outputs(file_outputs, dir_outputs)
    providers = [
        DefaultInfo(files = depset(outputs)),
        _make_corsair_info(file_outputs, dir_outputs, categorized),
        _make_output_groups(file_outputs, dir_outputs, categorized),
    ]
    verilog_info = _maybe_make_verilog_info(file_outputs, categorized)
    if verilog_info:
        providers.append(verilog_info)
    return providers

def _publish_destination_relpath(relpath, category, publish_root):
    mapped = relpath
    if "/" not in relpath and category in _PUBLISH_CATEGORY_DIRS:
        mapped = _path_join(_PUBLISH_CATEGORY_DIRS[category], relpath)
    if publish_root:
        return _path_join(publish_root, mapped)
    return mapped

def _workspace_relative_path(package, relpath):
    if package:
        return _path_join(package, relpath)
    return relpath

def _corsair_publish_impl(ctx):
    publish_root = ctx.attr.publish_root
    if publish_root:
        _validate_workspace_relative_path(publish_root, "publish_root")

    info = ctx.attr.src[CorsairInfo]
    package = ctx.attr.src.label.package
    launcher = ctx.actions.declare_file(ctx.label.name)

    lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        "if [[ -z \"${BUILD_WORKSPACE_DIRECTORY:-}\" ]]; then",
        "  echo \"error: BUILD_WORKSPACE_DIRECTORY is not set. Run this target with 'bazel run'.\" >&2",
        "  exit 1",
        "fi",
        "",
        "if [[ -n \"${RUNFILES_DIR:-}\" ]]; then",
        "  runfiles_dir=\"${RUNFILES_DIR}\"",
        "elif [[ -d \"$0.runfiles\" ]]; then",
        "  runfiles_dir=\"$0.runfiles\"",
        "else",
        "  echo \"error: failed to locate Bazel runfiles directory.\" >&2",
        "  exit 1",
        "fi",
        "",
        "runfiles_workspace=" + _shell_quote(ctx.workspace_name),
        "workspace_root=\"${runfiles_dir}/${runfiles_workspace}\"",
        "",
    ]

    for relpath in sorted(info.files.keys()):
        file = info.files[relpath]
        category = info.file_categories[relpath]
        dst_relpath = _workspace_relative_path(
            package,
            _publish_destination_relpath(relpath, category, publish_root),
        )
        lines.extend([
            "src_path=\"${workspace_root}/" + file.short_path + "\"",
            "dst_path=\"${BUILD_WORKSPACE_DIRECTORY}/" + dst_relpath + "\"",
            "mkdir -p \"$(dirname \"$dst_path\")\"",
            "cp \"$src_path\" \"$dst_path\"",
            "printf 'published %s\\n' " + _shell_quote(dst_relpath),
            "",
        ])

    for relpath in sorted(info.directories.keys()):
        directory = info.directories[relpath]
        category = info.directory_categories[relpath]
        dst_relpath = _workspace_relative_path(
            package,
            _publish_destination_relpath(relpath, category, publish_root),
        )
        lines.extend([
            "src_path=\"${workspace_root}/" + directory.short_path + "\"",
            "dst_path=\"${BUILD_WORKSPACE_DIRECTORY}/" + dst_relpath + "\"",
            "rm -rf \"$dst_path\"",
            "mkdir -p \"$(dirname \"$dst_path\")\"",
            "cp -R \"$src_path\" \"$dst_path\"",
            "printf 'published %s\\n' " + _shell_quote(dst_relpath),
            "",
        ])

    ctx.actions.write(launcher, "\n".join(lines), is_executable = True)

    runfiles = ctx.runfiles(files = info.all_files.to_list() + info.all_directories.to_list())
    return [DefaultInfo(executable = launcher, runfiles = runfiles)]

corsair_publish = rule(
    implementation = _corsair_publish_impl,
    attrs = {
        "src": attr.label(
            doc = "A corsair_generate, corsair_generate_raw, or corsair_workflow target to publish.",
            providers = [CorsairInfo],
            mandatory = True,
        ),
        "publish_root": attr.string(
            doc = "Optional subdirectory under the target package for checked-in outputs. Bare output names are categorized into hw/sw/doc.",
            default = "",
        ),
    },
    executable = True,
    doc = "Copy generated Corsair outputs from Bazel runfiles into repo-local check-in paths via bazel run.",
)

_corsair_generate_native_rule = rule(
    implementation = _corsair_generate_native_impl,
    attrs = {
        "regmap": attr.label(
            doc = "Register map input file (.yaml, .yml, .json, or .txt).",
            allow_single_file = True,
            mandatory = True,
        ),
        "csrconfig": attr.label(
            doc = "Optional native Corsair csrconfig override file for supported Bazel-native outputs.",
            allow_single_file = True,
        ),
        "base_address": attr.int(default = _DEFAULT_BASE_ADDRESS),
        "data_width": attr.int(default = _DEFAULT_DATA_WIDTH),
        "address_width": attr.int(default = _DEFAULT_ADDRESS_WIDTH),
        "register_reset": attr.string(default = _DEFAULT_REGISTER_RESET),
        "address_increment": attr.string(default = ""),
        "address_alignment": attr.string(default = _DEFAULT_ADDRESS_ALIGNMENT),
        "force_name_case": attr.string(default = ""),
        "rtl": attr.bool(default = True),
        "rtl_lang": attr.string(default = "verilog"),
        "interface": attr.string(default = _DEFAULT_INTERFACE),
        "read_filler": attr.int(default = _DEFAULT_READ_FILLER),
        "sv_pkg": attr.bool(default = True),
        "verilog_header": attr.bool(default = False),
        "c_header": attr.bool(default = True),
        "python_module": attr.bool(default = True),
        "markdown": attr.bool(default = False),
        "asciidoc": attr.bool(default = False),
        "json_dump": attr.bool(default = False),
        "yaml_dump": attr.bool(default = False),
        "txt_dump": attr.bool(default = False),
        "module_name": attr.string(default = ""),
        "prefix": attr.string(default = ""),
        "title": attr.string(default = _DEFAULT_TITLE),
        "print_images": attr.bool(default = True),
        "image_dir": attr.string(default = ""),
        "print_conventions": attr.bool(default = True),
        "rtl_out": attr.string(default = ""),
        "sv_pkg_out": attr.string(default = ""),
        "verilog_header_out": attr.string(default = ""),
        "c_header_out": attr.string(default = ""),
        "python_out": attr.string(default = ""),
        "markdown_out": attr.string(default = ""),
        "asciidoc_out": attr.string(default = ""),
        "json_out": attr.string(default = ""),
        "yaml_out": attr.string(default = ""),
        "txt_out": attr.string(default = ""),
        "targets": attr.string_list_dict(default = {}),
        "_runner": attr.label(
            default = _RUNNER,
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Internal implementation for the Bazel-native corsair_generate macro.",
    toolchains = ["@rules_python//python:toolchain_type"],
)

def _corsair_generate_raw_impl(ctx):
    file_outputs, dir_outputs = _collect_declared_outputs(ctx)

    args = ctx.actions.args()
    args.add("--mode", "config")
    args.add("--regmap", ctx.file.regmap.path)
    args.add("--csrconfig", ctx.file.csrconfig.path)

    for relpath in sorted(file_outputs.keys()):
        args.add("--output", "%s=%s" % (relpath, file_outputs[relpath].path))
    for relpath in sorted(dir_outputs.keys()):
        args.add("--output-dir", "%s=%s" % (relpath, dir_outputs[relpath].path))

    outputs = file_outputs.values() + dir_outputs.values()
    _run_runner_action(
        ctx = ctx,
        args = args,
        direct_inputs = [ctx.file.regmap, ctx.file.csrconfig],
        outputs = outputs,
        mnemonic = "CorsairGenerateRaw",
        progress_message = "Generating raw Corsair outputs for %s" % ctx.label.name,
    )

    categorized = _categorize_outputs(file_outputs, dir_outputs)
    providers = [
        DefaultInfo(files = depset(outputs)),
        _make_corsair_info(file_outputs, dir_outputs, categorized),
        _make_output_groups(file_outputs, dir_outputs, categorized),
    ]
    verilog_info = _maybe_make_verilog_info(file_outputs, categorized)
    if verilog_info:
        providers.append(verilog_info)
    return providers

corsair_generate_raw = rule(
    implementation = _corsair_generate_raw_impl,
    attrs = {
        "regmap": attr.label(
            doc = "Register map input file, for example regs.yaml.",
            allow_single_file = True,
            mandatory = True,
        ),
        "csrconfig": attr.label(
            doc = "Native Corsair csrconfig input file.",
            allow_single_file = True,
            mandatory = True,
        ),
        "outs": attr.output_list(
            doc = "Declared file outputs to copy out of the Corsair run. Use config paths or unique basenames.",
        ),
        "out_dirs": attr.string_list(
            doc = "Declared tree output directories to copy out of the Corsair run.",
            default = [],
        ),
        "_runner": attr.label(
            default = _RUNNER,
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Compatibility rule that runs a native csrconfig with explicitly declared outputs.",
    toolchains = ["@rules_python//python:toolchain_type"],
)

def _corsair_workflow_impl(ctx):
    file_outputs, dir_outputs = _collect_declared_outputs(ctx)

    args = ctx.actions.args()
    args.add("--mode", "workflow")
    args.add("--script", ctx.file.script.path)
    args.add("--function", ctx.attr.function)

    for script_arg in ctx.attr.args:
        args.add("--arg", script_arg)

    for src in ctx.files.srcs:
        args.add("--src", src.path)

    for data in ctx.files.data:
        args.add("--data", data.path)

    for import_root in ctx.attr.imports:
        args.add("--import-root", import_root)

    for key in sorted(ctx.attr.globcfg.keys()):
        args.add("--globcfg", "%s=%s" % (key, ctx.attr.globcfg[key]))

    for relpath in sorted(file_outputs.keys()):
        args.add("--output", "%s=%s" % (relpath, file_outputs[relpath].path))
    for relpath in sorted(dir_outputs.keys()):
        args.add("--output-dir", "%s=%s" % (relpath, dir_outputs[relpath].path))

    outputs = file_outputs.values() + dir_outputs.values()
    _run_runner_action(
        ctx = ctx,
        args = args,
        direct_inputs = [ctx.file.script] + ctx.files.srcs + ctx.files.data,
        outputs = outputs,
        mnemonic = "CorsairWorkflow",
        progress_message = "Generating Corsair workflow outputs for %s" % ctx.label.name,
    )

    categorized = _categorize_outputs(file_outputs, dir_outputs)
    providers = [
        DefaultInfo(files = depset(outputs)),
        _make_corsair_info(file_outputs, dir_outputs, categorized),
        _make_output_groups(file_outputs, dir_outputs, categorized),
    ]
    verilog_info = _maybe_make_verilog_info(file_outputs, categorized)
    if verilog_info:
        providers.append(verilog_info)
    return providers

corsair_workflow = rule(
    implementation = _corsair_workflow_impl,
    attrs = {
        "script": attr.label(
            doc = "Main Python workflow script. Must define generate(ctx) unless function overrides it.",
            allow_single_file = [".py"],
            mandatory = True,
        ),
        "srcs": attr.label_list(
            doc = "Additional Python sources imported by the workflow script.",
            allow_files = [".py"],
            default = [],
        ),
        "data": attr.label_list(
            doc = "Register map files and any other data consumed by the workflow script.",
            allow_files = True,
            default = [],
        ),
        "outs": attr.output_list(
            doc = "Declared file outputs generated by the workflow script.",
        ),
        "out_dirs": attr.string_list(
            doc = "Declared tree output directories generated by the workflow script.",
            default = [],
        ),
        "args": attr.string_list(
            doc = "Extra positional strings exposed to the workflow script as ctx.args.",
            default = [],
        ),
        "imports": attr.string_list(
            doc = "Extra Python import roots relative to the workflow script directory.",
            default = [],
        ),
        "globcfg": attr.string_dict(
            doc = "Initial Corsair global configuration overrides applied before the script runs.",
            default = {},
        ),
        "function": attr.string(
            doc = "Entrypoint function to call inside the workflow script.",
            default = "generate",
        ),
        "_runner": attr.label(
            default = _RUNNER,
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Run a user-authored Corsair Python workflow script to generate declared outputs.",
    toolchains = ["@rules_python//python:toolchain_type"],
)

def _corsair_snapshot_manifest_impl(ctx):
    info = ctx.attr.src[CorsairInfo]
    out = ctx.actions.declare_file(ctx.label.name + ".json")

    files = []
    for relpath in sorted(info.files.keys()):
        file = info.files[relpath]
        files.append({
            "relative_path": relpath,
            "short_path": file.short_path,
            "basename": file.basename,
            "category": info.file_categories[relpath],
        })

    directories = []
    for relpath in sorted(info.directories.keys()):
        directory = info.directories[relpath]
        directories.append({
            "relative_path": relpath,
            "short_path": directory.short_path,
            "basename": directory.basename,
            "category": info.directory_categories[relpath],
        })

    data = {
        "label": str(ctx.attr.src.label),
        "package": ctx.attr.src.label.package,
        "target_name": ctx.attr.src.label.name,
        "files": files,
        "directories": directories,
        "output_groups": {
            "rtl": [file.short_path for file in info.rtl.to_list()],
            "sv": [file.short_path for file in info.sv.to_list()],
            "headers": [file.short_path for file in info.vh.to_list()] + [file.short_path for file in info.c.to_list()],
            "c": [file.short_path for file in info.c.to_list()],
            "python": [file.short_path for file in info.py.to_list()],
            "docs": [file.short_path for file in info.docs.to_list()] + [directory.short_path for directory in info.doc_dirs.to_list()],
            "data": [file.short_path for file in info.data.to_list()],
            "all_generated": [file.short_path for file in info.all_files.to_list()] + [directory.short_path for directory in info.all_directories.to_list()],
        },
    }

    ctx.actions.write(out, _render_json(data) + "\n")
    return [DefaultInfo(files = depset([out]))]

corsair_snapshot_manifest = rule(
    implementation = _corsair_snapshot_manifest_impl,
    attrs = {
        "src": attr.label(
            doc = "A corsair_generate, corsair_generate_raw, or corsair_workflow target.",
            providers = [CorsairInfo],
            mandatory = True,
        ),
    },
    doc = "Emit a JSON manifest describing generated Bazel outputs for repo-local snapshot/update tooling.",
)

def _encode_optional_string(value):
    if value == None:
        return ""
    return value

def _encode_optional_scalar(value, attr_name):
    if value == None:
        return ""
    if type(value) == "int":
        return str(value)
    if type(value) == "string":
        return value
    fail("%s must be None, an int, or a string." % attr_name)

def corsair_generate(
        name,
        regmap,
        csrconfig = None,
        base_address = _DEFAULT_BASE_ADDRESS,
        data_width = _DEFAULT_DATA_WIDTH,
        address_width = _DEFAULT_ADDRESS_WIDTH,
        register_reset = _DEFAULT_REGISTER_RESET,
        address_increment = None,
        address_alignment = _DEFAULT_ADDRESS_ALIGNMENT,
        force_name_case = None,
        rtl = True,
        rtl_lang = "verilog",
        interface = _DEFAULT_INTERFACE,
        read_filler = _DEFAULT_READ_FILLER,
        sv_pkg = True,
        verilog_header = False,
        c_header = True,
        python_module = True,
        markdown = False,
        asciidoc = False,
        json_dump = False,
        yaml_dump = False,
        txt_dump = False,
        module_name = None,
        prefix = None,
        title = _DEFAULT_TITLE,
        print_images = True,
        image_dir = None,
        print_conventions = True,
        rtl_out = None,
        sv_pkg_out = None,
        verilog_header_out = None,
        c_header_out = None,
        python_out = None,
        markdown_out = None,
        asciidoc_out = None,
        json_out = None,
        yaml_out = None,
        txt_out = None,
        targets = None,
        publish = False,
        publish_name = None,
        publish_root = None,
        **kwargs):
    """Public Bazel-native Corsair rule.

    This macro keeps `corsair_generate` focused on deterministic Bazel outputs.
    Checked-in source snapshots can be handled via `corsair_publish`, or by
    setting `publish = True` to auto-create a runnable publish target.
    """
    if publish_name != None and not publish:
        fail("publish_name requires publish = True.")
    if publish_root != None and not publish:
        fail("publish_root requires publish = True.")

    _corsair_generate_native_rule(
        name = name,
        regmap = regmap,
        csrconfig = csrconfig,
        base_address = base_address,
        data_width = data_width,
        address_width = address_width,
        register_reset = register_reset,
        address_increment = _encode_optional_scalar(address_increment, "address_increment"),
        address_alignment = _encode_optional_scalar(address_alignment, "address_alignment"),
        force_name_case = _encode_optional_string(force_name_case),
        rtl = rtl,
        rtl_lang = rtl_lang,
        interface = interface,
        read_filler = read_filler,
        sv_pkg = sv_pkg,
        verilog_header = verilog_header,
        c_header = c_header,
        python_module = python_module,
        markdown = markdown,
        asciidoc = asciidoc,
        json_dump = json_dump,
        yaml_dump = yaml_dump,
        txt_dump = txt_dump,
        module_name = _encode_optional_string(module_name),
        prefix = _encode_optional_string(prefix),
        title = title,
        print_images = print_images,
        image_dir = _encode_optional_string(image_dir),
        print_conventions = print_conventions,
        rtl_out = _encode_optional_string(rtl_out),
        sv_pkg_out = _encode_optional_string(sv_pkg_out),
        verilog_header_out = _encode_optional_string(verilog_header_out),
        c_header_out = _encode_optional_string(c_header_out),
        python_out = _encode_optional_string(python_out),
        markdown_out = _encode_optional_string(markdown_out),
        asciidoc_out = _encode_optional_string(asciidoc_out),
        json_out = _encode_optional_string(json_out),
        yaml_out = _encode_optional_string(yaml_out),
        txt_out = _encode_optional_string(txt_out),
        targets = targets or {},
        **kwargs
    )

    if publish:
        resolved_publish_name = publish_name if publish_name != None else name + "_publish"
        if resolved_publish_name == name:
            fail("publish target name must differ from the generation target name.")
        corsair_publish(
            name = resolved_publish_name,
            src = ":" + name,
            publish_root = _encode_optional_string(publish_root),
        )

corsair_script_generate = corsair_workflow
