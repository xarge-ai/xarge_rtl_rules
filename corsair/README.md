# Corsair Rules

Bazel rules for generating register RTL, headers, documentation, and other
artifacts with [Corsair](https://corsair.readthedocs.io/en/latest/).

## Rules

Load the rules from `@xarge_rtl_rules//corsair:defs.bzl`:

```starlark
load(
    "@xarge_rtl_rules//corsair:defs.bzl",
    "corsair_generate",
    "corsair_publish",
    "corsair_workflow",
)
```

- `corsair_generate`: Bazel-native register generation with built-in output selection
- `corsair_publish`: runnable helper that copies generated artifacts into repo-local check-in paths
- `corsair_workflow`: advanced rule for custom Python API-driven flows

## Simple Usage

`corsair_generate` is the default interface. Users describe which standard
artifacts they want, optionally override output paths, and Bazel declares the
resulting files directly.

```starlark
load("@xarge_rtl_rules//corsair:defs.bzl", "corsair_generate")
load("@xarge_rtl_rules//rtl:defs.bzl", "verilog_library")

corsair_generate(
    name = "uart_regs",
    regmap = "regs.yaml",
    rtl = True,
    sv_pkg = True,
    c_header = True,
    python_module = True,
    markdown = True,
    rtl_out = "hw/uart_regs.sv",
    sv_pkg_out = "hw/uart_regs_pkg.sv",
    c_header_out = "sw/uart_regs.h",
    python_out = "sw/uart_regs.py",
    markdown_out = "doc/uart_regs.md",
    publish = True,
    publish_root = "registers",
)

verilog_library(
    name = "uart_regs_rtl",
    srcs = [
        ":hw/uart_regs.sv",
        ":hw/uart_regs_pkg.sv",
    ],
    includes = ["hw"],
)
```

`publish_root = "registers"` is relative to the current Bazel package.

If you want a workspace-root destination instead, use `//registers/uart` or
`@project_name/registers/uart`.

`bazel build //path/to:uart_regs` keeps outputs in Bazel's output tree.

`bazel run //path/to:uart_regs_publish` copies the generated files into
`registers/hw`, `registers/sw`, and `registers/doc` under the package for
check-in.

If you prefer to wire publishing explicitly instead of using `publish = True`,
use `corsair_publish` directly:

```starlark
load(
    "@xarge_rtl_rules//corsair:defs.bzl",
    "corsair_generate",
    "corsair_publish",
)

corsair_generate(
    name = "uart_regs",
    regmap = "regs.yaml",
    markdown = True,
)

corsair_publish(
    name = "uart_regs_checkin",
    src = ":uart_regs",
    publish_root = "registers",
)
```

When published, bare output names are categorized automatically:

- RTL, SV packages, and Verilog headers go to `hw/`
- C headers and Python modules go to `sw/`
- Markdown, Asciidoc, image directories, and dump files go to `doc/`

If an output path already contains a subdirectory such as `hw/uart_regs.sv` or
`doc/uart_regs.md`, that relative path is preserved under `publish_root`.

`publish_root` forms:

- `registers`: relative to the current Bazel package
- `//registers/uart`: relative to the workspace root
- `@project_name/registers/uart`: also relative to the workspace root

## Optional csrconfig Override

`corsair_generate` can also merge a native `csrconfig` when you want to keep
using existing Corsair config files while still exposing Bazel-native outputs.

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

`csrconfig` support in `corsair_generate` is intentionally limited to naming
and built-in generator selection. For arbitrary native layouts, use
`corsair_generate_raw`.

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

- `corsair_generate` supports built-in Corsair generators with relative output paths.
- `corsair_publish` is intended for `bazel run` check-in flows, not normal `bazel build`s.
- Use `corsair_workflow` for custom Python generators or more advanced flow control.
- The Bazel-managed dependency is pinned to `corsair==1.0.4`.
