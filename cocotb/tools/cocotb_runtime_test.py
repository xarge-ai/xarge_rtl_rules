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

"""Regression tests for cocotb runtime helper behavior."""

import importlib.util
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


def _fake_runner_module():
    runner_module = types.ModuleType("cocotb_tools.runner")
    runner_module.get_runner = lambda simulator: object()
    return runner_module


def _load_runtime_module():
    sys.modules.pop("cocotb_runtime", None)
    sys.modules.pop("cocotb_runtime_under_test", None)

    package_module = types.ModuleType("cocotb_tools")
    runner_module = _fake_runner_module()
    package_module.runner = runner_module
    runtime_path = Path(__file__).resolve().parent / "cocotb_runtime.py"

    with mock.patch.dict(
            sys.modules,
            {
                "cocotb_tools": package_module,
                "cocotb_tools.runner": runner_module,
            },
            clear = False):
        spec = importlib.util.spec_from_file_location(
            "cocotb_runtime_under_test",
            runtime_path,
        )
        module = importlib.util.module_from_spec(spec)
        sys.modules["cocotb_runtime_under_test"] = module
        spec.loader.exec_module(module)
        return module


class CocotbRuntimeTest(unittest.TestCase):
    def test_find_python_roots_keeps_directory_inputs(self):
        runtime = _load_runtime_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            tests_dir = Path(tmpdir) / "tests"
            tests_dir.mkdir()

            roots = runtime._find_python_roots([str(tests_dir)])

        self.assertIn(str(tests_dir), roots)
        self.assertNotIn(str(tests_dir.parent), roots)

    def test_test_kwargs_use_test_dir_for_runner_and_log_file(self):
        runtime = _load_runtime_module()

        build_dir = Path("/tmp/build")
        test_dir = Path("/tmp/test_modules")
        results_xml = Path("/tmp/results.xml")
        plan = {
            "hdl_toplevel": "dummy_top",
            "hdl_toplevel_library": "top",
            "hdl_toplevel_lang": "verilog",
            "log_file": "sim.log",
        }

        kwargs = runtime._test_kwargs(plan, build_dir, test_dir, results_xml)

        self.assertEqual(str(build_dir), kwargs["build_dir"])
        self.assertEqual(str(test_dir), kwargs["test_dir"])
        self.assertEqual(str(results_xml), kwargs["results_xml"])
        self.assertEqual(str(test_dir / "sim.log"), kwargs["log_file"])


if __name__ == "__main__":
    unittest.main()
