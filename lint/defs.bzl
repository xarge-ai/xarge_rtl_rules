# Copyright 2024 Xarge AI
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
RTL Lint rules for Verilator, Verible, and commercial tools.

Provides declarative lint test targets that run lint checks as Bazel tests.

Usage:

    load("@generva_rtl_rules//lint:defs.bzl", "verilator_lint_test", "verible_lint_test")

    verilator_lint_test(
        name = "lint_sync_fifo",
        srcs = ["sync_fifo.sv"],
        top = "sync_fifo",
    )

    verible_lint_test(
        name = "style_sync_fifo",
        srcs = ["sync_fifo.sv"],
    )

    # Commercial tool (VCStatic / SpyGlass / Ascent):
    load("@generva_rtl_rules//lint:defs.bzl", "lint_test")

    lint_test(
        name = "lint_sync_fifo_spyglass",
        srcs = ["sync_fifo.sv"],
        top = "sync_fifo",
        tool = "spyglass",
    )
"""

_RUN_LINT = Label("//lint/runner:run_lint.py")

def _copy_file_impl(ctx):
    """Starlark rule that copies a file — works reliably across repo boundaries."""
    out = ctx.actions.declare_file(ctx.attr.out_name)
    # Use expand_template with no substitutions to copy the file content.
    # This avoids sandbox issues with cross-repo symlinks (local_path_override).
    ctx.actions.expand_template(
        template = ctx.file.src,
        output = out,
        substitutions = {},
    )
    return [DefaultInfo(files = depset([out]))]

_copy_file = rule(
    implementation = _copy_file_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
        "out_name": attr.string(mandatory = True),
    },
)

def _lint_test_impl(
        name,
        args,
        data,
        tags,
        **kwargs):
    """Internal helper: copies runner into local package and creates py_test."""
    local_runner = name + "_run_lint.py"

    copy_target = name + "_copy_runner"

    # Use Starlark rule to copy the runner — handles cross-repo symlinks
    # properly in sandboxed builds (unlike genrule + cp).
    _copy_file(
        name = copy_target,
        src = _RUN_LINT,
        out_name = local_runner,
        tags = tags,
    )

    native.py_test(
        name = name,
        srcs = [":" + copy_target],
        main = local_runner,
        precompile = "disabled",
        args = args,
        data = data,
        tags = tags,
        **kwargs
    )


def verilator_lint_test(
        name,
        srcs,
        top = None,
        deps = [],
        defines = [],
        flags = [],
        waiver_file = None,
        tags = None,
        **kwargs):
    """Run Verilator --lint-only on RTL sources.

    Args:
        name: Test target name.
        srcs: RTL source files (.sv/.v).
        top: Top module name (default: inferred from first src filename).
        deps: Additional RTL dependency labels.
        defines: Preprocessor defines (e.g. ["VERILATOR", "SYNTHESIS"]).
        flags: Extra verilator flags (e.g. ["-Wall", "-Wno-WIDTHTRUNC"]).
        waiver_file: Optional Verilator waiver file (.vlt).
        tags: Additional tags. "lint" is always included.
        **kwargs: Extra arguments forwarded to sh_test.
    """
    all_tags = ["lint", "verilator-lint"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    args = ["--tool", "verilator"]
    if top:
        args.extend(["--top", top])
    for d in defines:
        args.extend(["--define", d])
    for f in flags:
        args.extend(["--flag", f])
    if waiver_file:
        args.extend(["--waiver", "$(location {})".format(waiver_file)])

    data = list(srcs) + list(deps)
    if waiver_file:
        data.append(waiver_file)

    for src in srcs:
        args.extend(["--src", "$(locations {})".format(src)])
    for dep in deps:
        args.extend(["--src", "$(locations {})".format(dep)])

    _lint_test_impl(
        name = name,
        args = args,
        data = data,
        tags = all_tags,
        **kwargs
    )


def verible_lint_test(
        name,
        srcs,
        deps = [],
        rules_config = None,
        waiver_file = None,
        rules = [],
        rules_off = [],
        tags = None,
        **kwargs):
    """Run verible-verilog-lint on RTL sources.

    Args:
        name: Test target name.
        srcs: RTL source files (.sv/.v).
        deps: Additional RTL dependency labels.
        rules_config: Path to .rules.verible_lint config file.
        waiver_file: Path to waiver config file.
        rules: Explicit rules to enable (e.g. ["module-filename"]).
        rules_off: Rules to disable (e.g. ["parameter-name-style"]).
        tags: Additional tags. "lint" is always included.
        **kwargs: Extra arguments forwarded to sh_test.
    """
    all_tags = ["lint", "verible-lint"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    args = ["--tool", "verible"]
    if rules_config:
        args.extend(["--rules-config", "$(location {})".format(rules_config)])
    if waiver_file:
        args.extend(["--waiver", "$(location {})".format(waiver_file)])
    for r in rules:
        args.extend(["--rule-on", r])
    for r in rules_off:
        args.extend(["--rule-off", r])

    data = list(srcs) + list(deps)
    if rules_config:
        data.append(rules_config)
    if waiver_file:
        data.append(waiver_file)

    for src in srcs:
        args.extend(["--src", "$(locations {})".format(src)])
    for dep in deps:
        args.extend(["--src", "$(locations {})".format(dep)])

    _lint_test_impl(
        name = name,
        args = args,
        data = data,
        tags = all_tags,
        **kwargs
    )


def lint_test(
        name,
        srcs,
        top = None,
        tool = "verilator",
        deps = [],
        defines = [],
        flags = [],
        waiver_file = None,
        rules_config = None,
        rules = [],
        rules_off = [],
        tags = None,
        **kwargs):
    """Generic RTL lint test supporting multiple tools.

    Args:
        name: Test target name.
        srcs: RTL source files (.sv/.v).
        top: Top module name (used by verilator and commercial tools).
        tool: Lint tool to use. One of: "verilator", "verible",
              "spyglass", "vcstatic", "ascent".
        deps: Additional RTL dependency labels.
        defines: Preprocessor defines.
        flags: Extra tool-specific flags.
        waiver_file: Tool-specific waiver file.
        rules_config: Rules configuration file (verible/commercial).
        rules: Rules to enable (verible).
        rules_off: Rules to disable (verible).
        tags: Additional tags. "lint" is always included.
        **kwargs: Extra arguments forwarded to sh_test.
    """
    if tool == "verilator":
        verilator_lint_test(
            name = name,
            srcs = srcs,
            top = top,
            deps = deps,
            defines = defines,
            flags = flags,
            waiver_file = waiver_file,
            tags = tags,
            **kwargs
        )
    elif tool == "verible":
        verible_lint_test(
            name = name,
            srcs = srcs,
            deps = deps,
            rules_config = rules_config,
            waiver_file = waiver_file,
            rules = rules,
            rules_off = rules_off,
            tags = tags,
            **kwargs
        )
    else:
        # Commercial tools: spyglass, vcstatic, ascent
        all_tags = ["lint", tool + "-lint"]
        if tags:
            all_tags = all_tags + [t for t in tags if t not in all_tags]

        args = ["--tool", tool]
        if top:
            args.extend(["--top", top])
        for d in defines:
            args.extend(["--define", d])
        for f in flags:
            args.extend(["--flag", f])
        if waiver_file:
            args.extend(["--waiver", "$(location {})".format(waiver_file)])
        if rules_config:
            args.extend(["--rules-config", "$(location {})".format(rules_config)])

        data = list(srcs) + list(deps)
        if waiver_file:
            data.append(waiver_file)
        if rules_config:
            data.append(rules_config)

        for src in srcs:
            args.extend(["--src", "$(locations {})".format(src)])
        for dep in deps:
            args.extend(["--src", "$(locations {})".format(dep)])

        _lint_test_impl(
            name = name,
            args = args,
            data = data,
            tags = all_tags,
            **kwargs
        )
