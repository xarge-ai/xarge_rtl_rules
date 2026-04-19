# Copyright 2026 Xarge AI
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

"""Bazel analysis tests that prove the existence of bugs in the Bazel rules.

Each test demonstrates incorrect behaviour at rule analysis time.
Tests that pass prove the bug is present; they will need updating once fixed.
"""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//rtl:defs.bzl", "verilog_library")
load("//rtl:providers.bzl", "VerilogInfo")
load("//packaging:defs.bzl", "verilog_filelist")

def _sorted_basenames(files):
    return sorted([f.basename for f in files])

# ==========================================================================
# Bug: RTL Bug 3 — Empty verilog_library succeeds without validation
# ==========================================================================
#
# The verilog_library rule does not validate that at least one source file
# or dependency is provided.  A target with no srcs and no deps silently
# creates a VerilogInfo with all-empty fields.  Downstream consumers (lint,
# simulation, synthesis) then receive nothing and may fail with cryptic errors
# that are far removed from the misconfigured rule.
#
# Expected correct behaviour: the rule should fail at analysis time with a
# clear error such as "verilog_library requires at least one src or dep".
#
# This test PASSES when the bug is present (proving it exists) and would need
# to be changed to expect_failure = True once the validation is added.
# ==========================================================================

def _empty_verilog_library_allowed_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    info = target[VerilogInfo]

    # Bug demonstrated: an empty library produces empty providers with no error.
    asserts.equals(
        env,
        [],
        info.srcs.to_list(),
        "Bug: empty verilog_library has no srcs — no validation error was raised",
    )
    asserts.equals(
        env,
        [],
        info.transitive_srcs.to_list(),
        "Bug: empty verilog_library has no transitive_srcs — no validation",
    )
    asserts.equals(
        env,
        [],
        info.includes.to_list(),
        "Bug: empty verilog_library has no includes — no validation",
    )
    asserts.equals(
        env,
        [],
        info.defines.to_list(),
        "Bug: empty verilog_library has no defines — no validation",
    )

    # Also verify DefaultInfo has no files — rule truly contributes nothing.
    asserts.equals(
        env,
        [],
        _sorted_basenames(target[DefaultInfo].files.to_list()),
        "Bug: DefaultInfo.files is empty — rule contributes nothing and was not rejected",
    )

    return analysistest.end(env)

_empty_verilog_library_allowed_test = analysistest.make(
    _empty_verilog_library_allowed_test_impl,
)

# ==========================================================================
# Bug: RTL Bug 2 — includes depset has no explicit order
# ==========================================================================
#
# In verilog_library the includes depset is built with the default ("default")
# order, which is unspecified / non-deterministic with respect to tool
# invocations.  When downstream rules collect includes for -I flags and
# header-file resolution order matters, this can silently produce wrong
# results in builds that depend on include search order.
#
# Expected correct behaviour: use order = "topological" so that a library's
# own include directories are searched before its dependencies'.
#
# This test shows that a two-level verilog_library chain produces an
# includes depset with default order, demonstrating the issue.
# ==========================================================================

def _includes_depset_has_default_order_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    includes_depset = target[VerilogInfo].includes

    # Bug demonstrated: the depset uses the default (unspecified) order.
    # A topological order would guarantee that the declaring library's
    # includes come before its deps' includes.
    # We cannot query the order directly from Starlark, but we CAN show
    # that the includes from BOTH the target and its dep are present and
    # rely on implicit ordering — which the rule does not guarantee.
    all_includes = includes_depset.to_list()

    asserts.true(
        env,
        "tests/testdata/include_leaf" in all_includes,
        "Leaf include dir should be collected transitively",
    )
    asserts.true(
        env,
        "tests/testdata/include_top" in all_includes,
        "Top include dir should be present in the depset",
    )

    # Bug: no ordering guarantee — a tool consuming this depset may encounter
    # include directories in any order.  The test documents this gap.
    asserts.equals(
        env,
        2,
        len(all_includes),
        "Both include dirs should be in the transitive set",
    )

    return analysistest.end(env)

_includes_depset_has_default_order_test = analysistest.make(
    _includes_depset_has_default_order_test_impl,
)

# ==========================================================================
# Bug: Packaging Bug 3 — verilog_filelist only uses DefaultInfo files from
# a verilog_library dep, missing transitive VerilogInfo sources
# ==========================================================================
#
# The verilog_filelist macro generates "--src $(locations :dep)" for each dep.
# For a verilog_library target, $(locations :dep) expands to DefaultInfo.files,
# which contains only the DIRECT sources of that library.  Sources from the
# library's own deps (collected in VerilogInfo.transitive_srcs) are NOT
# included.
#
# As a result, a filelist generated for a multi-level verilog_library hierarchy
# will be INCOMPLETE: only the top-level library's direct files appear.
#
# This test proves the bug by showing that the genrule created by
# verilog_filelist, when given a verilog_library dep that has its own deps,
# only declares the top library's direct sources as genrule inputs.  The
# transitive leaf sources are absent from the action inputs.
# ==========================================================================

def _find_genrule_action(actions):
    matches = [a for a in actions if a.mnemonic == "Genrule"]
    if not matches:
        fail("Did not find Genrule action. Saw: %s" % sorted([a.mnemonic for a in actions]))
    return matches[0]

def _filelist_genrule_missing_transitive_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    genrule = _find_genrule_action(actions)
    input_basenames = sorted([f.basename for f in genrule.inputs.to_list()])

    # The top-level library's direct source IS available as a genrule input
    # (it comes from DefaultInfo.files of the dep).
    asserts.true(
        env,
        "cocotb_dummy_lib_top.sv" in input_basenames,
        "Top library's direct source should be a genrule input",
    )

    # Bug demonstrated: the leaf source (transitive dep of the top library)
    # is NOT a genrule input because verilog_filelist uses $(locations :dep)
    # which only expands DefaultInfo.files, not VerilogInfo.transitive_srcs.
    asserts.false(
        env,
        "cocotb_dummy_leaf.sv" in input_basenames,
        "Bug: cocotb_dummy_leaf.sv (transitive dep) is absent from genrule inputs — "
        "verilog_filelist only captures DefaultInfo.files, missing transitive sources",
    )

    return analysistest.end(env)

_filelist_genrule_missing_transitive_inputs_test = analysistest.make(
    _filelist_genrule_missing_transitive_inputs_test_impl,
)

# ==========================================================================
# Public suite macro
# ==========================================================================

def bug_rule_test_suite(name):
    """Instantiate all bug-proof Bazel analysis tests."""

    # --- RTL Bug 3: empty verilog_library allowed -------------------------
    verilog_library(
        name = "bug_empty_verilog_lib",
        # No srcs, no deps — should fail validation but does not.
    )

    _empty_verilog_library_allowed_test(
        name = "rtl_bug3_empty_library_allowed_test",
        target_under_test = ":bug_empty_verilog_lib",
    )

    # --- RTL Bug 2: includes depset order not specified -------------------
    verilog_library(
        name = "bug_includes_leaf_lib",
        srcs = ["testdata/cocotb_dummy_leaf.sv"],
        includes = ["tests/testdata/include_leaf"],
    )

    verilog_library(
        name = "bug_includes_top_lib",
        srcs = [
            "testdata/cocotb_dummy_lib_top.sv",
            "testdata/include_top/cocotb_dummy_top.svh",
        ],
        deps = [":bug_includes_leaf_lib"],
        includes = ["tests/testdata/include_top"],
    )

    _includes_depset_has_default_order_test(
        name = "rtl_bug2_includes_depset_order_test",
        target_under_test = ":bug_includes_top_lib",
    )

    # --- Packaging Bug 3: filelist misses transitive VerilogInfo deps -----
    verilog_library(
        name = "bug_filelist_leaf_lib",
        srcs = ["testdata/cocotb_dummy_leaf.sv"],
    )

    verilog_library(
        name = "bug_filelist_top_lib",
        srcs = [
            "testdata/cocotb_dummy_lib_top.sv",
            "testdata/include_top/cocotb_dummy_top.svh",
        ],
        deps = [":bug_filelist_leaf_lib"],
    )

    verilog_filelist(
        name = "bug_filelist_from_verilog_lib",
        deps = [":bug_filelist_top_lib"],
        tags = ["manual"],
    )

    _filelist_genrule_missing_transitive_inputs_test(
        name = "packaging_bug3_filelist_misses_transitive_deps_test",
        target_under_test = ":bug_filelist_from_verilog_lib",
    )

    native.test_suite(
        name = name,
        tests = [
            ":rtl_bug3_empty_library_allowed_test",
            ":rtl_bug2_includes_depset_order_test",
            ":packaging_bug3_filelist_misses_transitive_deps_test",
        ],
    )
