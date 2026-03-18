load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("//corsair:defs.bzl", "CorsairInfo", "corsair_generate", "corsair_snapshot_manifest")
load("//rtl:providers.bzl", "VerilogInfo")

def _sorted_basenames(files):
    return sorted([file.basename for file in files])

def _find_actions(actions, mnemonic):
    matches = [action for action in actions if action.mnemonic == mnemonic]
    if not matches:
        fail("Did not find action with mnemonic %r. Saw %s" % (
            mnemonic,
            sorted([action.mnemonic for action in actions]),
        ))
    return matches

def _find_file_write_by_output(actions, basename):
    matches = []
    for action in actions:
        if action.mnemonic != "FileWrite":
            continue
        output_basenames = _sorted_basenames(action.outputs.to_list())
        if basename in output_basenames:
            matches.append(action)
    if not matches:
        fail("Did not find FileWrite action for %r." % basename)
    return matches[0]

def _minimal_generate_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(
        env,
        [
            "uart_regs_minimal.h",
            "uart_regs_minimal.py",
            "uart_regs_minimal.v",
            "uart_regs_minimal_pkg.sv",
        ],
        _sorted_basenames(target[DefaultInfo].files.to_list()),
    )

    info = target[CorsairInfo]
    asserts.equals(env, ["uart_regs_minimal.v"], _sorted_basenames(info.rtl.to_list()))
    asserts.equals(env, ["uart_regs_minimal_pkg.sv"], _sorted_basenames(info.sv.to_list()))
    asserts.equals(env, [], _sorted_basenames(info.vh.to_list()))
    asserts.equals(env, ["uart_regs_minimal.h"], _sorted_basenames(info.c.to_list()))
    asserts.equals(env, ["uart_regs_minimal.py"], _sorted_basenames(info.py.to_list()))
    asserts.equals(env, [], _sorted_basenames(info.docs.to_list()))
    asserts.equals(env, [], _sorted_basenames(info.doc_dirs.to_list()))
    asserts.equals(env, [], _sorted_basenames(info.data.to_list()))

    groups = target[OutputGroupInfo]
    asserts.equals(
        env,
        [
            "uart_regs_minimal.h",
            "uart_regs_minimal.py",
            "uart_regs_minimal.v",
            "uart_regs_minimal_pkg.sv",
        ],
        _sorted_basenames(groups.all_generated.to_list()),
    )
    asserts.equals(env, ["uart_regs_minimal.v"], _sorted_basenames(groups.rtl.to_list()))
    asserts.equals(env, ["uart_regs_minimal_pkg.sv"], _sorted_basenames(groups.sv.to_list()))
    asserts.equals(env, ["uart_regs_minimal.h"], _sorted_basenames(groups.c.to_list()))
    asserts.equals(env, ["uart_regs_minimal.py"], _sorted_basenames(groups.python.to_list()))

    verilog = target[VerilogInfo]
    asserts.equals(
        env,
        ["uart_regs_minimal.v", "uart_regs_minimal_pkg.sv"],
        _sorted_basenames(verilog.srcs.to_list()),
    )
    asserts.equals(env, [], sorted(verilog.includes.to_list()))

    actions = analysistest.target_actions(env)
    asserts.equals(env, 1, len(_find_actions(actions, "FileWrite")))
    asserts.equals(env, 1, len(_find_actions(actions, "CorsairGenerate")))

    return analysistest.end(env)

_minimal_generate_test = analysistest.make(_minimal_generate_test_impl)

def _csrconfig_generate_test_impl(ctx):
    env = analysistest.begin(ctx)

    actions = analysistest.target_actions(env)
    run_action = _find_actions(actions, "CorsairGenerate")[0]
    input_basenames = _sorted_basenames(run_action.inputs.to_list())

    asserts.true(env, "uart_regs.yaml" in input_basenames)
    asserts.true(env, "uart_regs.csrconfig" in input_basenames)
    asserts.true(env, "uart_regs_with_csrconfig__corsair.csrconfig" in input_basenames)

    return analysistest.end(env)

_csrconfig_generate_test = analysistest.make(_csrconfig_generate_test_impl)

def _snapshot_manifest_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(
        env,
        ["uart_regs_manifest.json"],
        _sorted_basenames(target[DefaultInfo].files.to_list()),
    )

    action = _find_actions(analysistest.target_actions(env), "FileWrite")[0]
    asserts.true(env, "\"target_name\": \"uart_regs_minimal\"" in action.content)
    asserts.true(env, "\"relative_path\": \"uart_regs_minimal.v\"" in action.content)
    asserts.true(env, "\"relative_path\": \"uart_regs_minimal_pkg.sv\"" in action.content)

    return analysistest.end(env)

_snapshot_manifest_test = analysistest.make(_snapshot_manifest_test_impl)

def _publish_launcher_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(
        env,
        ["uart_regs_publish_enabled_publish"],
        _sorted_basenames(target[DefaultInfo].files.to_list()),
    )

    actions = analysistest.target_actions(env)
    launcher_action = _find_file_write_by_output(actions, "uart_regs_publish_enabled_publish")

    asserts.true(env, "BUILD_WORKSPACE_DIRECTORY" in launcher_action.content)
    asserts.true(env, "RUNFILES_DIR" in launcher_action.content)
    asserts.true(env, "tests/registers/hw/uart_regs_publish_enabled.v" in launcher_action.content)
    asserts.true(env, "tests/registers/hw/uart_regs_publish_enabled_pkg.sv" in launcher_action.content)
    asserts.true(env, "tests/registers/sw/uart_regs_publish_enabled.h" in launcher_action.content)
    asserts.true(env, "tests/registers/sw/uart_regs_publish_enabled.py" in launcher_action.content)
    asserts.true(env, "tests/registers/doc/uart_regs_publish_enabled.md" in launcher_action.content)
    asserts.true(env, "tests/registers/doc/uart_regs_publish_enabled_img" in launcher_action.content)

    return analysistest.end(env)

_publish_launcher_test = analysistest.make(_publish_launcher_test_impl)

def _publish_workspace_root_launcher_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    asserts.equals(
        env,
        ["uart_regs_publish_workspace_root_publish"],
        _sorted_basenames(target[DefaultInfo].files.to_list()),
    )

    actions = analysistest.target_actions(env)
    launcher_action = _find_file_write_by_output(actions, "uart_regs_publish_workspace_root_publish")

    asserts.true(env, "registers/uart/hw/uart_regs_publish_workspace_root.v" in launcher_action.content)
    asserts.true(env, "registers/uart/hw/uart_regs_publish_workspace_root_pkg.sv" in launcher_action.content)
    asserts.true(env, "registers/uart/sw/uart_regs_publish_workspace_root.h" in launcher_action.content)
    asserts.true(env, "registers/uart/sw/uart_regs_publish_workspace_root.py" in launcher_action.content)
    asserts.true(env, "registers/uart/doc/uart_regs_publish_workspace_root.md" in launcher_action.content)
    asserts.false(env, "tests/registers/uart/" in launcher_action.content)

    return analysistest.end(env)

_publish_workspace_root_launcher_test = analysistest.make(_publish_workspace_root_launcher_test_impl)

def _invalid_attr_test_impl(ctx):
    env = analysistest.begin(ctx)
    asserts.expect_failure(env, "rtl_out requires rtl = True.")
    return analysistest.end(env)

_invalid_attr_test = analysistest.make(
    _invalid_attr_test_impl,
    expect_failure = True,
)

def corsair_rule_test_suite(name):
    corsair_generate(
        name = "uart_regs_minimal",
        regmap = "testdata/uart_regs.yaml",
    )

    corsair_generate(
        name = "uart_regs_with_csrconfig",
        regmap = "testdata/uart_regs.yaml",
        csrconfig = "testdata/uart_regs.csrconfig",
    )

    corsair_generate(
        name = "uart_regs_invalid_rtl_out",
        regmap = "testdata/uart_regs.yaml",
        rtl = False,
        rtl_out = "unexpected.v",
    )

    corsair_generate(
        name = "uart_regs_publish_enabled",
        regmap = "testdata/uart_regs.yaml",
        markdown = True,
        publish = True,
        publish_root = "registers",
    )

    corsair_generate(
        name = "uart_regs_publish_workspace_root",
        regmap = "testdata/uart_regs.yaml",
        markdown = True,
        publish = True,
        publish_root = "@project_name/registers/uart",
    )

    corsair_snapshot_manifest(
        name = "uart_regs_manifest",
        src = ":uart_regs_minimal",
    )

    _minimal_generate_test(
        name = "corsair_generate_minimal_test",
        target_under_test = ":uart_regs_minimal",
    )

    _csrconfig_generate_test(
        name = "corsair_generate_csrconfig_test",
        target_under_test = ":uart_regs_with_csrconfig",
    )

    _snapshot_manifest_test(
        name = "corsair_snapshot_manifest_test",
        target_under_test = ":uart_regs_manifest",
    )

    _publish_launcher_test(
        name = "corsair_publish_launcher_test",
        target_under_test = ":uart_regs_publish_enabled_publish",
    )

    _publish_workspace_root_launcher_test(
        name = "corsair_publish_workspace_root_launcher_test",
        target_under_test = ":uart_regs_publish_workspace_root_publish",
    )

    _invalid_attr_test(
        name = "corsair_generate_invalid_attr_test",
        target_under_test = ":uart_regs_invalid_rtl_out",
    )

    native.test_suite(
        name = name,
        tests = [
            ":corsair_generate_minimal_test",
            ":corsair_generate_csrconfig_test",
            ":corsair_snapshot_manifest_test",
            ":corsair_publish_launcher_test",
            ":corsair_publish_workspace_root_launcher_test",
            ":corsair_generate_invalid_attr_test",
        ],
    )
