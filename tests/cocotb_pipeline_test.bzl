load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//cocotb:defs.bzl", "cocotb_build", "cocotb_cfg", "cocotb_test")

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

def cocotb_rule_test_suite(name):
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

    cocotb_test(
        name = "cocotb_test_target",
        build = ":cocotb_test_build",
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

    native.test_suite(
        name = name,
        tests = [
            ":cocotb_build_driver_inputs_test",
            ":cocotb_test_driver_inputs_test",
        ],
    )
