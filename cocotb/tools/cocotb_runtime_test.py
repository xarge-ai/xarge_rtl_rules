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
import json
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

    def test_build_kwargs_adds_trace_fst_for_verilator(self):
        runtime = _load_runtime_module()

        kwargs = runtime._build_kwargs(
            {
                "simulator": "verilator",
                "hdl_library": "top",
                "hdl_toplevel": "dummy_top",
                "sources": [],
                "build_args": [],
                "waves": True,
                "wave_format": "fst",
            },
            Path("/tmp/build"),
        )

        self.assertIn("--trace-fst", kwargs["build_args"])

    def test_test_kwargs_do_not_pass_wave_control_args_to_runner(self):
        runtime = _load_runtime_module()

        kwargs = runtime._test_kwargs(
            {
                "hdl_toplevel": "dummy_top",
                "hdl_toplevel_library": "top",
                "hdl_toplevel_lang": "verilog",
                "wave_output": "waves/custom.vcd",
                "wave_format": "fst",
            },
            Path("/tmp/build"),
            Path("/tmp/test_modules"),
            Path("/tmp/results.xml"),
        )

        self.assertNotIn("wave_output", kwargs)
        self.assertNotIn("wave_format", kwargs)

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

    def test_run_test_plan_stages_default_waveform_and_records_failures(self):
        runtime = _load_runtime_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            build_dir = tmp / "build"
            build_dir.mkdir()
            module_path = tmp / "test_example.py"
            module_path.write_text("pass\n", encoding = "utf-8")
            plan_path = tmp / "plan.json"
            plan_path.write_text(json.dumps({
                "simulator": "verilator",
                "hdl_toplevel": "dummy_top",
                "hdl_toplevel_library": "top",
                "hdl_toplevel_lang": "verilog",
                "python_sources": [],
                "test_modules": [
                    {
                        "basename": "test_example.py",
                        "module_name": "test_example",
                        "path": module_path.as_posix(),
                        "short_path": "test_example.py",
                    },
                ],
                "waves": True,
            }, indent = 2) + "\n", encoding = "utf-8")

            def _fake_test(**kwargs):
                test_dir = Path(kwargs["test_dir"])
                test_dir.mkdir(parents = True, exist_ok = True)
                (test_dir / "dump.vcd").write_text("$date\n", encoding = "utf-8")
                Path(kwargs["results_xml"]).write_text(
                    '<testsuite tests="1" failures="1"></testsuite>\n',
                    encoding = "utf-8",
                )
                return None

            fake_runner = mock.Mock()
            fake_runner.test.side_effect = _fake_test

            results_out = tmp / "out" / "results.xml"
            failed_tests_out = tmp / "out" / "failed_tests.txt"
            artifacts_dir_out = tmp / "out" / "artifacts"

            with mock.patch.object(runtime, "get_runner", return_value = fake_runner):
                with mock.patch.object(runtime, "_configure_python_environment"):
                    with mock.patch.object(runtime, "_configure_cocotb_library_path"):
                        exit_code = runtime.run_test_plan(
                            plan_path = plan_path,
                            build_dir = build_dir,
                            results_xml_out = results_out,
                            failed_tests_out = failed_tests_out,
                            artifacts_dir_out = artifacts_dir_out,
                        )

            self.assertEqual(0, exit_code)
            self.assertTrue(results_out.exists())
            self.assertEqual("1", failed_tests_out.read_text(encoding = "utf-8").strip())
            self.assertTrue((artifacts_dir_out / "dump.vcd").exists())

    def test_run_test_plan_stages_custom_waveform_path(self):
        runtime = _load_runtime_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            build_dir = tmp / "build"
            build_dir.mkdir()
            module_path = tmp / "test_example.py"
            module_path.write_text("pass\n", encoding = "utf-8")
            plan_path = tmp / "plan.json"
            plan_path.write_text(json.dumps({
                "simulator": "verilator",
                "hdl_toplevel": "dummy_top",
                "hdl_toplevel_library": "top",
                "hdl_toplevel_lang": "verilog",
                "python_sources": [],
                "test_modules": [
                    {
                        "basename": "test_example.py",
                        "module_name": "test_example",
                        "path": module_path.as_posix(),
                        "short_path": "test_example.py",
                    },
                ],
                "waves": True,
                "wave_output": "waves/custom.vcd",
            }, indent = 2) + "\n", encoding = "utf-8")

            def _fake_test(**kwargs):
                test_dir = Path(kwargs["test_dir"])
                test_dir.mkdir(parents = True, exist_ok = True)
                (test_dir / "dump.vcd").write_text("$date\n", encoding = "utf-8")
                Path(kwargs["results_xml"]).write_text(
                    '<testsuite tests="1" failures="0"></testsuite>\n',
                    encoding = "utf-8",
                )
                return None

            fake_runner = mock.Mock()
            fake_runner.test.side_effect = _fake_test

            results_out = tmp / "out" / "results.xml"
            failed_tests_out = tmp / "out" / "failed_tests.txt"
            artifacts_dir_out = tmp / "out" / "artifacts"

            with mock.patch.object(runtime, "get_runner", return_value = fake_runner):
                with mock.patch.object(runtime, "_configure_python_environment"):
                    with mock.patch.object(runtime, "_configure_cocotb_library_path"):
                        exit_code = runtime.run_test_plan(
                            plan_path = plan_path,
                            build_dir = build_dir,
                            results_xml_out = results_out,
                            failed_tests_out = failed_tests_out,
                            artifacts_dir_out = artifacts_dir_out,
                        )

            self.assertEqual(0, exit_code)
            self.assertTrue((artifacts_dir_out / "waves" / "custom.vcd").exists())
            self.assertFalse((artifacts_dir_out / "dump.vcd").exists())

    def test_run_test_plan_stages_fst_waveform_path(self):
        runtime = _load_runtime_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            build_dir = tmp / "build"
            build_dir.mkdir()
            module_path = tmp / "test_example.py"
            module_path.write_text("pass\n", encoding = "utf-8")
            plan_path = tmp / "plan.json"
            plan_path.write_text(json.dumps({
                "simulator": "verilator",
                "hdl_toplevel": "dummy_top",
                "hdl_toplevel_library": "top",
                "hdl_toplevel_lang": "verilog",
                "python_sources": [],
                "test_modules": [
                    {
                        "basename": "test_example.py",
                        "module_name": "test_example",
                        "path": module_path.as_posix(),
                        "short_path": "test_example.py",
                    },
                ],
                "waves": True,
                "wave_output": "waves/custom.fst",
                "wave_format": "fst",
            }, indent = 2) + "\n", encoding = "utf-8")

            def _fake_test(**kwargs):
                test_dir = Path(kwargs["test_dir"])
                test_dir.mkdir(parents = True, exist_ok = True)
                (test_dir / "dump.fst").write_text("fst\n", encoding = "utf-8")
                Path(kwargs["results_xml"]).write_text(
                    '<testsuite tests="1" failures="0"></testsuite>\n',
                    encoding = "utf-8",
                )
                return None

            fake_runner = mock.Mock()
            fake_runner.test.side_effect = _fake_test

            with mock.patch.object(runtime, "get_runner", return_value = fake_runner):
                with mock.patch.object(runtime, "_configure_python_environment"):
                    with mock.patch.object(runtime, "_configure_cocotb_library_path"):
                        exit_code = runtime.run_test_plan(
                            plan_path = plan_path,
                            build_dir = build_dir,
                            results_xml_out = tmp / "out" / "results.xml",
                            failed_tests_out = tmp / "out" / "failed_tests.txt",
                            artifacts_dir_out = tmp / "out" / "artifacts",
                        )

            self.assertEqual(0, exit_code)
            self.assertTrue((tmp / "out" / "artifacts" / "waves" / "custom.fst").exists())
            self.assertFalse((tmp / "out" / "artifacts" / "dump.fst").exists())

    def test_wave_output_validation_rejects_unsafe_paths(self):
        runtime = _load_runtime_module()

        with self.assertRaises(ValueError):
            runtime._wave_artifact_request({
                "simulator": "verilator",
                "waves": True,
                "wave_output": "/tmp/bad.vcd",
            })

        with self.assertRaises(ValueError):
            runtime._wave_artifact_request({
                "simulator": "verilator",
                "waves": True,
                "wave_output": "../bad.vcd",
            })


if __name__ == "__main__":
    unittest.main()
