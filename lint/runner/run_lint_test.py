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

"""Bug-proof unit tests for the RTL lint runner (lint/runner/run_lint.py).

Each test class documents and demonstrates a specific bug.  Tests are designed
to PASS when the bug is present (proving the bug exists) and to require
updating when the bug is fixed.
"""

import argparse
import importlib.util
import sys
import unittest
from pathlib import Path
from unittest import mock


def _load_run_lint_module():
    sys.modules.pop("run_lint_under_test", None)
    module_path = Path(__file__).resolve().parent / "run_lint.py"
    spec = importlib.util.spec_from_file_location("run_lint_under_test", module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["run_lint_under_test"] = module
    spec.loader.exec_module(module)
    return module


class LintToolSilentSkipBugTests(unittest.TestCase):
    """Tests that prove the silent-skip bug in the lint runner.

    Bug: When verilator or verible-verilog-lint is not found on PATH, the
    runner exits with code 0 (success) instead of failing.  This means a lint
    test "passes" even when the lint tool was never actually executed.

    A correct implementation would either:
      * Exit with a non-zero code when the tool is missing (strict mode), or
      * At minimum print a clear SKIP marker that the CI system can detect.

    Today the runner exits 0 silently, which can mask configuration errors.
    """

    def test_verilator_lint_exits_zero_when_tool_not_found(self):
        """Bug: verilator lint silently passes (exit 0) when verilator is absent.

        When find_tool("verilator") returns None the runner calls sys.exit(0).
        A test that "passes" without running any lint is misleading.
        """
        run_lint = _load_run_lint_module()

        args = argparse.Namespace(
            src = ["tests/testdata/dummy.sv"],
            top = None,
            define = [],
            flag = [],
            waiver = None,
        )

        with mock.patch.object(run_lint, "find_tool", return_value = None):
            with self.assertRaises(SystemExit) as cm:
                run_lint.run_verilator_lint(args)

        # Bug demonstrated: exit code is 0 (success) even though no lint ran.
        # Correct behaviour would be exit code != 0 when strict mode is desired.
        self.assertEqual(
            0,
            cm.exception.code,
            "Bug: verilator lint exits 0 when tool is missing — lint was never run",
        )

    def test_verible_lint_exits_zero_when_tool_not_found(self):
        """Bug: verible-verilog-lint silently passes (exit 0) when absent.

        Mirrors the verilator case: the runner calls sys.exit(0) when the tool
        is not found, making the test appear to pass without any lint being done.
        """
        run_lint = _load_run_lint_module()

        args = argparse.Namespace(
            src = ["tests/testdata/dummy.sv"],
            rules_config = None,
            waiver = None,
            rule_on = [],
            rule_off = [],
        )

        with mock.patch.object(run_lint, "find_tool", return_value = None):
            with self.assertRaises(SystemExit) as cm:
                run_lint.run_verible_lint(args)

        # Bug demonstrated: exit code is 0 even though no lint check ran.
        self.assertEqual(
            0,
            cm.exception.code,
            "Bug: verible lint exits 0 when tool is missing — lint was never run",
        )


class LintTopModuleInferenceBugTests(unittest.TestCase):
    """Tests that prove the fragile top-module inference bug.

    Bug: When no --top is specified, the runner infers the top module name
    from the stem of the FIRST source file's basename.  This has two problems:

    1. File names with hyphens (e.g. "my-module.sv") produce an invalid
       Verilog module name ("my-module") that verilator rejects.

    2. When multiple source files are passed the inferred name depends on
       Bazel's ordering of $(locations ...) expansion, which is not guaranteed
       to be stable across runs.

    The correct fix is to require an explicit --top when multiple sources are
    provided, or to validate the inferred name before use.
    """

    def test_hyphenated_filename_produces_invalid_verilog_module_name(self):
        """Bug: a source file named 'my-module.sv' causes an invalid --top-module.

        os.path.splitext('my-module.sv')[0] == 'my-module', which is not a
        valid Verilog identifier.  Verilator will emit an error, but the runner
        never validates the name before constructing the command.
        """
        run_lint = _load_run_lint_module()

        args = argparse.Namespace(
            src = ["my-module.sv"],   # hyphen makes stem an invalid identifier
            top = None,               # force inference from filename
            define = [],
            flag = [],
            waiver = None,
        )

        captured_cmd = []

        def _fake_run(cmd, **_kwargs):
            captured_cmd.extend(cmd)
            class _R:
                returncode = 0
                stdout = ""
                stderr = ""
            return _R()

        import subprocess
        with mock.patch.object(run_lint, "find_tool", return_value = "/usr/bin/verilator"):
            with mock.patch("subprocess.run", side_effect = _fake_run):
                run_lint.run_verilator_lint(args)

        # Find the value passed to --top-module
        try:
            idx = captured_cmd.index("--top-module")
            inferred_top = captured_cmd[idx + 1]
        except ValueError:
            self.fail("--top-module flag was not emitted in the command")

        # Bug demonstrated: the inferred name contains a hyphen, which is
        # not a valid Verilog identifier.
        self.assertIn(
            "-",
            inferred_top,
            "Bug: inferred top module name '%s' contains a hyphen — "
            "this is not a valid Verilog identifier" % inferred_top,
        )


if __name__ == "__main__":
    unittest.main()
