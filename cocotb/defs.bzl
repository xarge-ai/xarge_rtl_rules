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

"""Public CocoTB API aliases for xarge_rtl_rules."""

load(
    "//cocotb:cocotb_pipeline.bzl",
    _CocotbBuildInfo = "CocotbBuildInfo",
    _CocotbCfgInfo = "CocotbCfgInfo",
    _cocotb_build = "cocotb_build",
    _cocotb_build_test = "cocotb_build_test",
    _cocotb_cfg = "cocotb_cfg",
    _cocotb_test = "cocotb_test",
)

CocotbCfgInfo = _CocotbCfgInfo
CocotbBuildInfo = _CocotbBuildInfo

cocotb_cfg = _cocotb_cfg
cocotb_build = _cocotb_build
cocotb_build_test = _cocotb_build_test
cocotb_test = _cocotb_test

cocotb_config = _cocotb_cfg
cocotb_library = _cocotb_build

sim_config = _cocotb_cfg
cocotb_sim_config = _cocotb_cfg

sim_build = _cocotb_build
cocotb_sim_build = _cocotb_build
cocotb_sim_compile = _cocotb_build

sim_test = _cocotb_test
cocotb_sim_test = _cocotb_test
cocotb_sim_run = _cocotb_test

hdl_config = _cocotb_cfg
hdl_sim_config = _cocotb_cfg
rtl_sim_config = _cocotb_cfg

hdl_target = _cocotb_build
hdl_sim_target = _cocotb_build
rtl_sim_target = _cocotb_build
hdl_sim_build = _cocotb_build

hdl_test = _cocotb_test
hdl_testbench = _cocotb_test
rtl_testbench = _cocotb_test
verification_test = _cocotb_test

cocotb_target = _cocotb_build
cocotb_binary = _cocotb_build
cocotb_executable = _cocotb_build

def verilator_config(name, **kwargs):
    """Create a configuration target for Verilator."""
    cocotb_config(
        name = name,
        simulator = "verilator",
        **kwargs
    )

def icarus_config(name, **kwargs):
    """Create a configuration target for Icarus Verilog."""
    cocotb_config(
        name = name,
        simulator = "icarus",
        **kwargs
    )

def questa_config(name, **kwargs):
    """Create a configuration target for Questa/ModelSim."""
    cocotb_config(
        name = name,
        simulator = "questa",
        **kwargs
    )

def vcs_config(name, **kwargs):
    """Create a configuration target for Synopsys VCS."""
    cocotb_config(
        name = name,
        simulator = "vcs",
        **kwargs
    )

def ghdl_config(name, **kwargs):
    """Create a configuration target for GHDL."""
    cocotb_config(
        name = name,
        simulator = "ghdl",
        **kwargs
    )
