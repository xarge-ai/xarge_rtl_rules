# Copyright 2023 Antmicro
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
Declarative SymbiYosys formal verification rule.

Generates .sby configuration at test time from BUILD.bazel parameters,
eliminating the need for hand-written .sby files.

Usage:

    load("@generva_rtl_rules//formal:defs.bzl", "sby_test")

    sby_test(
        name = "formal_sync_fifo",
        properties = "sync_fifo_properties.sv",
        rtl_deps = ["//rtl/fifo:sync_fifo_sv"],
        bmc_depth = 40,
        prove = True,
    )
"""

load("//rtl:providers.bzl", "VerilogInfo", "collect_verilog_srcs")

_RUN_SBY = Label("//formal:run_sby.py")

def _copy_file_impl(ctx):
    """Copy a file using expand_template — avoids sandbox symlink issues."""
    out = ctx.actions.declare_file(ctx.attr.out_name)
    ctx.actions.expand_template(
        template = ctx.file.src,
        output = out,
        substitutions = {},
    )
    return [DefaultInfo(files = depset([out]))]

_copy_file = rule(
    implementation = _copy_file_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
        "out_name": attr.string(mandatory = True),
    },
)

def _dedupe_strings(values):
    seen = {}
    result = []
    for value in values:
        if value in seen:
            continue
        seen[value] = True
        result.append(value)
    return result


def _is_verilog_compile_source(file):
    lowered = file.basename.lower()
    return lowered.endswith(".v") or lowered.endswith(".sv")


def _collect_rtl_files_impl(ctx):
    all_files = depset(collect_verilog_srcs(ctx.attr.deps))
    all_file_list = all_files.to_list()
    compile_files = depset([file for file in all_file_list if _is_verilog_compile_source(file)])
    return [
        DefaultInfo(
            files = compile_files,
            runfiles = ctx.runfiles(files = all_file_list),
        ),
    ]


_collect_rtl_files = rule(
    implementation = _collect_rtl_files_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "RTL dependency targets, filegroups, or raw source files",
            allow_files = True,
            default = [],
        ),
    },
)


def _collect_rtl_metadata_impl(ctx):
    includes = []
    defines = []

    for dep in ctx.attr.deps:
        if VerilogInfo not in dep:
            continue
        includes.extend(dep[VerilogInfo].includes.to_list())
        defines.extend(dep[VerilogInfo].defines.to_list())

    metadata = {
        "includes": _dedupe_strings(includes),
        "defines": _dedupe_strings(defines),
    }
    out = ctx.actions.declare_file("{}.json".format(ctx.label.name))
    ctx.actions.write(
        output = out,
        content = json.encode_indent(metadata) + "\n",
    )
    return [
        DefaultInfo(
            files = depset([out]),
            runfiles = ctx.runfiles(files = [out]),
        ),
    ]


_collect_rtl_metadata = rule(
    implementation = _collect_rtl_metadata_impl,
    attrs = {
        "deps": attr.label_list(
            doc = "RTL dependency targets, filegroups, or raw source files",
            allow_files = True,
            default = [],
        ),
    },
)

def sby_test(
        name,
        properties,
        rtl_deps,
        bmc_depth = 20,
        prove = False,
        multiclock = False,
        bmc_engine = None,
        prove_engine = None,
        prove_depth = None,
        defines = [],
        flatten = True,
        top = None,
        tags = None,
        **kwargs):
    """Declare a SymbiYosys formal verification test.

    Args:
        name: Test target name.
        properties: SVA properties/bind file (.sv).
        rtl_deps: RTL dependency labels, including raw source files, filegroups, or verilog_library targets.
        bmc_depth: Bounded model check depth (default: 20).
        prove: Enable unbounded prove task (default: False).
        multiclock: Enable multiclock for CDC designs (default: False).
        bmc_engine: BMC engine (default: "smtbmc").
        prove_engine: Prove engine (default: "abc pdr"; "smtbmc" if multiclock).
        prove_depth: K-induction depth for smtbmc prove (default: bmc_depth).
        defines: Additional preprocessor defines for RTL and properties (for example, ["VERILATOR"]).
        flatten: Pass -flatten to yosys prep (default: True).
        top: Top module name (default: properties filename stem).
        tags: Additional tags. "formal" is always included.
        **kwargs: Extra arguments forwarded to py_test.
    """
    if bmc_engine == None:
        bmc_engine = "smtbmc"
    if prove_engine == None:
        prove_engine = "smtbmc" if multiclock else "abc pdr"

    all_tags = ["formal"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    args = [
        "--bmc-depth",
        str(bmc_depth),
        "--bmc-engine",
        bmc_engine.replace(" ", ":"),
    ]
    if prove:
        args.extend(["--prove", "--prove-engine", prove_engine.replace(" ", ":")])
        if prove_depth != None:
            args.extend(["--prove-depth", str(prove_depth)])
    if multiclock:
        args.append("--multiclock")
    if not flatten:
        args.append("--no-flatten")
    if top:
        args.extend(["--top", top])
    for d in defines:
        args.extend(["--define", d])

    collector_target = name + "_rtl_files"
    metadata_target = name + "_rtl_metadata"
    local_runner = name + "_run_sby.py"
    copy_target = name + "_copy_runner"

    _collect_rtl_files(
        name = collector_target,
        deps = rtl_deps,
        tags = all_tags,
    )

    _collect_rtl_metadata(
        name = metadata_target,
        deps = rtl_deps,
        tags = all_tags,
    )

    args.extend(["--properties", "$(location {})".format(properties)])
    args.extend(["--rtl", "$(locations :{})".format(collector_target)])
    args.extend(["--rtl-metadata", "$(location :{})".format(metadata_target)])

    _copy_file(
        name = copy_target,
        src = _RUN_SBY,
        out_name = local_runner,
        tags = all_tags,
    )

    native.py_test(
        name = name,
        srcs = [":" + copy_target],
        main = local_runner,
        precompile = "disabled",
        args = args,
        data = [properties, ":" + collector_target, ":" + metadata_target],
        tags = all_tags,
        **kwargs
    )
