load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//formal:defs.bzl", "sby_test")
load("//rtl:defs.bzl", "verilog_library")

def _sorted_basenames(files):
    return sorted([file.basename for file in files])

def _find_file_write_by_output(actions, basename):
    matches = []
    for action in actions:
        if action.mnemonic != "FileWrite":
            continue
        if basename in _sorted_basenames(action.outputs.to_list()):
            matches.append(action)
    if not matches:
        fail("Did not find FileWrite action for %r." % basename)
    return matches[0]

def _rtl_metadata_manifest_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_file_write_by_output(
        analysistest.target_actions(env),
        "formal_sby_dummy_rtl_metadata.json",
    )

    asserts.true(env, "tests/testdata/include_leaf" in action.content)
    asserts.true(env, "tests/testdata/include_top" in action.content)
    asserts.true(env, '"LEAF_FLAG"' in action.content)
    asserts.true(env, '"WIDTH=32"' in action.content)

    return analysistest.end(env)

_rtl_metadata_manifest_test = analysistest.make(_rtl_metadata_manifest_test_impl)

def _sby_target_smoke_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    asserts.true(env, target[DefaultInfo].files_to_run.executable != None)
    return analysistest.end(env)

_sby_target_smoke_test = analysistest.make(_sby_target_smoke_test_impl)

def formal_rule_test_suite(name):
    native.filegroup(
        name = "formal_dummy_filegroup",
        srcs = ["testdata/cocotb_dummy_dut.sv"],
    )

    verilog_library(
        name = "formal_dummy_verilog_leaf",
        srcs = [
            "testdata/cocotb_dummy_leaf.sv",
            "testdata/include_leaf/cocotb_dummy_leaf.svh",
        ],
        includes = ["tests/testdata/include_leaf"],
        defines = ["LEAF_FLAG"],
    )

    verilog_library(
        name = "formal_dummy_verilog_lib",
        srcs = [
            "testdata/cocotb_dummy_lib_top.sv",
            "testdata/include_top/cocotb_dummy_top.svh",
        ],
        deps = [":formal_dummy_verilog_leaf"],
        includes = ["tests/testdata/include_top"],
        defines = ["WIDTH=32"],
    )

    sby_test(
        name = "formal_sby_dummy",
        properties = "testdata/formal_dummy_properties.sv",
        rtl_deps = [
            "testdata/cocotb_dummy_dut.sv",
            ":formal_dummy_filegroup",
            ":formal_dummy_verilog_lib",
        ],
        defines = ["EXPLICIT=1"],
    )

    _rtl_metadata_manifest_test(
        name = "formal_rtl_metadata_manifest_test",
        target_under_test = ":formal_sby_dummy_rtl_metadata",
    )

    _sby_target_smoke_test(
        name = "formal_sby_target_smoke_test",
        target_under_test = ":formal_sby_dummy",
    )

    native.test_suite(
        name = name,
        tests = [
            ":formal_rtl_metadata_manifest_test",
            ":formal_sby_target_smoke_test",
        ],
    )
