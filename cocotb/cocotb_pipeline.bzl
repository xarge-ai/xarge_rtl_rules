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
Pipeline-based CocoTB rules for build/test separation.

This enables building once and running multiple tests against the same build output,
with proper Bazel caching. Use these rules when you need to run multiple test
configurations against the same HDL build.

For single test scenarios, the legacy cocotb_build_test from cocotb_tools.bzl
may be more convenient.
"""

load("@rules_python//python:defs.bzl", "PyInfo")

# Providers for passing information between pipeline stages

CocotbCfgInfo = provider(
    "Configuration for CocoTB simulator pipeline",
    fields = {
        "simulator": "Simulator name (e.g., 'verilator', 'icarus')",
        "cfg_file": "Configuration file with simulator settings",
    },
)

CocotbBuildInfo = provider(
    "Build output from CocoTB build stage",
    fields = {
        "simulator": "Simulator name used for build",
        "build_dir_tree": "Directory tree artifact containing build outputs",
        "stamp_file": "Stamp file indicating successful build",
        "hdl_toplevel": "HDL toplevel module name",
        "hdl_library": "HDL library name",
    },
)

# Helper functions

def _write_kwargs_file(ctx, kwargs, filename):
    """
    Write kwargs to a file in a simple format that Python can parse.
    
    Since Starlark doesn't handle recursive JSON well, we'll write in a 
    format that Python can easily convert to proper JSON.
    """
    
    # Convert to a simple key=value format that Python can parse
    lines = []
    for k, v in kwargs.items():
        # Convert value to string representation
        if type(v) == "list":
            # Convert list to Python list string
            items = []
            for item in v:
                if type(item) == "string":
                    items.append('"{}"'.format(item.replace('\\', '\\\\').replace('"', '\\"')))
                else:
                    items.append(str(item))
            value_str = "[{}]".format(",".join(items))
        elif type(v) == "dict":
            # Convert dict to Python dict string
            items = []
            for dk in v:
                dv = v[dk]
                if type(dv) == "string":
                    dv_str = '"{}"'.format(dv.replace('\\', '\\\\').replace('"', '\\"'))
                else:
                    dv_str = str(dv)
                if type(dk) == "string":
                    dk_str = '"{}"'.format(dk.replace('\\', '\\\\').replace('"', '\\"'))
                else:
                    dk_str = str(dk)
                items.append("{}:{}".format(dk_str, dv_str))
            value_str = "{{{0}}}".format(",".join(items))
        elif type(v) == "string":
            value_str = '"{}"'.format(v.replace('\\', '\\\\').replace('"', '\\"'))
        elif type(v) == "bool":
            value_str = "true" if v else "false"
        else:
            value_str = str(v)
        
        lines.append("{}={}".format(k, value_str))
    
    content = "\n".join(lines)
    
    kwargs_file = ctx.actions.declare_file(filename)
    ctx.actions.write(
        output = kwargs_file,
        content = content,
    )
    
    return kwargs_file

def _collect_file_paths(files, prefix = ""):
    """Collect file paths from a list of File objects, optionally with prefix tag."""
    paths = []
    for f in files:
        path = f.path if hasattr(f, "path") else f.short_path
        if prefix:
            paths.append("{}:{}".format(prefix, path))
        else:
            paths.append(path)
    return paths

def _merge_file_lists(*file_lists):
    """Merge multiple lists of files, removing duplicates."""
    seen = {}
    result = []
    for file_list in file_lists:
        for f in file_list:
            path = f.path if hasattr(f, "path") else f.short_path
            if path not in seen:
                seen[path] = True
                result.append(f)
    return result

# Rule implementations

def _cocotb_cfg_impl(ctx):
    """Implementation for cocotb_cfg rule."""
    
    # Create a simple configuration file (simple key=value format)
    cfg_content = 'simulator="{0}"\nversion="1.0"\n'.format(ctx.attr.simulator)
    
    cfg_file = ctx.actions.declare_file("{}.cfg.txt".format(ctx.label.name))
    ctx.actions.write(
        output = cfg_file,
        content = cfg_content,
    )
    
    return [
        DefaultInfo(files = depset([cfg_file])),
        CocotbCfgInfo(
            simulator = ctx.attr.simulator,
            cfg_file = cfg_file,
        ),
    ]

def _cocotb_build_impl(ctx):
    """Implementation for cocotb_build rule."""
    
    cfg_info = ctx.attr.cfg[CocotbCfgInfo]
    simulator = cfg_info.simulator
    
    # Collect all source files
    verilog_files = ctx.files.verilog_sources
    vhdl_files = ctx.files.vhdl_sources
    generic_files = ctx.files.sources
    all_source_files = _merge_file_lists(verilog_files, vhdl_files, generic_files)
    
    # Create tagged source paths for the driver
    tagged_sources = []
    tagged_sources.extend(_collect_file_paths(verilog_files, "VERILOG"))
    tagged_sources.extend(_collect_file_paths(vhdl_files, "VHDL"))
    tagged_sources.extend(_collect_file_paths(generic_files))  # Untagged = Verilog
    
    # Prepare build kwargs for JSON serialization
    build_kwargs = {
        "hdl_library": ctx.attr.hdl_library,
        "sources": tagged_sources,
        "includes": ctx.attr.includes,
        "defines": ctx.attr.defines,
        "parameters": ctx.attr.parameters,
        "build_args": ctx.attr.build_args,
        "hdl_toplevel": ctx.attr.hdl_toplevel,
        "always": ctx.attr.always,
        "clean": ctx.attr.clean,
        "verbose": ctx.attr.verbose,
        "waves": ctx.attr.waves,
    }
    
    # Add optional parameters
    if ctx.attr.timescale:
        build_kwargs["timescale"] = ctx.attr.timescale
    if ctx.attr.log_file:
        build_kwargs["log_file"] = ctx.attr.log_file
    
    # Create build kwargs file  
    build_kwargs_file = _write_kwargs_file(ctx, build_kwargs, "{}.build_kwargs.txt".format(ctx.label.name))
    
    # Declare output artifacts
    build_dir_tree = ctx.actions.declare_directory("{}_build".format(ctx.label.name))
    stamp_file = ctx.actions.declare_file("{}.build.ok".format(ctx.label.name))
    
    # Get python toolchain
    py_toolchain = ctx.toolchains["@rules_python//python:toolchain_type"].py3_runtime
    
    # Run the build directly with environment inheritance
    ctx.actions.run(
        executable = ctx.executable._cocotb_driver,
        arguments = [
            "--mode", "build",
            "--simulator", simulator,
            "--build-dir", build_dir_tree.path,
            "--build-kwargs-txt", build_kwargs_file.path,
            "--stamp-out", stamp_file.path
        ],
        inputs = depset(
            direct = [cfg_info.cfg_file, build_kwargs_file] + all_source_files,
            transitive = [
                ctx.attr._cocotb_driver[PyInfo].transitive_sources,
                py_toolchain.files,
            ],
        ),
        outputs = [build_dir_tree, stamp_file],
        mnemonic = "CocotbBuild",
        progress_message = "Building CocoTB simulation for {}".format(ctx.label.name),
        use_default_shell_env = True,  # Inherit PATH and other environment variables
    )
    
    return [
        DefaultInfo(files = depset([build_dir_tree, stamp_file])),
        CocotbBuildInfo(
            simulator = simulator,
            build_dir_tree = build_dir_tree,
            stamp_file = stamp_file,
            hdl_toplevel = ctx.attr.hdl_toplevel,
            hdl_library = ctx.attr.hdl_library,
        ),
    ]

def _cocotb_test_impl(ctx):
    """Implementation for cocotb_test rule."""
    
    build_info = ctx.attr.build[CocotbBuildInfo]
    simulator = build_info.simulator
    
    # Use hdl_toplevel from build if not overridden
    hdl_toplevel = ctx.attr.hdl_toplevel or build_info.hdl_toplevel
    hdl_toplevel_library = ctx.attr.hdl_toplevel_library or build_info.hdl_library
    
    # Collect test module files
    test_module_files = ctx.files.test_module
    test_module_names = []
    for f in test_module_files:
        name = f.basename
        if name.endswith(".py"):
            name = name[:-3]  # Remove .py extension
        test_module_names.append(name)
    
    # Prepare test kwargs for JSON serialization
    test_kwargs = {
        "test_module": test_module_names,
        "hdl_toplevel": hdl_toplevel,
        "hdl_toplevel_library": hdl_toplevel_library,
        "hdl_toplevel_lang": ctx.attr.hdl_toplevel_lang,
        "gpi_interfaces": ctx.attr.gpi_interfaces,
        "testcase": ctx.attr.testcase,
        "elab_args": ctx.attr.elab_args,
        "test_args": ctx.attr.test_args,
        "plusargs": ctx.attr.plusargs,
        "extra_env": ctx.attr.extra_env,
        "waves": ctx.attr.waves,
        "gui": ctx.attr.gui,
        "parameters": ctx.attr.parameters,
        "verbose": ctx.attr.verbose,
    }
    
    # Add optional parameters
    if ctx.attr.seed:
        test_kwargs["seed"] = ctx.attr.seed
    if ctx.attr.timescale:
        test_kwargs["timescale"] = ctx.attr.timescale
    if ctx.attr.log_file:
        test_kwargs["log_file"] = ctx.attr.log_file
    if ctx.attr.pre_cmd:
        test_kwargs["pre_cmd"] = ctx.attr.pre_cmd
    if ctx.attr.test_filter:
        test_kwargs["test_filter"] = ctx.attr.test_filter
    
    # Create test kwargs file
    test_kwargs_file = _write_kwargs_file(ctx, test_kwargs, "{}.test_kwargs.txt".format(ctx.label.name))
    
    # Create test directory with test modules  
    # Based on CocoTB runner source, the test should run from test_dir
    # which contains the Python test modules, with build_dir referencing
    # the compiled simulation artifacts
    test_dir = ctx.actions.declare_directory("{}_test_dir".format(ctx.label.name))
    
    # Copy test modules to the test directory  
    ctx.actions.run_shell(
        command = """
        mkdir -p {test_dir}
        for module in {modules}; do
            cp "$module" {test_dir}/
        done
        """.format(
            test_dir = test_dir.path,
            modules = " ".join([f.path for f in test_module_files]),
        ),
        inputs = test_module_files,
        outputs = [test_dir],
        mnemonic = "CreateTestDir",
        progress_message = "Creating test directory for {}".format(ctx.label.name),
    )
    
    # Declare output artifacts
    results_xml = ctx.actions.declare_file("{}.results.xml".format(ctx.label.name))
    
    # Get python toolchain
    py_toolchain = ctx.toolchains["@rules_python//python:toolchain_type"].py3_runtime
    
    # Collect all Python dependencies
    py_deps = []
    for dep in ctx.attr.deps:
        if PyInfo in dep:
            py_deps.append(dep[PyInfo].transitive_sources)
    
    # Run the test directly with environment inheritance
    # Based on CocoTB runner: test runs from test_dir, references build_dir
    ctx.actions.run(
        executable = ctx.executable._cocotb_driver,
        arguments = [
            "--mode", "test",
            "--simulator", simulator,
            "--build-dir", build_info.build_dir_tree.path,
            "--test-dir", test_dir.path,
            "--test-kwargs-txt", test_kwargs_file.path,
            "--results-xml-out", results_xml.path
        ],
        inputs = depset(
            direct = [
                build_info.build_dir_tree,
                build_info.stamp_file,
                test_kwargs_file,
                test_dir,
            ],
            transitive = [
                ctx.attr._cocotb_driver[PyInfo].transitive_sources,
                py_toolchain.files,
            ] + py_deps,
        ),
        outputs = [results_xml],
        mnemonic = "CocotbTest",
        progress_message = "Running CocoTB test for {}".format(ctx.label.name),
        use_default_shell_env = True,  # Inherit PATH and other environment variables
    )
    
    # Create test script for Bazel test execution
    test_script = ctx.actions.declare_file("{}_test.sh".format(ctx.label.name))
    test_script_content = """#!/bin/bash
set -e

# Copy results.xml to expected location
if [ -f "{results_xml}" ]; then
    cp "{results_xml}" "${{XML_OUTPUT_FILE:-results.xml}}"
fi

# Test passes if we get here (driver exits with proper code)
echo "Test completed successfully"
""".format(results_xml = results_xml.short_path)
    
    ctx.actions.write(
        output = test_script,
        content = test_script_content,
        is_executable = True,
    )
    
    # Return test information
    return [
        DefaultInfo(
            executable = test_script,
            files = depset([results_xml]),
            runfiles = ctx.runfiles(files = [results_xml]),
        ),
    ]

# Rule definitions

cocotb_cfg = rule(
    implementation = _cocotb_cfg_impl,
    attrs = {
        "simulator": attr.string(
            doc = "Simulator name (e.g., 'verilator', 'icarus', 'questa')",
            default = "verilator",
            values = ["ghdl", "icarus", "questa", "verilator", "vcs"],
        ),
    },
    doc = "Configure simulator for CocoTB pipeline",
)

cocotb_build = rule(
    implementation = _cocotb_build_impl,
    attrs = {
        "cfg": attr.label(
            doc = "CocoTB configuration (cocotb_cfg target)",
            providers = [CocotbCfgInfo],
            mandatory = True,
        ),
        "sources": attr.label_list(
            doc = "Language-agnostic source files (assumed Verilog if not tagged)",
            allow_files = [".v", ".sv", ".vhd", ".vhdl", ".vlt"],
            default = [],
        ),
        "verilog_sources": attr.label_list(
            doc = "Verilog source files",
            allow_files = [".v", ".sv"],
            default = [],
        ),
        "vhdl_sources": attr.label_list(
            doc = "VHDL source files",
            allow_files = [".vhd", ".vhdl"],
            default = [],
        ),
        "includes": attr.string_list(
            doc = "Include directories",
            default = [],
        ),
        "defines": attr.string_dict(
            doc = "Preprocessor defines",
            default = {},
        ),
        "parameters": attr.string_dict(
            doc = "Verilog parameters or VHDL generics",
            default = {},
        ),
        "build_args": attr.string_list(
            doc = "Extra build arguments for the simulator",
            default = [],
        ),
        "hdl_toplevel": attr.string(
            doc = "HDL toplevel module name",
            mandatory = True,
        ),
        "hdl_library": attr.string(
            doc = "HDL library name",
            default = "top",
        ),
        "always": attr.bool(
            doc = "Always run the build step",
            default = False,
        ),
        "clean": attr.bool(
            doc = "Clean build directory before building",
            default = False,
        ),
        "verbose": attr.bool(
            doc = "Enable verbose output",
            default = False,
        ),
        "waves": attr.bool(
            doc = "Enable waveform recording",
            default = False,
        ),
        "timescale": attr.string_list(
            doc = "Time unit and precision (e.g., ['1ns', '1ps'])",
            default = [],
        ),
        "log_file": attr.string(
            doc = "Build log file name",
            default = "",
        ),
        "_cocotb_driver": attr.label(
            default = "//tools:cocotb_driver",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = ["@rules_python//python:toolchain_type"],
    doc = "Build HDL simulation using CocoTB",
)

cocotb_test = rule(
    implementation = _cocotb_test_impl,
    attrs = {
        "build": attr.label(
            doc = "CocoTB build target (cocotb_build)",
            providers = [CocotbBuildInfo],
            mandatory = True,
        ),
        "test_module": attr.label_list(
            doc = "Python test modules",
            allow_files = [".py"],
            mandatory = True,
        ),
        "deps": attr.label_list(
            doc = "Python dependencies",
            providers = [PyInfo],
            default = [],
        ),
        "hdl_toplevel": attr.string(
            doc = "HDL toplevel module (overrides build setting)",
            default = "",
        ),
        "hdl_toplevel_library": attr.string(
            doc = "HDL toplevel library (overrides build setting)",
            default = "",
        ),
        "hdl_toplevel_lang": attr.string(
            doc = "HDL toplevel language",
            default = "verilog",
            values = ["verilog", "vhdl"],
        ),
        "gpi_interfaces": attr.string_list(
            doc = "GPI interfaces to use",
            default = [],
        ),
        "testcase": attr.string_list(
            doc = "Specific testcases to run",
            default = [],
        ),
        "seed": attr.string(
            doc = "Random seed",
            default = "",
        ),
        "elab_args": attr.string_list(
            doc = "Elaboration arguments",
            default = [],
        ),
        "test_args": attr.string_list(
            doc = "Test arguments",
            default = [],
        ),
        "plusargs": attr.string_list(
            doc = "Simulator plusargs",
            default = [],
        ),
        "extra_env": attr.string_dict(
            doc = "Extra environment variables",
            default = {},
        ),
        "waves": attr.bool(
            doc = "Enable waveform recording",
            default = False,
        ),
        "gui": attr.bool(
            doc = "Run with GUI",
            default = False,
        ),
        "parameters": attr.string_dict(
            doc = "Runtime parameters",
            default = {},
        ),
        "verbose": attr.bool(
            doc = "Enable verbose output",
            default = False,
        ),
        "timescale": attr.string_list(
            doc = "Time unit and precision",
            default = [],
        ),
        "log_file": attr.string(
            doc = "Test log file name",
            default = "",
        ),
        "pre_cmd": attr.string_list(
            doc = "Commands to run before simulation",
            default = [],
        ),
        "test_filter": attr.string(
            doc = "Regular expression to filter test names",
            default = "",
        ),
        "_cocotb_driver": attr.label(
            default = "//tools:cocotb_driver",
            executable = True,
            cfg = "exec",
        ),
    },
    toolchains = ["@rules_python//python:toolchain_type"],
    test = True,
    doc = "Run CocoTB tests against a build",
)
def cocotb_build_test(**kwargs):
    """
    Legacy single-rule interface for CocoTB build and test.
    
    This rule combines build and test in a single target for convenience,
    while using the robust pipeline implementation internally.
    
    For scenarios requiring multiple tests against the same build,
    use the pipeline rules directly: cocotb_cfg, cocotb_build, cocotb_test.
    
    Args:
        **kwargs: All arguments supported by cocotb_test, plus build-related args:
            - hdl_toplevel: HDL toplevel module name (required)
            - hdl_toplevel_lang: HDL toplevel language (required for legacy compatibility)
            - sim_name: Simulator name (default: "verilator")
            - verilog_sources: Verilog source files
            - vhdl_sources: VHDL source files
            - test_module: Python test modules (required)
            - plus other standard cocotb arguments
    """
    
    # Extract required arguments
    name = kwargs.pop("name")
    hdl_toplevel = kwargs.pop("hdl_toplevel")
    test_module = kwargs.pop("test_module")
    
    # Extract optional arguments with defaults
    sim_name = kwargs.pop("sim_name", "verilator")
    verilog_sources = kwargs.pop("verilog_sources", [])
    vhdl_sources = kwargs.pop("vhdl_sources", [])
    
    # Create intermediate cfg target
    cfg_name = name + "_cfg"
    cocotb_cfg(
        name = cfg_name,
        simulator = sim_name,
    )
    
    # Create intermediate build target
    build_name = name + "_build"
    build_kwargs = {
        "name": build_name,
        "cfg": ":" + cfg_name,
        "hdl_toplevel": hdl_toplevel,
        "verilog_sources": verilog_sources,
        "vhdl_sources": vhdl_sources,
    }
    
    # Pass through build-related arguments
    for arg in ["includes", "defines", "parameters", "build_args", "waves", "verbose", "clean"]:
        if arg in kwargs:
            build_kwargs[arg] = kwargs.pop(arg)
    
    cocotb_build(**build_kwargs)
    
    # Create the test target
    test_kwargs = {
        "name": name,
        "build": ":" + build_name,
        "test_module": test_module,
    }
    
    # Pass through all remaining test arguments
    test_kwargs.update(kwargs)
    
    # Remove legacy-only arguments that aren't used in pipeline
    test_kwargs.pop("hdl_toplevel_lang", None)  # Not needed in pipeline approach
    test_kwargs.pop("hdl_library", None)        # Handled by build target
    
    cocotb_test(**test_kwargs)
