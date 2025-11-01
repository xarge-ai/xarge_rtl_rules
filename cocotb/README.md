# CocoTB Rules - Industry Standard Repository

This repository provides industry-standard Bazel rules for CocoTB-based hardware verification. The rules follow Bazel community best practices and provide multiple naming conventions to accommodate different industry preferences.

**Note**: These rules are designed to be part of the `xarge_rtl_rules` repository, which provides a comprehensive set of RTL design and verification rules.

## Overview

These rules enable running CocoTB testbenches with Verilator and other simulators in a Bazel build environment. The implementation separates configuration, compilation, and testing phases for maximum flexibility.

## Features

- **Industry Standard API**: Primary `cocotb_*` naming following Bazel conventions
- **Multiple Aliases**: Simulation-focused (`sim_*`) and hardware-focused (`hdl_*`) alternatives
- **Flexible Configuration**: Separate config, build, and test phases
- **Pre-configured Helpers**: Common simulator configurations ready to use
- **Extensible Architecture**: Designed to accommodate UVM, synthesis, and other rules

## Quick Start

Add to your `MODULE.bazel`:

```starlark
# For Bzlmod (recommended)
bazel_dep(name = "xarge_rtl_rules", version = "1.0.0")

# For development (local)
local_path_override(
    module_name = "xarge_rtl_rules",
    path = "../xarge_rtl_rules",
)
```

## Usage Examples

### Primary API (Industry Standard)

```starlark
load("@xarge_rtl_rules//cocotb:defs.bzl", "cocotb_config", "cocotb_library", "cocotb_test")

# Configuration
cocotb_config(
    name = "verilator_cfg",
    simulator = "verilator",
)

# Build target
cocotb_library(
    name = "my_design_lib",
    cfg = ":verilator_cfg",
    hdl_toplevel = "my_design",
    verilog_sources = ["my_design.sv"],
)

# Test
cocotb_test(
    name = "my_design_test",
    build = ":my_design_lib",
    test_module = ["test_my_design.py"],
    testcase = ["test_basic"],
)

```

### Simulation-Focused Aliases

```starlark
load("@xarge_rtl_rules//cocotb:defs.bzl", "sim_config", "sim_build", "sim_test")

sim_config(name = "sim_cfg", simulator = "verilator")
sim_build(name = "my_sim", cfg = ":sim_cfg", ...)
sim_test(name = "my_test", build = ":my_sim", ...)
```

### Hardware/RTL Aliases

```starlark
load("@xarge_rtl_rules//cocotb:defs.bzl", "hdl_sim_config", "hdl_sim_target", "hdl_testbench")

hdl_sim_config(name = "hdl_cfg", simulator = "verilator")
hdl_sim_target(name = "my_hdl", cfg = ":hdl_cfg", ...)
hdl_testbench(name = "my_tb", build = ":my_hdl", ...)
```

## Rule Reference

### cocotb_config / sim_config / hdl_sim_config

Configures simulator settings for CocoTB tests.

**Attributes:**
- `simulator` (string): Simulator to use ("verilator", "iverilog", etc.)
- `compile_args` (list): Additional compilation arguments
- `sim_args` (list): Additional simulation arguments

### cocotb_library / sim_build / hdl_sim_target

Compiles HDL sources for simulation.

**Attributes:**
- `cfg` (label): Configuration target
- `hdl_toplevel` (string): Top-level module name
- `verilog_sources` (list): Verilog source files
- `parameters` (dict): Module parameters
- `extra_env` (dict): Environment variables

### cocotb_test / sim_test / hdl_testbench

Runs CocoTB testbenches.

**Attributes:**
- `build` (label): Build target to test
- `test_module` (list): Python test modules
- `testcase` (list, optional): Specific test cases
- `deps` (list): Python dependencies
- `parameters` (dict): Additional parameters

## Pre-configured Helpers

### verilator_config

Pre-configured for Verilator with common settings:

```starlark
load("@xarge_rtl_rules//cocotb:defs.bzl", "verilator_config")

verilator_config(name = "quick_verilator")
```

## Advanced Usage

### Parameterized Tests

```starlark
[cocotb_test(
    name = "test_width_{}".format(width),
    build = ":my_design_lib",
    parameters = {"WIDTH": str(width)},
    test_module = ["test_parameterized.py"],
) for width in [8, 16, 32]]
```

### Multiple Simulators

```starlark
SIMULATORS = ["verilator", "iverilog"]

[cocotb_config(
    name = "{}_cfg".format(sim),
    simulator = sim,
) for sim in SIMULATORS]

[cocotb_test(
    name = "test_{}".format(sim), 
    build = ":my_design_lib",
    test_module = ["test_cross_sim.py"],
) for sim in SIMULATORS]
```

## Directory Structure

```
rules/cocotb/
├── defs.bzl           # Public API with all aliases
├── BUILD.bazel        # Package definition
├── private/           # Implementation details
│   ├── pipeline.bzl   # Core rule implementations  
│   └── BUILD.bazel    # Private package
├── tools/             # Executable tools
│   ├── cocotb_driver.py
│   ├── cocotb_wrapper.py
│   └── BUILD.bazel
└── examples/          # Usage examples
    ├── BUILD.bazel
    └── test_*.py
```

## Legacy Compatibility

The original API remains available for backward compatibility:

```starlark
# Single-step legacy approach
load("@xarge_rtl_rules//cocotb:defs.bzl", "cocotb_build_test")

cocotb_build_test(
    name = "legacy_test",
    hdl_toplevel = "my_module",
    test_module = ["test_my_module.py"],
    verilog_sources = ["my_module.sv"],
    sim_name = "verilator",
)
```

## Part of xarge_rtl_rules Ecosystem

This CocoTB package is part of the larger `xarge_rtl_rules` repository which provides:

- **CocoTB Rules**: Python-based verification (this package)
- **UVM Rules**: SystemVerilog UVM testbenches (coming soon)
- **Synthesis Rules**: FPGA/ASIC synthesis flows (coming soon)  
- **Place & Route Rules**: Physical design automation (coming soon)

## Extending the Rules

This repository is designed to accommodate additional rule types:

- **UVM Rules**: For SystemVerilog/UVM testbenches
- **Synthesis Rules**: For FPGA/ASIC synthesis flows  
- **Formal Rules**: For formal verification
- **Coverage Rules**: For functional coverage collection

## Contributing

1. Follow Bazel rule development best practices
2. Maintain backward compatibility in public APIs
3. Add tests for new features
4. Update documentation for API changes

## License

[Your License Here]

## Support

For questions and issues:
- GitHub Issues: [Repository Issues URL]
- Documentation: [Documentation URL]
- Examples: See `examples/` directory

**Key Attributes:**
- `cfg` (label): CocoTB configuration target (from `cocotb_cfg`)
- `hdl_toplevel` (string): HDL toplevel module name
- `sources` (label_list): Language-agnostic source files
- `verilog_sources` (label_list): Verilog source files (.v, .sv)  
- `vhdl_sources` (label_list): VHDL source files (.vhd, .vhdl)
- `includes` (string_list): Include directories
- `defines` (string_dict): Preprocessor defines
- `parameters` (string_dict): Verilog parameters or VHDL generics
- `hdl_library` (string): HDL library name (default: "top")
- `waves` (bool): Enable waveform recording
- `build_args` (string_list): Extra simulator build arguments
- `verbose` (bool): Enable verbose output
- `clean` (bool): Clean build directory before building
- `timescale` (string_list): Time unit and precision, e.g. `["1ns", "1ps"]`

### `cocotb_test`

Runs CocoTB tests against a build target.

**Key Attributes:**
- `build` (label): CocoTB build target (from `cocotb_build`)
- `test_module` (label_list): Python test modules (.py files)
- `deps` (label_list): Python dependencies  
- `testcase` (string_list): Specific testcases to run (empty = all)
- `hdl_toplevel` (string): Override HDL toplevel from build
- `hdl_toplevel_lang` (string): HDL language - "verilog" (default) or "vhdl"
- `parameters` (string_dict): Runtime parameters (override build params)
- `seed` (string): Random seed for reproducible tests
- `waves` (bool): Enable waveform recording for this test
- `gui` (bool): Launch simulator GUI (if supported)
- `verbose` (bool): Enable verbose output
- `extra_env` (string_dict): Extra environment variables
- `plusargs` (string_list): Simulator plusargs
- `test_args` (string_list): Extra test arguments
- `elab_args` (string_list): Elaboration arguments
- `pre_cmd` (string_list): Commands to run before simulation
- `test_filter` (string): Regex to filter test names

## Source File Tagging

The pipeline supports tagged source files for explicit language specification:

```starlark
cocotb_build(
    name = "mixed_build",
    cfg = ":cfg",
    sources = [
        "VERILOG:design.sv",
        "VHDL:testbench.vhd", 
        "VERILATORCTL:sim.vlt",  # Verilator control file
        "untagged_file.v",       # Assumed Verilog
    ],
    hdl_toplevel = "top",
)
```

**Supported Tags:**
- `VERILOG:path` - Verilog source file
- `VHDL:path` - VHDL source file  
- `VERILATORCTL:path` - Verilator control file (.vlt)
- Untagged files assumed to be Verilog

## Simulator Support

### Verilator (Default)

```starlark
cocotb_cfg(
    name = "verilator_cfg",
    simulator = "verilator",
)
```

**Waveforms:** Must be enabled at build time (`waves = True` in `cocotb_build`). Individual tests can then request GUI or save traces.

**Control Files:** Use `VERILATORCTL:` tags to include `.vlt` files:
```starlark
sources = ["VERILATORCTL:configs/timing.vlt"]
```

### Other Simulators

```starlark
# Icarus Verilog
cocotb_cfg(name = "icarus_cfg", simulator = "icarus")

# Questa/ModelSim  
cocotb_cfg(name = "questa_cfg", simulator = "questa")

# Synopsys VCS
cocotb_cfg(name = "vcs_cfg", simulator = "vcs")

# GHDL (VHDL)
cocotb_cfg(name = "ghdl_cfg", simulator = "ghdl")
```

All simulators must be available in `PATH` during execution.

## Migration from Legacy Rules

### Before (Single Rule)
```starlark
load("//rules/cocotb:cocotb_tools.bzl", "cocotb_build_test")

cocotb_build_test(
    name = "my_test",
    hdl_toplevel = "dut",
    hdl_toplevel_lang = "verilog",
    test_module = ["test_dut.py"],
    verilog_sources = ["//rtl:dut_srcs"],
    sim_name = "verilator",
    waves = True,
    defines = {"WIDTH": "32"},
)
```

### After (Pipeline)
```starlark
load("//rules/cocotb:cocotb_pipeline.bzl", "cocotb_cfg", "cocotb_build", "cocotb_test")

cocotb_cfg(
    name = "cfg",
    simulator = "verilator",  # was sim_name
)

cocotb_build(
    name = "dut_build",
    cfg = ":cfg",
    hdl_toplevel = "dut",
    verilog_sources = ["//rtl:dut_srcs"],  # same
    waves = True,       # same
    defines = {"WIDTH": "32"},  # same  
)

cocotb_test(
    name = "my_test", 
    build = ":dut_build",
    test_module = ["test_dut.py"],  # same
    hdl_toplevel_lang = "verilog",  # same
)
```

## Usage Examples

### Running Tests

```bash
# Single test
bazel test //dv/cocotb/rv_skid_buffer:rv_skid_buffer_basic_test

# Multiple tests (same build, cached)
bazel test //dv/cocotb/rv_skid_buffer:rv_*

# With verbose output
bazel test //dv/cocotb/rv_skid_buffer:rv_skid_buffer_basic_test --test_output=all

# With test filter
bazel test //dv/cocotb/rv_skid_buffer:rv_* --test_output=errors
```

### Build Caching Benefits

```bash
# First test - triggers build + test
bazel test //dv/cocotb/rv_skid_buffer:rv_skid_buffer_basic_test

# Second test - reuses build (cache hit), only runs test
bazel test //dv/cocotb/rv_skid_buffer:rv_skid_buffer_random_test

# Clean build directory but keep Bazel cache
bazel clean
bazel test //dv/cocotb/rv_skid_buffer:rv_skid_buffer_basic_test  # Still cached!
```

## Troubleshooting

### Common Issues

**"Simulator not found"**
- Ensure simulator (verilator, icarus, etc.) is in PATH
- Check simulator installation: `which verilator`

**"No module named 'cocotb'"** 
- Install CocoTB: `pip install cocotb` or `pip install cocotb-tools`
- Check requirements.txt in third_party/python/

**"results.xml not found"**
- Check test actually ran (look for test output)
- Verify test module imports and test functions are decorated with `@cocotb.test()`

**"Missing include files"**
- Add include directories to `includes` attribute
- Use absolute paths from workspace root
- Check include paths in .vlt files for Verilator

**Build cache misses**
- Ensure `cocotb_build` target doesn't change between tests
- Check that input files aren't changing (timestamps, content)
- Use `bazel query --output=build //path:target` to debug dependencies

**Verilator waveforms not working**
- Enable `waves = True` in `cocotb_build` (not just `cocotb_test`)
- Verilator needs waveform support compiled in at build time
- Check for `.vcd` files in build directory

### Debug Commands

```bash
# Show build dependencies
bazel query --output=build //dv/cocotb/rv_skid_buffer:rv_skid_buffer_build

# Show test dependencies  
bazel query --output=build //dv/cocotb/rv_skid_buffer:rv_skid_buffer_basic_test

# Force rebuild
bazel clean && bazel build //dv/cocotb/rv_skid_buffer:rv_skid_buffer_build

# Show generated command
bazel run //dv/cocotb/rv_skid_buffer:rv_skid_buffer_basic_test --verbose_failures
```

### Environment Variables

Set these for debugging:

```bash
export COCOTB_LOG_LEVEL=DEBUG    # CocoTB debug output
export BAZEL_VERBOSE=1           # Bazel debug output  
```

## Advanced Configuration

### Custom Test Driver

The pipeline uses `//tools:cocotb_driver` internally. For advanced customization, you can:

1. Copy and modify `tools/cocotb_driver.py`
2. Create a new `py_binary` target
3. Override `_cocotb_driver` attribute in rules

### Multiple Simulator Configs

```starlark
# Test same design with different simulators
cocotb_cfg(name = "verilator_cfg", simulator = "verilator")
cocotb_cfg(name = "icarus_cfg", simulator = "icarus")

cocotb_build(name = "dut_verilator", cfg = ":verilator_cfg", ...)
cocotb_build(name = "dut_icarus", cfg = ":icarus_cfg", ...)

cocotb_test(name = "test_verilator", build = ":dut_verilator", ...)
cocotb_test(name = "test_icarus", build = ":dut_icarus", ...)
```

### Parameterized Tests

```starlark
# Test different widths
[cocotb_test(
    name = "test_width_{}".format(w),
    build = ":dut_build", 
    test_module = ["test_dut.py"],
    parameters = {"WIDTH": str(w)},
) for w in [8, 16, 32, 64]]
```

## Dependencies

- **CocoTB >= 2.0** (preferred) or **cocotb-tools** (fallback)
- **Python 3.7+**
- **Simulator** (verilator, icarus, questa, etc.) in PATH
- **Bazel rules_python**

## License

Copyright 2023 Antmicro. Licensed under Apache 2.0.