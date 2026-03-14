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
Verilog packaging rules for IP distribution.

Provides rules to bundle RTL sources into ZIP archives and generate
filelists for non-Bazel consumption.

Usage:

    load("@generva_rtl_rules//packaging:defs.bzl", "verilog_zip_bundle", "verilog_filelist")

    verilog_zip_bundle(
        name = "sync_fifo_bundle",
        srcs = ["sync_fifo.sv"],
        deps = ["//rtl/utils/control:updown_counter_sv"],
    )

    verilog_filelist(
        name = "sync_fifo_filelist",
        srcs = ["sync_fifo.sv"],
        deps = ["//rtl/utils/control:updown_counter_sv"],
    )
"""

_BUNDLE = Label("//packaging/tools:bundle.py")

def _copy_tool_impl(ctx):
    """Copy a file using expand_template — avoids sandbox symlink issues."""
    out = ctx.actions.declare_file(ctx.attr.out_name)
    ctx.actions.expand_template(
        template = ctx.file.src,
        output = out,
        substitutions = {},
    )
    return [DefaultInfo(files = depset([out]))]

_copy_tool = rule(
    implementation = _copy_tool_impl,
    attrs = {
        "src": attr.label(allow_single_file = True, mandatory = True),
        "out_name": attr.string(mandatory = True),
    },
)

def _packaging_impl(
        name,
        srcs,
        deps,
        outs,
        args,
        tags,
        **kwargs):
    """Internal helper: copies bundle.py locally and runs it via genrule."""
    local_tool = name + "_bundle.py"

    _copy_tool(
        name = name + "_copy_tool",
        src = _BUNDLE,
        out_name = local_tool,
        tags = tags,
    )

    native.genrule(
        name = name,
        srcs = list(srcs) + list(deps),
        outs = outs,
        tools = [":" + name + "_copy_tool"],
        cmd = "python3 $(location :{}_copy_tool) {}".format(name, " ".join(args)),
        tags = tags,
        **kwargs
    )

def verilog_zip_bundle(
        name,
        srcs = [],
        deps = [],
        prefix = "",
        strip_prefix = "",
        flatten = False,
        tags = None,
        **kwargs):
    """Bundle RTL sources into a ZIP archive.

    Collects all listed sources and dependency files into a single .zip
    file suitable for IP distribution.

    Args:
        name: Target name. Output will be <name>.zip.
        srcs: Direct RTL source files (.sv/.v/.svh/.vh).
        deps: Dependency labels (filegroups or file targets) to include.
        prefix: Directory prefix inside the ZIP (e.g. "my_ip/rtl").
        strip_prefix: Strip this prefix from source paths in the ZIP.
        flatten: If True, place all files at top level in the ZIP.
        tags: Additional tags.
        **kwargs: Extra arguments forwarded to genrule.
    """
    all_tags = ["packaging"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    args = ["--output", "$(location {}.zip)".format(name), "--mode", "zip"]
    if prefix:
        args.extend(["--prefix", prefix])
    if strip_prefix:
        args.extend(["--strip-prefix", strip_prefix])
    if flatten:
        args.append("--flatten")

    for src in srcs:
        args.extend(["--src", "$(locations {})".format(src)])
    for dep in deps:
        args.extend(["--src", "$(locations {})".format(dep)])

    _packaging_impl(
        name = name,
        srcs = srcs,
        deps = deps,
        outs = [name + ".zip"],
        args = args,
        tags = all_tags,
        **kwargs
    )


def verilog_filelist(
        name,
        srcs = [],
        deps = [],
        relative_to = "",
        tags = None,
        **kwargs):
    """Generate a .f filelist for RTL sources.

    Creates a plain-text filelist (.f) with one source file per line,
    suitable for passing to simulators and synthesis tools via -f flag.

    Args:
        name: Target name. Output will be <name>.f.
        srcs: Direct RTL source files.
        deps: Dependency labels to include.
        relative_to: Make paths relative to this directory prefix.
        tags: Additional tags.
        **kwargs: Extra arguments forwarded to genrule.
    """
    all_tags = ["packaging"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    args = ["--output", "$(location {}.f)".format(name), "--mode", "filelist"]
    if relative_to:
        args.extend(["--relative-to", relative_to])

    for src in srcs:
        args.extend(["--src", "$(locations {})".format(src)])
    for dep in deps:
        args.extend(["--src", "$(locations {})".format(dep)])

    _packaging_impl(
        name = name,
        srcs = srcs,
        deps = deps,
        outs = [name + ".f"],
        args = args,
        tags = all_tags,
        **kwargs
    )
