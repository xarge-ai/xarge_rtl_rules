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
Working legacy cocotb_build_test rule using pipeline approach.

This implementation uses the robust pipeline rules (cocotb_build + cocotb_test)
internally to provide a single-rule interface that just works.

The old implementation had runfiles path issues. This new implementation
leverages the proven pipeline approach while maintaining the same API.
"""

load("//cocotb/private:pipeline.bzl", 
     "cocotb_cfg", 
     "cocotb_build", 
     "cocotb_test",
     "CocotbCfgInfo",
     "CocotbBuildInfo")

def _cocotb_build_test_impl(ctx):
    """
    Implementation that creates intermediate targets using pipeline rules.
    
    This creates a cfg target and build target internally, then returns
    the test target. This ensures we use the working pipeline approach
    while providing the legacy single-rule interface.
    """
    
    # Step 1: Create a simulator configuration
    cfg_name = ctx.label.name + "_cfg"
    cfg_target = cocotb_cfg(
        name = cfg_name,
        simulator = ctx.attr.sim_name,
    )
    
    # Step 2: Create the build target  
    build_name = ctx.label.name + "_build"
    build_target = cocotb_build(
        name = build_name,
        cfg = cfg_target,
        hdl_toplevel = ctx.attr.hdl_toplevel,
        verilog_sources = ctx.attr.verilog_sources,
        vhdl_sources = ctx.attr.vhdl_sources,
        includes = ctx.attr.includes,
        defines = ctx.attr.defines,
        parameters = ctx.attr.parameters,
        build_args = ctx.attr.build_args,
        waves = ctx.attr.waves,
        verbose = ctx.attr.verbose,
        clean = ctx.attr.clean,
    )
    
    # Step 3: Create and return the test target
    test_target = cocotb_test(
        name = ctx.label.name,
        build = build_target,
        test_module = ctx.attr.test_module,
        testcase = ctx.attr.testcase,
        deps = ctx.attr.deps,
        test_args = ctx.attr.test_args,
        elab_args = ctx.attr.elab_args,
        plus_args = ctx.attr.plus_args,
        extra_env = ctx.attr.extra_env,
        gpi_interfaces = ctx.attr.gpi_interfaces,
        waves = ctx.attr.waves,
        gui = getattr(ctx.attr, "gui", False),
        seed = ctx.attr.seed,
        verbose = ctx.attr.verbose,
    )
    
    return test_target

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

# For export compatibility, also provide the rule-based approach
# (though the macro approach above is preferred)
_cocotb_build_test_rule = rule(
    implementation = _cocotb_build_test_impl,
    attrs = {
        "hdl_toplevel": attr.string(mandatory = True),
        "hdl_toplevel_lang": attr.string(default = "verilog"),  # For compatibility
        "sim_name": attr.string(default = "verilator"),
        "test_module": attr.label_list(allow_files = [".py"], mandatory = True),
        "verilog_sources": attr.label_list(allow_files = [".v", ".sv"], default = []),
        "vhdl_sources": attr.label_list(allow_files = [".vhd", ".vhdl"], default = []),
        "deps": attr.label_list(providers = [PyInfo], default = []),
        "testcase": attr.string_list(default = []),
        "includes": attr.string_list(default = []),
        "defines": attr.string_dict(default = {}),
        "parameters": attr.string_dict(default = {}),
        "build_args": attr.string_list(default = []),
        "test_args": attr.string_list(default = []),
        "elab_args": attr.string_list(default = []),
        "plus_args": attr.string_list(default = []),
        "extra_env": attr.string_list(default = []),
        "gpi_interfaces": attr.string_list(default = []),
        "waves": attr.bool(default = False),
        "gui": attr.bool(default = False),
        "seed": attr.string(default = ""),
        "verbose": attr.bool(default = False),
        "clean": attr.bool(default = False),
    },
    test = True,
)
