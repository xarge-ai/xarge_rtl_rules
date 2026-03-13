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
Declarative SymbiYosys formal verification rule.

Generates .sby configuration at test time from BUILD.bazel parameters,
eliminating the need for hand-written .sby files.

Usage:

    load("@generva_rtl_rules//formal:defs.bzl", "sby_test")

    sby_test(
        name = "formal_sync_fifo",
        properties = "sync_fifo_properties.sv",
        rtl_deps = ["//rtl/fifo:sync_fifo_sv"],
        bmc_depth = 40,
        prove = True,
    )
"""

_RUN_SBY = Label("//formal:run_sby.py")

def sby_test(
        name,
        properties,
        rtl_deps,
        bmc_depth = 20,
        prove = False,
        multiclock = False,
        bmc_engine = None,
        prove_engine = None,
        prove_depth = None,
        defines = [],
        flatten = True,
        top = None,
        tags = None,
        **kwargs):
    """Declare a SymbiYosys formal verification test.

    Args:
        name: Test target name.
        properties: SVA properties/bind file (.sv).
        rtl_deps: RTL source file labels.
        bmc_depth: Bounded model check depth (default: 20).
        prove: Enable unbounded prove task (default: False).
        multiclock: Enable multiclock for CDC designs (default: False).
        bmc_engine: BMC engine (default: "smtbmc").
        prove_engine: Prove engine (default: "abc pdr"; "smtbmc" if multiclock).
        prove_depth: K-induction depth for smtbmc prove (default: bmc_depth).
        defines: Preprocessor defines for RTL files (e.g. ["VERILATOR"]).
        flatten: Pass -flatten to yosys prep (default: True).
        top: Top module name (default: properties filename stem).
        tags: Additional tags. "formal" is always included.
        **kwargs: Extra arguments forwarded to py_test.
    """
    if bmc_engine == None:
        bmc_engine = "smtbmc"
    if prove_engine == None:
        prove_engine = "smtbmc" if multiclock else "abc pdr"

    all_tags = ["formal"]
    if tags:
        all_tags = all_tags + [t for t in tags if t not in all_tags]

    args = [
        "--bmc-depth",
        str(bmc_depth),
        "--bmc-engine",
        bmc_engine.replace(" ", ":"),
    ]
    if prove:
        args.extend(["--prove", "--prove-engine", prove_engine.replace(" ", ":")])
        if prove_depth != None:
            args.extend(["--prove-depth", str(prove_depth)])
    if multiclock:
        args.append("--multiclock")
    if not flatten:
        args.append("--no-flatten")
    if top:
        args.extend(["--top", top])
    for d in defines:
        args.extend(["--define", d])

    args.extend(["--properties", "$(location {})".format(properties)])
    for dep in rtl_deps:
        args.extend(["--rtl", "$(locations {})".format(dep)])

    native.py_test(
        name = name,
        srcs = [_RUN_SBY],
        main = _RUN_SBY,
        args = args,
        data = [properties] + rtl_deps,
        tags = all_tags,
        **kwargs
    )
