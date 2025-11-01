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
     "cocotb_test")

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
