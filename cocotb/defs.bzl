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
Industry-standard public API for CocoTB rules.

This module provides the main public interface following Bazel rules naming conventions.
Import from this module in your BUILD files.

Example:
    load("@rules_hdl//cocotb:defs.bzl", "cocotb_library", "cocotb_test")
    load("@rules_hdl//cocotb:defs.bzl", "hdl_sim_config", "hdl_sim_target", "hdl_testbench")
"""

# Re-export core pipeline rules with industry-standard names
load("//cocotb/private:pipeline.bzl", 
     _cocotb_cfg = "cocotb_cfg", 
     _cocotb_build = "cocotb_build", 
     _cocotb_test = "cocotb_test")

# Re-export legacy rule for backward compatibility  
load("//cocotb:cocotb_pipeline.bzl", 
     _cocotb_build_test = "cocotb_build_test")

# Re-export providers for advanced users
load("//cocotb/private:pipeline.bzl", 
     _CocotbCfgInfo = "CocotbCfgInfo", 
     _CocotbBuildInfo = "CocotbBuildInfo")

# === Primary Public API (Industry Standard Names) ===
# Following patterns from rules_python, rules_go, rules_cc

# Configuration rule - follows pattern like py_runtime, go_toolchain
cocotb_config = _cocotb_cfg

# Library rule - follows pattern like py_library, cc_library  
cocotb_library = _cocotb_build

# Test rule - follows pattern like py_test, cc_test
cocotb_test = _cocotb_test

# === Simulation Industry Aliases ===
# Common in EDA/simulation tools

# Simulator configuration
sim_config = _cocotb_cfg
cocotb_sim_config = _cocotb_cfg

# Simulation build/compilation
sim_build = _cocotb_build
cocotb_sim_build = _cocotb_build
cocotb_sim_compile = _cocotb_build

# Simulation test execution
sim_test = _cocotb_test
cocotb_sim_test = _cocotb_test
cocotb_sim_run = _cocotb_test

# === Hardware/RTL Industry Aliases ===
# Common in hardware verification

# HDL simulation configuration
hdl_config = _cocotb_cfg
hdl_sim_config = _cocotb_cfg
rtl_sim_config = _cocotb_cfg

# HDL simulation target/build
hdl_target = _cocotb_build
hdl_sim_target = _cocotb_build
rtl_sim_target = _cocotb_build
hdl_sim_build = _cocotb_build

# HDL testbench execution
hdl_test = _cocotb_test
hdl_testbench = _cocotb_test
rtl_testbench = _cocotb_test
verification_test = _cocotb_test

# === Build System Style Aliases ===
# Following CMake/Make conventions

cocotb_target = _cocotb_build      # CMake target style
cocotb_binary = _cocotb_build      # cc_binary style
cocotb_executable = _cocotb_build  # Common build system term

# === Backward Compatibility ===
# Original names for migration

cocotb_cfg = _cocotb_cfg
cocotb_build = _cocotb_build

# Legacy single-rule approach
cocotb_build_test = _cocotb_build_test

# === Providers ===
CocotbCfgInfo = _CocotbCfgInfo
CocotbBuildInfo = _CocotbBuildInfo

# === Common Simulator Configurations ===
# Pre-configured common setups

def verilator_config(name, **kwargs):
    """Verilator simulator configuration."""
    return cocotb_config(
        name = name,
        simulator = "verilator",
        **kwargs
    )

def icarus_config(name, **kwargs):
    """Icarus Verilog simulator configuration."""
    return cocotb_config(
        name = name,
        simulator = "icarus", 
        **kwargs
    )

def questa_config(name, **kwargs):
    """Questa/ModelSim simulator configuration."""
    return cocotb_config(
        name = name,
        simulator = "questa",
        **kwargs
    )

def vcs_config(name, **kwargs):
    """Synopsys VCS simulator configuration."""
    return cocotb_config(
        name = name,
        simulator = "vcs",
        **kwargs
    )

def ghdl_config(name, **kwargs):
    """GHDL simulator configuration."""
    return cocotb_config(
        name = name,
        simulator = "ghdl",
        **kwargs
    )