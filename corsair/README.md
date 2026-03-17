# Corsair Rules

Bazel rules for generating register RTL, headers, documentation, and other
artifacts with [Corsair](https://corsair.readthedocs.io/en/latest/).

## Rules

Load the rules from `@xarge_rtl_rules//corsair:defs.bzl`:

```starlark
load(
    "@xarge_rtl_rules//corsair:defs.bzl",
    "corsair_generate",
    "corsair_workflow",
)
```

- `corsair_generate`: simple rule that mirrors `corsair -r regs.yaml -c csrconfig`
- `corsair_workflow`: advanced rule for custom Python API-driven flows

## Simple Usage

`corsair_generate` is the default interface. Users only provide a register map,
a `csrconfig`, and the outputs they want to expose through Bazel.

```starlark
load("@xarge_rtl_rules//corsair:defs.bzl", "corsair_generate")
load("@xarge_rtl_rules//rtl:defs.bzl", "verilog_library")

corsair_generate(
    name = "uart_regs",
    regmap = "regs.yaml",
    csrconfig = "csrconfig",
    outs = [
        "uart_regs.sv",
        "uart_regs_pkg.sv",
        "uart_regs.svh",
        "uart_regs.md",
    ],
    out_dirs = ["uart_regs_img"],
)

verilog_library(
    name = "uart_regs_rtl",
    srcs = [
        ":uart_regs.sv",
        ":uart_regs_pkg.sv",
        ":uart_regs.svh",
    ],
    includes = ["."],
)
```

Example `csrconfig`:

```ini
[globcfg]
data_width = 32
address_width = 16
register_reset = sync_pos
address_alignment = data_width

[rtl]
generator = Verilog
path = hw/uart_regs.sv
interface = axil

[sv_pkg]
generator = SystemVerilogPackage
path = hw/uart_regs_pkg.sv
prefix = UART

[sv_header]
generator = VerilogHeader
path = hw/uart_regs.svh
prefix = UART

[docs]
generator = Markdown
path = doc/uart_regs.md
title = UART Register Map
image_dir = uart_regs_img
```

`outs` and `out_dirs` can be declared in two ways:

- Exact generated path, such as `hw/uart_regs.sv` or `doc/uart_regs_img`
- Unique basename, such as `uart_regs.sv` or `uart_regs_img`

Using basenames keeps the BUILD rule small while still letting `csrconfig`
organize files into subdirectories.

## Advanced Workflow Usage

Use `corsair_workflow` when the standard `csrconfig` flow is not enough and you
want to assemble your own generation pipeline in Python with Corsair APIs.

```starlark
load("@xarge_rtl_rules//corsair:defs.bzl", "corsair_workflow")

corsair_workflow(
    name = "uart_regs_custom",
    script = "uart_regs_gen.py",
    data = ["regs.yaml"],
    outs = [
        "uart_regs.sv",
        "uart_regs_pkg.sv",
    ],
    out_dirs = ["uart_regs_img"],
)
```

```python
import corsair


def generate(ctx):
    rmap = ctx.read_register_map("regs.yaml")

    corsair.generators.Verilog(
        rmap,
        path=str(ctx.output_path("uart_regs.sv")),
        interface="axil",
    ).generate()

    corsair.generators.SystemVerilogPackage(
        rmap,
        path=str(ctx.output_path("uart_regs_pkg.sv")),
        prefix="UART",
    ).generate()
```

The workflow script defaults to a `generate(ctx)` entrypoint. You can override
the function name with the rule's `function` attribute.

`ctx` provides:

- `ctx.args`: extra strings from the rule's `args` attribute
- `ctx.data_files`: all declared `data` files as `pathlib.Path` objects
- `ctx.input_path(name)`: resolve a declared data file by exact path, suffix, or basename
- `ctx.read_register_map(name)`: load and validate a register map file into `corsair.RegisterMap`
- `ctx.output_path(name)`: resolve a declared file output
- `ctx.output_dir(name)`: resolve a declared tree output directory
- `ctx.globcfg`: the current validated Corsair global configuration
- `ctx.set_globcfg(**kwargs)`: update and re-apply Corsair global configuration
- `ctx.tmpdir`: temporary scratch directory for intermediate files

## Notes

- Declare every generated file in `outs` and every generated directory in `out_dirs`.
- `corsair_generate` supports built-in Corsair generators with relative output paths.
- Use `corsair_workflow` for custom Python generators or more advanced flow control.
- The Bazel-managed dependency is pinned to `corsair==1.0.4`.
