load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//cocotb:defs.bzl", "cocotb_build", "cocotb_build_test", "cocotb_cfg", "cocotb_test")
load("//rtl:defs.bzl", "verilog_library")

def _sorted_basenames(files):
    return sorted([file.basename for file in files])

def _find_action(actions, mnemonic):
    matches = [action for action in actions if action.mnemonic == mnemonic]
    if not matches:
        fail("Did not find action with mnemonic %r. Saw %s" % (
            mnemonic,
            sorted([action.mnemonic for action in actions]),
        ))
    return matches[0]

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

def _build_driver_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_action(analysistest.target_actions(env), "CocotbBuild")
    input_basenames = _sorted_basenames(action.inputs.to_list())

    asserts.true(env, "cocotb_driver.py" in input_basenames)
    asserts.true(env, "cocotb_runtime.py" in input_basenames)

    return analysistest.end(env)

_build_driver_inputs_test = analysistest.make(_build_driver_inputs_test_impl)

def _test_driver_inputs_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_action(analysistest.target_actions(env), "CocotbTest")
    input_basenames = _sorted_basenames(action.inputs.to_list())

    asserts.true(env, "cocotb_driver.py" in input_basenames)
    asserts.true(env, "cocotb_runtime.py" in input_basenames)

    return analysistest.end(env)

_test_driver_inputs_test = analysistest.make(_test_driver_inputs_test_impl)

def _test_outputs_include_artifacts_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_action(analysistest.target_actions(env), "CocotbTest")
    output_basenames = _sorted_basenames(action.outputs.to_list())

    asserts.true(env, "cocotb_test_target.results.xml" in output_basenames)
    asserts.true(env, "cocotb_test_target.failed_tests.txt" in output_basenames)
    asserts.true(env, "cocotb_test_target.artifacts" in output_basenames)

    return analysistest.end(env)

_test_outputs_include_artifacts_test = analysistest.make(_test_outputs_include_artifacts_test_impl)

def _legacy_macro_build_waves_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_file_write_by_output(
        analysistest.target_actions(env),
        "legacy_cocotb_test_build.build.json",
    )

    asserts.true(env, "\"waves\": true" in action.content)

    return analysistest.end(env)

_legacy_macro_build_waves_test = analysistest.make(_legacy_macro_build_waves_test_impl)

def _legacy_macro_test_waves_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_file_write_by_output(
        analysistest.target_actions(env),
        "legacy_cocotb_test.test.json",
    )

    asserts.true(env, "\"waves\": true" in action.content)

    return analysistest.end(env)

_legacy_macro_test_waves_test = analysistest.make(_legacy_macro_test_waves_test_impl)

def _verilog_library_build_plan_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_file_write_by_output(
        analysistest.target_actions(env),
        "cocotb_mixed_verilog_build.build.json",
    )

    asserts.true(env, "cocotb_dummy_dut.sv" in action.content)
    asserts.true(env, "cocotb_dummy_lib_top.sv" in action.content)
    asserts.true(env, "cocotb_dummy_leaf.sv" in action.content)
    asserts.true(env, "tests/testdata/include_leaf" in action.content)
    asserts.true(env, "tests/testdata/include_top" in action.content)
    asserts.true(env, "tests/testdata/include_user" in action.content)
    asserts.true(env, "\"LEAF_FLAG\": \"\"" in action.content)
    asserts.true(env, "\"WIDTH\": \"32\"" in action.content)
    asserts.true(env, "\"USER_FLAG\": \"1\"" in action.content)

    return analysistest.end(env)

_verilog_library_build_plan_test = analysistest.make(_verilog_library_build_plan_test_impl)

def _verilog_library_header_input_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_action(analysistest.target_actions(env), "CocotbBuild")
    input_basenames = _sorted_basenames(action.inputs.to_list())

    asserts.true(env, "cocotb_dummy_leaf.svh" in input_basenames)

    return analysistest.end(env)

_verilog_library_header_input_test = analysistest.make(_verilog_library_header_input_test_impl)

def _legacy_macro_verilog_library_build_plan_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = _find_file_write_by_output(
        analysistest.target_actions(env),
        "legacy_cocotb_mixed_test_build.build.json",
    )

    asserts.true(env, "cocotb_dummy_dut.sv" in action.content)
    asserts.true(env, "cocotb_dummy_lib_top.sv" in action.content)
    asserts.true(env, "cocotb_dummy_leaf.sv" in action.content)

    return analysistest.end(env)

_legacy_macro_verilog_library_build_plan_test = analysistest.make(_legacy_macro_verilog_library_build_plan_test_impl)

def cocotb_rule_test_suite(name):
    native.filegroup(
        name = "cocotb_dummy_filegroup",
        srcs = ["testdata/cocotb_dummy_dut.sv"],
    )

    verilog_library(
        name = "cocotb_dummy_verilog_leaf",
        srcs = [
            "testdata/cocotb_dummy_leaf.sv",
            "testdata/include_leaf/cocotb_dummy_leaf.svh",
        ],
        includes = ["tests/testdata/include_leaf"],
        defines = ["LEAF_FLAG"],
    )

    verilog_library(
        name = "cocotb_dummy_verilog_lib",
        srcs = [
            "testdata/cocotb_dummy_lib_top.sv",
            "testdata/include_top/cocotb_dummy_top.svh",
        ],
        deps = [":cocotb_dummy_verilog_leaf"],
        includes = ["tests/testdata/include_top"],
        defines = ["WIDTH=32"],
    )

    cocotb_cfg(
        name = "cocotb_test_cfg",
        simulator = "verilator",
    )

    cocotb_build(
        name = "cocotb_test_build",
        cfg = ":cocotb_test_cfg",
        hdl_toplevel = "dummy_dut",
        verilog_sources = ["testdata/cocotb_dummy_dut.sv"],
    )

    cocotb_build(
        name = "cocotb_mixed_verilog_build",
        cfg = ":cocotb_test_cfg",
        hdl_toplevel = "dummy_dut",
        verilog_sources = [
            ":cocotb_dummy_filegroup",
            ":cocotb_dummy_verilog_lib",
        ],
        includes = ["tests/testdata/include_user"],
        defines = {"USER_FLAG": "1"},
    )

    cocotb_test(
        name = "cocotb_test_target",
        build = ":cocotb_test_build",
        test_module = ["testdata/cocotb_dummy_test.py"],
    )

    cocotb_build_test(
        name = "legacy_cocotb_test",
        sim_name = "verilator",
        hdl_toplevel = "dummy_dut",
        verilog_sources = ["testdata/cocotb_dummy_dut.sv"],
        test_module = ["testdata/cocotb_dummy_test.py"],
        waves = True,
    )

    cocotb_build_test(
        name = "legacy_cocotb_mixed_test",
        sim_name = "verilator",
        hdl_toplevel = "dummy_dut",
        verilog_sources = [
            ":cocotb_dummy_filegroup",
            ":cocotb_dummy_verilog_lib",
        ],
        test_module = ["testdata/cocotb_dummy_test.py"],
    )

    _build_driver_inputs_test(
        name = "cocotb_build_driver_inputs_test",
        target_under_test = ":cocotb_test_build",
    )

    _test_driver_inputs_test(
        name = "cocotb_test_driver_inputs_test",
        target_under_test = ":cocotb_test_target",
    )

    _test_outputs_include_artifacts_test(
        name = "cocotb_test_outputs_include_artifacts_test",
        target_under_test = ":cocotb_test_target",
    )

    _legacy_macro_build_waves_test(
        name = "cocotb_legacy_build_waves_test",
        target_under_test = ":legacy_cocotb_test_build",
    )

    _legacy_macro_test_waves_test(
        name = "cocotb_legacy_test_waves_test",
        target_under_test = ":legacy_cocotb_test",
    )

    _verilog_library_build_plan_test(
        name = "cocotb_verilog_library_build_plan_test",
        target_under_test = ":cocotb_mixed_verilog_build",
    )

    _verilog_library_header_input_test(
        name = "cocotb_verilog_library_header_input_test",
        target_under_test = ":cocotb_mixed_verilog_build",
    )

    _legacy_macro_verilog_library_build_plan_test(
        name = "cocotb_legacy_verilog_library_build_plan_test",
        target_under_test = ":legacy_cocotb_mixed_test_build",
    )

    native.test_suite(
        name = name,
        tests = [
            ":cocotb_build_driver_inputs_test",
            ":cocotb_test_driver_inputs_test",
            ":cocotb_test_outputs_include_artifacts_test",
            ":cocotb_legacy_build_waves_test",
            ":cocotb_legacy_test_waves_test",
            ":cocotb_verilog_library_build_plan_test",
            ":cocotb_verilog_library_header_input_test",
            ":cocotb_legacy_verilog_library_build_plan_test",
        ],
    )
