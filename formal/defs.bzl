# Copyright 2023 Antmicro
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
Industry-standard public API for SymbiYosys formal verification rules.

Usage in BUILD.bazel:

    load("@generva_rtl_rules//formal:defs.bzl", "sby_test")

    sby_test(
        name = "formal_async_fifo",
        sby = "async_fifo.sby",
        properties = "async_fifo_properties.sv",
        rtl_deps = ["//rtl/fifo:async_fifo_sv"],
    )
"""

_RUN_SBY = Label("//formal:run_sby.py")

def sby_test(name, sby, properties, rtl_deps, tags = None, **kwargs):
    """Declare a SymbiYosys formal verification test.

    Args:
        name: Test target name (e.g. "formal_async_fifo").
        sby: The .sby configuration file.
        properties: The SystemVerilog properties/bind file.
        rtl_deps: List of RTL filegroup targets needed by the .sby file.
        tags: Additional tags. "formal" is always included.
        **kwargs: Extra arguments forwarded to py_test (e.g. size, timeout).
    """
    all_tags = ["formal"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    native.py_test(
        name = name,
        srcs = [_RUN_SBY],
        main = _RUN_SBY,
        args = ["$(location {})".format(sby)],
        data = [sby, properties] + rtl_deps,
        tags = all_tags,
        **kwargs
    )
