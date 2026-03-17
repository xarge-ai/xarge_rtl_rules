# Xarge RTL Rules

Industry-standard Bazel rules for RTL design and verification workflows.

## Supported Rule Types

- **Corsair**: Register generation via simple `csrconfig` flows and Corsair Python APIs ✅
- **CocoTB**: Python-based HDL verification with multiple simulators ✅
- **UVM**: SystemVerilog UVM testbench rules (coming soon)
- **Synthesis**: FPGA and ASIC synthesis flows (coming soon)
- **Place & Route**: Physical design automation (coming soon)

## Quick Start

Add to your MODULE.bazel:
```starlark
bazel_dep(name = "xarge_rtl_rules", version = "1.0.0")

# For development
local_path_override(
    module_name = "xarge_rtl_rules", 
    path = "../xarge_rtl_rules",
)
```

Use in your BUILD files:
```starlark
load("@xarge_rtl_rules//corsair:defs.bzl", "corsair_generate")
load("@xarge_rtl_rules//cocotb:defs.bzl", "cocotb_test")
load("@xarge_rtl_rules//uvm:defs.bzl", "uvm_testbench")     # Future
load("@xarge_rtl_rules//synthesis:defs.bzl", "fpga_build")  # Future
```

## Documentation

- [Corsair Rules](corsair/README.md)
- [CocoTB Rules](cocotb/README.md)
- [Migration Guide](../common-ip/MIGRATION_GUIDE.md)

## Repository Structure

```
xarge_rtl_rules/
├── corsair/        # Corsair-based register generation rules
├── cocotb/         # CocoTB verification rules
├── uvm/            # UVM testbench rules (future) 
├── synthesis/      # Synthesis rules (future)
├── pnr/            # Place & Route rules (future)
└── third_party/    # Dependencies
```
