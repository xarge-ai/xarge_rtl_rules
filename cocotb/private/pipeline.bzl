# Copyright 2026 Xarge AI
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

"""CocoTB pipeline rules for xarge_rtl_rules."""

load("@rules_python//python:defs.bzl", "PyInfo")

CocotbCfgInfo = provider(
    doc = "Configuration for a CocoTB simulator pipeline.",
    fields = {
        "cfg_file": "JSON manifest describing the simulator selection.",
        "simulator": "Simulator name passed to the CocoTB runner.",
    },
)

CocotbBuildInfo = provider(
    doc = "Build output from the CocoTB compile stage.",
    fields = {
        "build_dir_tree": "Tree artifact containing simulator build outputs.",
        "hdl_library": "HDL library used for the compiled design.",
        "hdl_toplevel": "HDL toplevel module name used during build.",
        "simulator": "Simulator name used for the compiled design.",
        "stamp_file": "Marker file written when the build completes successfully.",
    },
)

def _json_file(ctx, filename, value):
    out = ctx.actions.declare_file(filename)
    ctx.actions.write(
        output = out,
        content = json.encode_indent(value) + "\n",
    )
    return out

def _file_entry(file, kind = ""):
    entry = {
        "basename": file.basename,
        "path": file.path,
        "short_path": file.short_path,
    }
    if kind:
        entry["kind"] = kind
    return entry

def _classify_generic_source(file):
    lowered = file.basename.lower()
    if lowered.endswith(".vlt"):
        return "verilator_control"
    if lowered.endswith(".vhd") or lowered.endswith(".vhdl"):
        return "vhdl"
    return "verilog"

def _append_source(entries, inputs, seen, file, kind):
    if file.path in seen:
        return
    seen[file.path] = True
    inputs.append(file)
    entries.append(_file_entry(file, kind = kind))

def _collect_source_inputs(ctx):
    seen = {}
    entries = []
    inputs = []

    for file in ctx.files.verilog_sources:
        _append_source(entries, inputs, seen, file, "verilog")
    for file in ctx.files.vhdl_sources:
        _append_source(entries, inputs, seen, file, "vhdl")
    for file in ctx.files.sources:
        _append_source(entries, inputs, seen, file, _classify_generic_source(file))

    return entries, inputs

def _module_name(file):
    if file.basename.endswith(".py"):
        return file.basename[:-3]
    return file.basename

def _test_module_entries(files):
    entries = []
    for file in files:
        entry = _file_entry(file)
        entry["module_name"] = _module_name(file)
        entries.append(entry)
    return entries

def _py_dep_sources(ctx):
    return depset(
        transitive = [
            dep[PyInfo].transitive_sources
            for dep in ctx.attr.deps
            if PyInfo in dep
        ],
    )

def _py_dep_entries(dep_sources):
    return [_file_entry(file) for file in dep_sources.to_list()]

def _optional_string(value):
    if value:
        return value
    return None

def _optional_list(value):
    if value:
        return value
    return None

def _timescale_value(value):
    if not value:
        return None
    if len(value) != 2:
        fail("timescale must contain exactly two entries, for example ['1ns', '1ps']")
    return value

def _cfg_manifest(ctx):
    simulator = ctx.attr.simulator.strip()
    if not simulator:
        fail("simulator must be a non-empty string")
    return {
        "label": str(ctx.label),
        "simulator": simulator,
    }

def _cocotb_cfg_impl(ctx):
    manifest = _cfg_manifest(ctx)
    cfg_file = _json_file(ctx, "{}.cfg.json".format(ctx.label.name), manifest)
    return [
        DefaultInfo(files = depset([cfg_file])),
        CocotbCfgInfo(
            simulator = manifest["simulator"],
            cfg_file = cfg_file,
        ),
    ]

def _build_plan(ctx, cfg_info, source_entries):
    plan = {
        "cfg_file": cfg_info.cfg_file.path,
        "hdl_library": ctx.attr.hdl_library,
        "hdl_toplevel": ctx.attr.hdl_toplevel,
        "label": str(ctx.label),
        "simulator": cfg_info.simulator,
        "sources": source_entries,
        "build_args": ctx.attr.build_args,
        "includes": ctx.attr.includes,
        "defines": ctx.attr.defines,
        "parameters": ctx.attr.parameters,
        "always": ctx.attr.always,
        "clean": ctx.attr.clean,
        "verbose": ctx.attr.verbose,
        "waves": ctx.attr.waves,
    }

    timescale = _timescale_value(ctx.attr.timescale)
    if timescale:
        plan["timescale"] = timescale

    log_file = _optional_string(ctx.attr.log_file)
    if log_file:
        plan["log_file"] = log_file

    return plan

def _cocotb_build_impl(ctx):
    cfg_info = ctx.attr.cfg[CocotbCfgInfo]
    source_entries, source_inputs = _collect_source_inputs(ctx)
    driver_files_to_run = ctx.attr._cocotb_driver[DefaultInfo].files_to_run
    driver_sources = depset(
        transitive = [
            ctx.attr._cocotb_driver[PyInfo].transitive_sources,
        ],
    )
    plan_file = _json_file(
        ctx,
        "{}.build.json".format(ctx.label.name),
        _build_plan(ctx, cfg_info, source_entries),
    )
    build_dir_tree = ctx.actions.declare_directory("{}_build".format(ctx.label.name))
    stamp_file = ctx.actions.declare_file("{}.build.ok".format(ctx.label.name))

    ctx.actions.run(
        executable = ctx.executable._cocotb_driver,
        arguments = [
            "build",
            "--plan",
            plan_file.path,
            "--build-dir",
            build_dir_tree.path,
            "--stamp-out",
            stamp_file.path,
        ],
        inputs = depset(
            direct = [cfg_info.cfg_file, plan_file] + source_inputs,
            transitive = [driver_sources],
        ),
        outputs = [build_dir_tree, stamp_file],
        tools = [driver_files_to_run],
        mnemonic = "CocotbBuild",
        progress_message = "Building CocoTB artifacts for {}".format(ctx.label),
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(files = depset([build_dir_tree, stamp_file])),
        CocotbBuildInfo(
            simulator = cfg_info.simulator,
            build_dir_tree = build_dir_tree,
            stamp_file = stamp_file,
            hdl_toplevel = ctx.attr.hdl_toplevel,
            hdl_library = ctx.attr.hdl_library,
        ),
    ]

def _test_plan(ctx, build_info, dep_entries):
    plan = {
        "build_hdl_library": build_info.hdl_library,
        "build_hdl_toplevel": build_info.hdl_toplevel,
        "hdl_toplevel": _optional_string(ctx.attr.hdl_toplevel) or build_info.hdl_toplevel,
        "hdl_toplevel_lang": ctx.attr.hdl_toplevel_lang,
        "hdl_toplevel_library": _optional_string(ctx.attr.hdl_toplevel_library) or build_info.hdl_library,
        "label": str(ctx.label),
        "simulator": build_info.simulator,
        "test_modules": _test_module_entries(ctx.files.test_module),
        "gpi_interfaces": ctx.attr.gpi_interfaces,
        "testcase": ctx.attr.testcase,
        "elab_args": ctx.attr.elab_args,
        "test_args": ctx.attr.test_args,
        "plusargs": ctx.attr.plusargs,
        "extra_env": ctx.attr.extra_env,
        "waves": ctx.attr.waves,
        "gui": ctx.attr.gui,
        "parameters": ctx.attr.parameters,
        "python_sources": dep_entries,
        "verbose": ctx.attr.verbose,
    }

    seed = _optional_string(ctx.attr.seed)
    if seed:
        plan["seed"] = seed

    timescale = _timescale_value(ctx.attr.timescale)
    if timescale:
        plan["timescale"] = timescale

    log_file = _optional_string(ctx.attr.log_file)
    if log_file:
        plan["log_file"] = log_file

    pre_cmd = _optional_list(ctx.attr.pre_cmd)
    if pre_cmd:
        plan["pre_cmd"] = pre_cmd

    test_filter = _optional_string(ctx.attr.test_filter)
    if test_filter:
        plan["test_filter"] = test_filter

    return plan

def _test_script(ctx, results_xml, failed_tests_file):
    script = ctx.actions.declare_file("{}_test.sh".format(ctx.label.name))
    content = """#!/usr/bin/env bash
set -euo pipefail

RESULTS_SHORT_PATH="{results_short_path}"
FAILED_TESTS_SHORT_PATH="{failed_tests_short_path}"
RUNFILE_PATH=""
FAILED_TESTS_RUNFILE_PATH=""
if [[ -n "${{TEST_SRCDIR:-}}" && -n "${{TEST_WORKSPACE:-}}" ]]; then
  RUNFILE_PATH="${{TEST_SRCDIR}}/${{TEST_WORKSPACE}}/${{RESULTS_SHORT_PATH}}"
  FAILED_TESTS_RUNFILE_PATH="${{TEST_SRCDIR}}/${{TEST_WORKSPACE}}/${{FAILED_TESTS_SHORT_PATH}}"
fi

if [[ -n "$RUNFILE_PATH" && -f "$RUNFILE_PATH" ]]; then
  cp "$RUNFILE_PATH" "${{XML_OUTPUT_FILE:-results.xml}}"
elif [[ -f "$RESULTS_SHORT_PATH" ]]; then
  cp "$RESULTS_SHORT_PATH" "${{XML_OUTPUT_FILE:-results.xml}}"
else
  echo "missing CocoTB results file: $RESULTS_SHORT_PATH" >&2
  exit 1
fi

FAILED_TESTS_PATH=""
if [[ -n "$FAILED_TESTS_RUNFILE_PATH" && -f "$FAILED_TESTS_RUNFILE_PATH" ]]; then
  FAILED_TESTS_PATH="$FAILED_TESTS_RUNFILE_PATH"
elif [[ -f "$FAILED_TESTS_SHORT_PATH" ]]; then
  FAILED_TESTS_PATH="$FAILED_TESTS_SHORT_PATH"
else
  echo "missing CocoTB failed-tests file: $FAILED_TESTS_SHORT_PATH" >&2
  exit 1
fi

FAILED_TESTS="$(tr -d '[:space:]' < "$FAILED_TESTS_PATH")"
if [[ -z "$FAILED_TESTS" ]]; then
  echo "empty CocoTB failed-tests file: $FAILED_TESTS_PATH" >&2
  exit 1
fi

if [[ "$FAILED_TESTS" != "0" ]]; then
  exit 1
fi
""".format(
        results_short_path = results_xml.short_path,
        failed_tests_short_path = failed_tests_file.short_path,
    )
    ctx.actions.write(output = script, content = content, is_executable = True)
    return script

def _cocotb_test_impl(ctx):
    build_info = ctx.attr.build[CocotbBuildInfo]
    dep_sources = _py_dep_sources(ctx)
    driver_files_to_run = ctx.attr._cocotb_driver[DefaultInfo].files_to_run
    driver_sources = depset(
        transitive = [
            ctx.attr._cocotb_driver[PyInfo].transitive_sources,
        ],
    )
    plan_file = _json_file(
        ctx,
        "{}.test.json".format(ctx.label.name),
        _test_plan(ctx, build_info, _py_dep_entries(dep_sources)),
    )
    results_xml = ctx.actions.declare_file("{}.results.xml".format(ctx.label.name))
    failed_tests_file = ctx.actions.declare_file("{}.failed_tests.txt".format(ctx.label.name))
    artifacts_dir = ctx.actions.declare_directory("{}.artifacts".format(ctx.label.name))

    ctx.actions.run(
        executable = ctx.executable._cocotb_driver,
        arguments = [
            "test",
            "--plan",
            plan_file.path,
            "--build-dir",
            build_info.build_dir_tree.path,
            "--results-xml-out",
            results_xml.path,
            "--failed-tests-out",
            failed_tests_file.path,
            "--artifacts-dir",
            artifacts_dir.path,
        ],
        inputs = depset(
            direct = [
                build_info.build_dir_tree,
                build_info.stamp_file,
                plan_file,
            ] + ctx.files.test_module,
            transitive = [
                dep_sources,
                driver_sources,
            ],
        ),
        outputs = [results_xml, failed_tests_file, artifacts_dir],
        tools = [driver_files_to_run],
        mnemonic = "CocotbTest",
        progress_message = "Running CocoTB test {}".format(ctx.label),
        use_default_shell_env = True,
    )

    test_script = _test_script(ctx, results_xml, failed_tests_file)
    return [
        DefaultInfo(
            executable = test_script,
            files = depset([results_xml, failed_tests_file, artifacts_dir]),
            runfiles = ctx.runfiles(files = [results_xml, failed_tests_file]),
        ),
    ]

cocotb_cfg = rule(
    implementation = _cocotb_cfg_impl,
    attrs = {
        "simulator": attr.string(
            default = "verilator",
            doc = "Simulator name passed through to CocoTB's runner API.",
        ),
    },
    doc = "Create a simulator configuration target for the CocoTB pipeline.",
)

cocotb_build = rule(
    implementation = _cocotb_build_impl,
    attrs = {
        "cfg": attr.label(
            mandatory = True,
            providers = [CocotbCfgInfo],
            doc = "Configuration target created by cocotb_cfg.",
        ),
        "sources": attr.label_list(
            allow_files = [".v", ".sv", ".vhd", ".vhdl", ".vlt"],
            default = [],
            doc = "Language-agnostic HDL sources. Files are classified by extension.",
        ),
        "verilog_sources": attr.label_list(
            allow_files = [".v", ".sv"],
            default = [],
            doc = "Verilog or SystemVerilog source files.",
        ),
        "vhdl_sources": attr.label_list(
            allow_files = [".vhd", ".vhdl"],
            default = [],
            doc = "VHDL source files.",
        ),
        "includes": attr.string_list(
            default = [],
            doc = "Include directories passed to the simulator build step.",
        ),
        "defines": attr.string_dict(
            default = {},
            doc = "Preprocessor defines for the simulator build step.",
        ),
        "parameters": attr.string_dict(
            default = {},
            doc = "Verilog parameters or VHDL generics.",
        ),
        "build_args": attr.string_list(
            default = [],
            doc = "Extra simulator-specific build arguments.",
        ),
        "hdl_toplevel": attr.string(
            mandatory = True,
            doc = "Name of the HDL toplevel module or entity.",
        ),
        "hdl_library": attr.string(
            default = "top",
            doc = "HDL library used for compilation.",
        ),
        "always": attr.bool(
            default = False,
            doc = "Force the simulator build step even when cached artifacts exist.",
        ),
        "clean": attr.bool(
            default = False,
            doc = "Clean the simulator build directory before compilation.",
        ),
        "verbose": attr.bool(
            default = False,
            doc = "Enable verbose simulator output.",
        ),
        "waves": attr.bool(
            default = False,
            doc = "Enable waveform support during build.",
        ),
        "timescale": attr.string_list(
            default = [],
            doc = "Optional [unit, precision] timescale pair.",
        ),
        "log_file": attr.string(
            default = "",
            doc = "Optional simulator build log file name.",
        ),
        "_cocotb_driver": attr.label(
            default = "//cocotb/tools:cocotb_driver",
            executable = True,
            cfg = "exec",
        ),
    },
    doc = "Compile HDL sources for reuse across one or more CocoTB tests.",
)

cocotb_test = rule(
    implementation = _cocotb_test_impl,
    attrs = {
        "build": attr.label(
            mandatory = True,
            providers = [CocotbBuildInfo],
            doc = "Build target created by cocotb_build.",
        ),
        "test_module": attr.label_list(
            allow_files = [".py"],
            mandatory = True,
            doc = "Python test modules containing cocotb tests.",
        ),
        "deps": attr.label_list(
            default = [],
            providers = [PyInfo],
            doc = "Additional Python dependencies needed by the test modules.",
        ),
        "hdl_toplevel": attr.string(
            default = "",
            doc = "Optional override for the HDL toplevel module name.",
        ),
        "hdl_toplevel_library": attr.string(
            default = "",
            doc = "Optional override for the HDL toplevel library.",
        ),
        "hdl_toplevel_lang": attr.string(
            default = "verilog",
            values = ["verilog", "vhdl"],
            doc = "Language of the HDL toplevel.",
        ),
        "gpi_interfaces": attr.string_list(
            default = [],
            doc = "Optional list of GPI interfaces.",
        ),
        "testcase": attr.string_list(
            default = [],
            doc = "Optional subset of testcase names to run.",
        ),
        "seed": attr.string(
            default = "",
            doc = "Optional random seed passed to the test run.",
        ),
        "elab_args": attr.string_list(
            default = [],
            doc = "Extra elaboration arguments.",
        ),
        "test_args": attr.string_list(
            default = [],
            doc = "Extra simulator runtime arguments.",
        ),
        "plusargs": attr.string_list(
            default = [],
            doc = "Simulator plusargs.",
        ),
        "extra_env": attr.string_dict(
            default = {},
            doc = "Extra environment variables to expose during the test run.",
        ),
        "waves": attr.bool(
            default = False,
            doc = "Enable waveform dumping for the test run.",
        ),
        "gui": attr.bool(
            default = False,
            doc = "Run the simulator in GUI mode when supported.",
        ),
        "parameters": attr.string_dict(
            default = {},
            doc = "Runtime parameter overrides for the test run.",
        ),
        "verbose": attr.bool(
            default = False,
            doc = "Enable verbose runtime output.",
        ),
        "timescale": attr.string_list(
            default = [],
            doc = "Optional [unit, precision] timescale pair for the run.",
        ),
        "log_file": attr.string(
            default = "",
            doc = "Optional simulator runtime log file name.",
        ),
        "pre_cmd": attr.string_list(
            default = [],
            doc = "Optional commands run by the simulator before test execution.",
        ),
        "test_filter": attr.string(
            default = "",
            doc = "Optional regular expression filter for test names.",
        ),
        "_cocotb_driver": attr.label(
            default = "//cocotb/tools:cocotb_driver",
            executable = True,
            cfg = "exec",
        ),
    },
    test = True,
    doc = "Run CocoTB tests against a reusable cocotb_build output.",
)
