# CocoTB Rules

`xarge_rtl_rules//cocotb` provides Bazel rules for building HDL once and running one or more cocotb tests against that build.

The canonical pipeline API is:

- `cocotb_cfg`
- `cocotb_build`
- `cocotb_test`
- `cocotb_build_test` for the one-shot compatibility macro

`defs.bzl` also keeps the older alias names such as `cocotb_config`, `cocotb_library`, `sim_build`, and `hdl_testbench`.

## Quick Start

```starlark
load(
    "@xarge_rtl_rules//cocotb:defs.bzl",
    "cocotb_build",
    "cocotb_cfg",
    "cocotb_test",
)
load("@xarge_py_deps//:requirements.bzl", "requirement")

cocotb_cfg(
    name = "verilator_cfg",
    simulator = "verilator",
)

cocotb_build(
    name = "rv_skid_buffer_build",
    cfg = ":verilator_cfg",
    hdl_toplevel = "rv_skid_buffer",
    verilog_sources = ["//rtl/utils:rv_skid_buffer_v"],
    waves = True,
)

cocotb_test(
    name = "rv_skid_buffer_test",
    build = ":rv_skid_buffer_build",
    test_module = ["test_rv_skid_buffer.py"],
    deps = [
        requirement("cocotb"),
        requirement("cocotbext-axi"),
    ],
)
```

## One-Shot Compatibility

If you prefer the older single-target flow, `cocotb_build_test` still expands into the same pipeline:

```starlark
load("@xarge_rtl_rules//cocotb:defs.bzl", "cocotb_build_test")

cocotb_build_test(
    name = "rv_skid_buffer_test",
    sim_name = "verilator",
    hdl_toplevel = "rv_skid_buffer",
    verilog_sources = ["//rtl/utils:rv_skid_buffer_v"],
    test_module = ["test_rv_skid_buffer.py"],
)
```

## Rule Summary

### `cocotb_cfg`

Selects the simulator to use. The `simulator` string is passed through to cocotb's runner API.

### `cocotb_build`

Compiles HDL sources into a reusable simulator build directory.

Common attrs:

- `cfg`
- `hdl_toplevel`
- `sources`, `verilog_sources`, `vhdl_sources`
- `includes`, `defines`, `parameters`
- `build_args`
- `hdl_library`
- `waves`, `verbose`, `clean`, `always`
- `timescale`, `log_file`

### `cocotb_test`

Runs cocotb Python modules against a `cocotb_build` target.

Common attrs:

- `build`
- `test_module`
- `deps`
- `testcase`
- `parameters`
- `plusargs`, `test_args`, `elab_args`
- `extra_env`
- `waves`, `gui`, `verbose`
- `seed`, `timescale`, `log_file`, `test_filter`

Building a `cocotb_test` target now also emits a `<target>.artifacts/` tree next
to the results XML in `bazel-bin`. Runtime outputs such as `dump.vcd` are copied
there so they remain available for post-run debug.

## Helper Macros

`defs.bzl` includes small simulator helpers:

- `verilator_config`
- `icarus_config`
- `questa_config`
- `vcs_config`
- `ghdl_config`

Each helper is just a convenience wrapper around `cocotb_cfg`.

## Notes

- `cocotb_build` and `cocotb_test` are intentionally split so multiple tests can share one compiled simulator build.
- `sources` accepts mixed HDL files and classifies them by extension. `.vlt` files are treated as Verilator control files.
- `deps` should include any Python packages imported by the cocotb tests beyond the runtime packages already supplied by this repo.

## Provenance

Earlier revisions of this package were explored against `hdl/bazel_rules_hdl`. The current Starlark backend, Python driver, wrapper, and docs were rewritten in March 2026 around the API used by `xarge_rtl_rules`. The repo-level provenance note in `THIRD_PARTY.md` keeps that history explicit.
