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
]

_IGNORED_LEGACY_KEYS = [
    "cocotb_wrapper",
    "sim",
]

_WAVES_ON_CONDITION = str(Label("//cocotb/settings:waves_on"))
_WAVES_OFF_CONDITION = str(Label("//cocotb/settings:waves_off"))
_WAVE_FORMAT_VCD_CONDITION = str(Label("//cocotb/settings:wave_format_vcd"))
_WAVE_FORMAT_FST_CONDITION = str(Label("//cocotb/settings:wave_format_fst"))

CocotbCfgInfo = _CocotbCfgInfo
CocotbBuildInfo = _CocotbBuildInfo

cocotb_cfg = _cocotb_cfg

def _translate_legacy_kwargs(kwargs):
    """Normalize legacy compatibility kwargs in place."""
    if "plus_args" in kwargs and "plusargs" not in kwargs:
        kwargs["plusargs"] = kwargs.pop("plus_args")

    for key in _IGNORED_LEGACY_KEYS:
        kwargs.pop(key, None)

def _configured_waves(value):
    if value == None:
        fallback = False
    elif type(value) == "bool":
        fallback = value
    else:
        return value

    return select({
        _WAVES_ON_CONDITION: True,
        _WAVES_OFF_CONDITION: False,
        "//conditions:default": fallback,
    })

def _configured_wave_format(value):
    if value == None:
        fallback = ""
    elif type(value) == "string":
        fallback = value
    else:
        return value

    return select({
        _WAVE_FORMAT_FST_CONDITION: "fst",
        _WAVE_FORMAT_VCD_CONDITION: "vcd",
        "//conditions:default": fallback,
    })

def cocotb_build(
        name,
        cfg,
        hdl_toplevel,
        waves = None,
        wave_format = None,
        **kwargs):
    """Public wrapper over cocotb_build with optional CLI waveform overrides."""
    _translate_legacy_kwargs(kwargs)

    build_kwargs = dict(kwargs)
    build_kwargs.update({
        "name": name,
        "cfg": cfg,
        "hdl_toplevel": hdl_toplevel,
        "waves": _configured_waves(waves),
        "wave_format": _configured_wave_format(wave_format),
    })

    _cocotb_build(**build_kwargs)

def cocotb_test(
        name,
        build,
        test_module,
        waves = None,
        wave_output = None,
        wave_format = None,
        **kwargs):
    """Public wrapper over cocotb_test with optional CLI waveform overrides."""
    _translate_legacy_kwargs(kwargs)

    test_kwargs = dict(kwargs)
    test_kwargs.update({
        "name": name,
        "build": build,
        "test_module": test_module,
        "waves": _configured_waves(waves),
        "wave_format": _configured_wave_format(wave_format),
    })
    if wave_output != None:
        test_kwargs["wave_output"] = wave_output

    _cocotb_test(**test_kwargs)

def cocotb_build_test(
        name,
        hdl_toplevel,
        test_module,
        sim_name = "verilator",
        verilog_sources = [],
        vhdl_sources = [],
        sources = [],
        waves = None,
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

    build_kwargs["waves"] = _configured_waves(waves)
    build_kwargs["wave_format"] = _configured_wave_format(wave_format)

    cocotb_build(**build_kwargs)

    test_kwargs = {
        "name": name,
        "build": ":" + build_name,
        "test_module": test_module,
    }
    for key in _SHARED_BUILD_TEST_KEYS:
        if key in kwargs:
            test_kwargs[key] = kwargs[key]

    test_kwargs["waves"] = _configured_waves(waves)
    test_kwargs["wave_format"] = _configured_wave_format(wave_format)
    if wave_output != None:
        test_kwargs["wave_output"] = wave_output
    test_kwargs.update(kwargs)

    cocotb_test(**test_kwargs)
