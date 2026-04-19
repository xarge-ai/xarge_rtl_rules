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


class FormalBugProofTests(unittest.TestCase):
    """Tests that prove the existence of known bugs in the formal verification rules.

    Each test demonstrates incorrect or missing behaviour that a user would
    experience today.  When a bug is fixed the corresponding test should be
    updated or removed.
    """

    # ------------------------------------------------------------------
    # Bug: prove_depth silently ignored when prove=False  (Formal Bug 3)
    # ------------------------------------------------------------------
    # In formal/defs.bzl the macro only emits --prove-depth when prove=True:
    #
    #   if prove:
    #       args.extend(["--prove", "--prove-engine", ...])
    #       if prove_depth != None:
    #           args.extend(["--prove-depth", str(prove_depth)])
    #
    # When prove=False the prove_depth value is discarded without any warning
    # or error, so the user's setting has absolutely no effect.
    # ------------------------------------------------------------------

    def test_prove_depth_value_absent_from_output_when_prove_disabled(self):
        """Bug: prove_depth is silently ignored when prove=False.

        A user who writes sby_test(prove=False, prove_depth=42) expects either:
          * a validation error telling them prove_depth requires prove=True, or
          * the value to be stored for future use.

        Instead the value is discarded silently.  This test demonstrates the
        bug by showing that 42 never appears in the generated .sby content.
        """
        run_sby = _load_run_sby_module()

        args = argparse.Namespace(
            bmc_depth = 20,
            bmc_engine = "smtbmc",
            prove = False,        # prove mode disabled
            prove_engine = "smtbmc",
            prove_depth = 42,     # user specified this, but it will be ignored
            multiclock = False,
            no_flatten = False,
            top = "my_top",
            define = [],
            properties = "props.sv",
            rtl_metadata = None,
            rtl_files = ["rtl.sv"],
        )

        sby = run_sby.generate_sby(args)

        # Bug demonstrated: the prove_depth value never reaches the .sby file.
        self.assertNotIn("42", sby,
            "Bug: prove_depth=42 should warn the user but is silently dropped")
        self.assertNotIn("prove: depth", sby,
            "Bug: no prove depth line should exist since prove_depth is ignored")

    def test_no_prove_section_generated_when_prove_false_regardless_of_depth(self):
        """Bug: no validation that prove_depth requires prove=True.

        The runner generates a correct .sby when prove=False, but the Bazel
        macro silently drops the prove_depth argument without feedback to the
        user.  Comparing prove=True (depth present) vs prove=False (depth absent)
        shows the discrepancy.
        """
        run_sby = _load_run_sby_module()

        base = argparse.Namespace(
            bmc_depth = 10,
            bmc_engine = "smtbmc",
            prove_engine = "smtbmc",
            prove_depth = 50,
            multiclock = False,
            no_flatten = False,
            top = "top",
            define = [],
            properties = "props.sv",
            rtl_metadata = None,
            rtl_files = ["rtl.sv"],
        )

        # With prove=True the depth IS present
        base.prove = True
        sby_with_prove = run_sby.generate_sby(base)
        self.assertIn("prove: depth 50", sby_with_prove,
            "prove: depth should appear when prove=True")

        # With prove=False the depth is silently absent — bug demonstrated
        base.prove = False
        sby_without_prove = run_sby.generate_sby(base)
        self.assertNotIn("prove: depth", sby_without_prove,
            "Bug: prove_depth=50 is completely absent when prove=False")
        self.assertNotIn("50", sby_without_prove,
            "Bug: value 50 never appears in .sby; user gets no feedback")

    # ------------------------------------------------------------------
    # Bug: engine token encoding is undocumented and can be bypassed
    # (Formal Bug 2 — engine encoding edge case)
    # ------------------------------------------------------------------
    # The sby_test macro converts spaces to colons in engine names
    # (.replace(" ", ":")) so that "abc pdr" survives shell tokenization.
    # The runner's main() converts them back (.replace(":", " ")).
    #
    # BUT generate_sby() itself performs NO conversion — it uses the engine
    # string as-is.  If the runner is called in a non-Bazel context (e.g.,
    # directly from a script), the caller must perform the colon→space
    # conversion manually.  Calling generate_sby() with "abc:pdr" produces
    # an invalid .sby engine token.
    # ------------------------------------------------------------------

    def test_generate_sby_uses_engine_string_verbatim_without_decoding(self):
        """Bug: generate_sby() outputs the engine string with no colon-to-space
        conversion.  The conversion belongs to main() only.

        When called directly (e.g. from tests or scripts) with a colon-encoded
        engine string such as "abc:pdr", generate_sby() emits "abc:pdr" into
        the .sby file, which is NOT valid SymbiYosys engine syntax.
        A valid .sby file requires "abc pdr" (space-separated tokens).
        """
        run_sby = _load_run_sby_module()

        args = argparse.Namespace(
            bmc_depth = 20,
            bmc_engine = "abc:pdr",   # colon-encoded; main() would decode this
            prove = False,
            prove_engine = "smtbmc",
            prove_depth = None,
            multiclock = False,
            no_flatten = False,
            top = "top",
            define = [],
            properties = "props.sv",
            rtl_metadata = None,
            rtl_files = ["rtl.sv"],
        )

        sby = run_sby.generate_sby(args)

        # Bug demonstrated: the engine string is emitted verbatim with a colon.
        # A valid .sby engine line requires "abc pdr" not "abc:pdr".
        self.assertIn(
            "abc:pdr",
            sby,
            "Bug: generate_sby() emits the colon form 'abc:pdr' verbatim, "
            "which is invalid .sby syntax — the decoding in main() is skipped",
        )
        # The space-separated (valid) form is absent when generate_sby is
        # called directly without the main() decoding step.
        self.assertNotIn(
            "abc pdr",
            sby,
            "Bug: 'abc pdr' (valid .sby form) is absent; "
            "generate_sby() has no built-in colon→space decoding",
        )


if __name__ == "__main__":
    unittest.main()
