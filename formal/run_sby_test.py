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

"""Unit tests for the SymbiYosys runner helper."""

import argparse
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


def _load_run_sby_module():
    sys.modules.pop("run_sby_under_test", None)
    module_path = Path(__file__).resolve().parent / "run_sby.py"
    spec = importlib.util.spec_from_file_location("run_sby_under_test", module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["run_sby_under_test"] = module
    spec.loader.exec_module(module)
    return module


class RunSbyTest(unittest.TestCase):
    def test_generate_sby_merges_rtl_metadata_includes_and_defines(self):
        run_sby = _load_run_sby_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            props = tmp / "props.sv"
            rtl = tmp / "rtl.sv"
            include_a = tmp / "include_a"
            include_b = tmp / "include_b"
            metadata = tmp / "rtl_metadata.json"

            props.write_text("module props; endmodule\n", encoding = "utf-8")
            rtl.write_text("module rtl; endmodule\n", encoding = "utf-8")
            include_a.mkdir()
            include_b.mkdir()
            metadata.write_text(
                json.dumps(
                    {
                        "includes": [str(include_a), str(include_b), str(include_a)],
                        "defines": ["LEAF_FLAG", "WIDTH=32", "LEAF_FLAG"],
                    },
                    indent = 2,
                ) + "\n",
                encoding = "utf-8",
            )

            args = argparse.Namespace(
                bmc_depth = 20,
                bmc_engine = "smtbmc",
                prove = False,
                prove_engine = "abc pdr",
                prove_depth = None,
                multiclock = False,
                no_flatten = False,
                top = None,
                define = ["EXPLICIT=1", "WIDTH=64"],
                properties = str(props),
                rtl_metadata = str(metadata),
                rtl_files = [str(rtl)],
            )

            sby = run_sby.generate_sby(args)

        rtl_line = "read -formal -I{} -I{} -DLEAF_FLAG -DWIDTH=32 -DEXPLICIT=1 -DWIDTH=64 {}".format(
            include_a.resolve(),
            include_b.resolve(),
            rtl.resolve(),
        )
        props_line = "read -formal -I{} -I{} -DLEAF_FLAG -DWIDTH=32 -DEXPLICIT=1 -DWIDTH=64 {}".format(
            include_a.resolve(),
            include_b.resolve(),
            props.resolve(),
        )

        self.assertIn(rtl_line, sby)
        self.assertIn(props_line, sby)

    def test_generate_sby_resolves_workspace_relative_inputs_from_runfiles(self):
        run_sby = _load_run_sby_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            runfiles_root = tmp / "runfiles"
            workspace_root = runfiles_root / "demo_ws"
            include_dir = workspace_root / "tests" / "testdata" / "include"
            rtl = workspace_root / "rtl" / "dummy.sv"
            props = workspace_root / "tests" / "testdata" / "props.sv"
            metadata = workspace_root / "tests" / "testdata" / "rtl_metadata.json"

            include_dir.mkdir(parents = True)
            rtl.parent.mkdir(parents = True)
            props.parent.mkdir(parents = True, exist_ok = True)
            rtl.write_text("module dummy; endmodule\n", encoding = "utf-8")
            props.write_text("module props; endmodule\n", encoding = "utf-8")
            metadata.write_text(
                json.dumps(
                    {
                        "includes": ["tests/testdata/include"],
                        "defines": ["FROM_RUNFILES=1"],
                    },
                    indent = 2,
                ) + "\n",
                encoding = "utf-8",
            )

            args = argparse.Namespace(
                bmc_depth = 20,
                bmc_engine = "smtbmc",
                prove = False,
                prove_engine = "abc pdr",
                prove_depth = None,
                multiclock = False,
                no_flatten = False,
                top = None,
                define = [],
                properties = "tests/testdata/props.sv",
                rtl_metadata = "tests/testdata/rtl_metadata.json",
                rtl_files = ["rtl/dummy.sv"],
            )

            with mock.patch.dict(
                run_sby.os.environ,
                {
                    "TEST_SRCDIR": str(runfiles_root),
                    "TEST_WORKSPACE": "demo_ws",
                },
                clear = False,
            ):
                sby = run_sby.generate_sby(args)

        rtl_line = "read -formal -I{} -DFROM_RUNFILES=1 {}".format(
            include_dir.resolve(),
            rtl.resolve(),
        )
        props_line = "read -formal -I{} -DFROM_RUNFILES=1 {}".format(
            include_dir.resolve(),
            props.resolve(),
        )

        self.assertIn(rtl_line, sby)
        self.assertIn(props_line, sby)

    def test_generate_sby_without_metadata_keeps_existing_define_behavior(self):
        run_sby = _load_run_sby_module()

        args = argparse.Namespace(
            bmc_depth = 20,
            bmc_engine = "smtbmc",
            prove = False,
            prove_engine = "abc pdr",
            prove_depth = None,
            multiclock = False,
            no_flatten = False,
            top = None,
            define = ["USER=1"],
            properties = "props.sv",
            rtl_metadata = None,
            rtl_files = ["rtl.sv"],
        )

        sby = run_sby.generate_sby(args)

        self.assertIn("read -formal -DUSER=1 {}".format(Path("rtl.sv").resolve()), sby)
        self.assertIn("read -formal -DUSER=1 {}".format(Path("props.sv").resolve()), sby)


if __name__ == "__main__":
    unittest.main()
