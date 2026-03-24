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

"""Compatibility facade for the public CocoTB pipeline API."""

load(
    "//cocotb/private:pipeline.bzl",
    _CocotbBuildInfo = "CocotbBuildInfo",
    _CocotbCfgInfo = "CocotbCfgInfo",
    _cocotb_build = "cocotb_build",
    _cocotb_cfg = "cocotb_cfg",
    _cocotb_test = "cocotb_test",
)

_BUILD_ONLY_KEYS = [
    "always",
    "build_args",
    "clean",
    "defines",
    "hdl_library",
    "includes",
    "sources",
    "verilog_sources",
    "vhdl_sources",
]

_SHARED_BUILD_TEST_KEYS = [
    "log_file",
    "parameters",
    "timescale",
    "verbose",
    "waves",
    "wave_format",
]

_IGNORED_LEGACY_KEYS = [
    "cocotb_wrapper",
    "sim",
]

CocotbCfgInfo = _CocotbCfgInfo
CocotbBuildInfo = _CocotbBuildInfo

cocotb_cfg = _cocotb_cfg
cocotb_build = _cocotb_build
cocotb_test = _cocotb_test

def _translate_legacy_kwargs(kwargs):
    """Normalize legacy compatibility kwargs in place."""
    if "plus_args" in kwargs and "plusargs" not in kwargs:
        kwargs["plusargs"] = kwargs.pop("plus_args")

    for key in _IGNORED_LEGACY_KEYS:
        kwargs.pop(key, None)

def cocotb_build_test(
        name,
        hdl_toplevel,
        test_module,
        sim_name = "verilator",
        verilog_sources = [],
        vhdl_sources = [],
        sources = [],
        wave_output = None,
        wave_format = None,
        **kwargs):
    """Backward-compatible single target wrapper over the pipeline backend."""
    _translate_legacy_kwargs(kwargs)

    cfg_name = name + "_cfg"
    cocotb_cfg(
        name = cfg_name,
        simulator = sim_name,
    )

    build_name = name + "_build"
    build_kwargs = {
        "name": build_name,
        "cfg": ":" + cfg_name,
        "hdl_toplevel": hdl_toplevel,
        "verilog_sources": verilog_sources,
        "vhdl_sources": vhdl_sources,
        "sources": sources,
    }

    for key in _BUILD_ONLY_KEYS:
        if key in kwargs:
            build_kwargs[key] = kwargs.pop(key)

    for key in _SHARED_BUILD_TEST_KEYS:
        if key in kwargs:
            build_kwargs[key] = kwargs[key]

    if wave_format != None:
        build_kwargs["wave_format"] = wave_format

    cocotb_build(**build_kwargs)

    test_kwargs = {
        "name": name,
        "build": ":" + build_name,
        "test_module": test_module,
    }
    if wave_output != None:
        test_kwargs["wave_output"] = wave_output
    if wave_format != None:
        test_kwargs["wave_format"] = wave_format
    test_kwargs.update(kwargs)

    cocotb_test(**test_kwargs)
