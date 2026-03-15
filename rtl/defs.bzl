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
Verilog/SystemVerilog RTL library rule with transitive dependency tracking.

Provides the verilog_library rule which creates VerilogInfo-providing targets
that track transitive sources, includes, and defines through the dependency graph.

Usage:

    load("@generva_rtl_rules//rtl:defs.bzl", "verilog_library")

    verilog_library(
        name = "sync_fifo",
        srcs = ["sync_fifo.sv"],
    )

    verilog_library(
        name = "async_fifo",
        srcs = ["async_fifo.sv"],
        deps = [":sync_fifo", "//rtl/cdc:cdc_pkg"],
    )
"""

load("//rtl:providers.bzl", "VerilogInfo")

def _verilog_library_impl(ctx):
    direct = depset(ctx.files.srcs)
    transitive = depset(
        ctx.files.srcs,
        transitive = [dep[VerilogInfo].transitive_srcs for dep in ctx.attr.deps if VerilogInfo in dep],
    )
    includes = depset(
        ctx.attr.includes,
        transitive = [dep[VerilogInfo].includes for dep in ctx.attr.deps if VerilogInfo in dep],
    )
    defines = depset(
        ctx.attr.defines,
        transitive = [dep[VerilogInfo].defines for dep in ctx.attr.deps if VerilogInfo in dep],
    )
    return [
        DefaultInfo(files = direct),
        VerilogInfo(
            srcs = direct,
            transitive_srcs = transitive,
            includes = includes,
            defines = defines,
        ),
    ]

verilog_library = rule(
    implementation = _verilog_library_impl,
    attrs = {
        "srcs": attr.label_list(
            doc = "Verilog/SystemVerilog source files (.v, .sv, .svh, .vh)",
            allow_files = [".v", ".sv", ".svh", ".vh"],
            default = [],
        ),
        "deps": attr.label_list(
            doc = "Other verilog_library targets this depends on",
            providers = [VerilogInfo],
            default = [],
        ),
        "includes": attr.string_list(
            doc = "Include directories for -I flags",
            default = [],
        ),
        "defines": attr.string_list(
            doc = "Preprocessor defines (e.g. ['SYNTHESIS', 'DATA_WIDTH=32'])",
            default = [],
        ),
    },
    doc = "Declare a Verilog/SystemVerilog library with transitive dependency tracking.",
)
