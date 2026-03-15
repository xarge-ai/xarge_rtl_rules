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

"""VerilogInfo provider for transitive Verilog/SystemVerilog dependency tracking."""

VerilogInfo = provider(
    "Verilog/SystemVerilog source information with transitive dependency tracking.",
    fields = {
        "srcs": "depset of direct source Files (.v, .sv, .svh, .vh)",
        "transitive_srcs": "depset of all transitive source Files",
        "includes": "depset of include directory strings",
        "defines": "depset of preprocessor define strings",
    },
)

def collect_verilog_srcs(deps):
    """Collect transitive source files from deps, supporting both VerilogInfo and plain labels.

    Args:
        deps: List of targets. If a target provides VerilogInfo, its transitive_srcs
              are collected. Otherwise, DefaultInfo files are used.

    Returns:
        A list of Files.
    """
    files = []
    for dep in deps:
        if VerilogInfo in dep:
            files.extend(dep[VerilogInfo].transitive_srcs.to_list())
        elif DefaultInfo in dep:
            files.extend(dep[DefaultInfo].files.to_list())
    return files
