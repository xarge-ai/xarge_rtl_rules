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

"""Bug-proof unit tests for the Verilog packaging tool (packaging/tools/bundle.py).

Each test class documents and demonstrates a specific bug.  Tests PASS when the
bug is present (proving its existence) and require updating when the bug is fixed.
"""

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path


def _load_bundle_module():
    sys.modules.pop("bundle_under_test", None)
    module_path = Path(__file__).resolve().parent / "bundle.py"
    spec = importlib.util.spec_from_file_location("bundle_under_test", module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["bundle_under_test"] = module
    spec.loader.exec_module(module)
    return module


class FilelistDeduplicationBugTests(unittest.TestCase):
    """Tests that prove the missing deduplication bug in create_filelist.

    Bug (Packaging Bug 2): create_filelist writes every entry it receives,
    including duplicates.  create_zip guards against duplicates via a 'seen'
    set, but create_filelist does not.

    This matters because the verilog_filelist Bazel macro builds the --src
    argument list from both 'srcs' AND 'deps' independently.  When the same
    label appears in both lists (or when two labels resolve to the same file),
    the runner receives the file path twice and writes it twice to the .f file.

    A downstream simulator or synthesis tool that reads the .f filelist will
    then see the same file compiled twice, which either produces errors or
    causes subtle compile-order bugs.
    """

    def test_create_filelist_writes_duplicate_when_same_file_passed_twice(self):
        """Bug: create_filelist produces duplicate lines for the same file.

        Simulates the scenario where a label appears in both srcs and deps of
        verilog_filelist, causing the runner to receive --src <file> --src <file>.
        After argparse flattening, args.src = [file, file] and create_filelist
        writes the file path twice.
        """
        bundle = _load_bundle_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            src_file = os.path.join(tmpdir, "my_module.sv")
            Path(src_file).write_text("module my_module; endmodule\n", encoding = "utf-8")

            output_f = os.path.join(tmpdir, "out.f")

            # Simulate: same file passed twice (same label in srcs and deps)
            bundle.create_filelist([src_file, src_file], output_f, relative_to = "")

            lines = [
                line.strip()
                for line in Path(output_f).read_text(encoding = "utf-8").splitlines()
                if line.strip()
            ]

        # Bug demonstrated: the same file appears TWICE in the filelist output.
        # A correct implementation would deduplicate and emit the path only once.
        self.assertEqual(
            2,
            len(lines),
            "Bug: create_filelist has no deduplication — "
            "same file appears %d time(s); expected 2 (bug) not 1 (fixed)" % len(lines),
        )
        self.assertEqual(
            lines[0],
            lines[1],
            "Bug: both duplicate lines should contain the same path",
        )

    def test_create_zip_deduplicates_but_create_filelist_does_not(self):
        """Bug: create_zip and create_filelist are inconsistent in deduplication.

        create_zip uses a 'seen' set to skip duplicate archive names and emits
        a WARNING.  create_filelist has no equivalent guard.  The two functions
        should have consistent behaviour when receiving duplicate inputs.
        """
        bundle = _load_bundle_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            src_file = os.path.join(tmpdir, "rtl.sv")
            Path(src_file).write_text("module rtl; endmodule\n", encoding = "utf-8")

            zip_out = os.path.join(tmpdir, "out.zip")
            filelist_out = os.path.join(tmpdir, "out.f")

            # create_zip deduplicates — file appears only once in the archive
            bundle.create_zip(
                [src_file, src_file],
                zip_out,
                prefix = "",
                strip_prefix = "",
                flatten = True,
            )

            import zipfile
            with zipfile.ZipFile(zip_out) as zf:
                zip_names = zf.namelist()

            # create_filelist does NOT deduplicate — file appears twice
            bundle.create_filelist([src_file, src_file], filelist_out, relative_to = "")
            filelist_lines = [
                l.strip()
                for l in Path(filelist_out).read_text(encoding = "utf-8").splitlines()
                if l.strip()
            ]

        # create_zip correctly deduplicates
        self.assertEqual(
            1,
            len(zip_names),
            "create_zip should deduplicate: expected 1 entry, got %d" % len(zip_names),
        )

        # Bug: create_filelist does NOT deduplicate, producing an inconsistency
        self.assertEqual(
            2,
            len(filelist_lines),
            "Bug: create_filelist should deduplicate like create_zip, "
            "but it writes %d lines instead of 1" % len(filelist_lines),
        )


class FilelistTransitiveDepsBugTests(unittest.TestCase):
    """Tests that prove the missing transitive-deps bug in verilog_filelist.

    Bug (Packaging Bug 3): verilog_filelist generates --src $(locations :dep)
    for each dep.  When :dep is a verilog_library target, $(locations :dep)
    expands to only the files in DefaultInfo.files of that target — i.e., only
    the DIRECT sources of the library, not the transitive sources collected via
    VerilogInfo.transitive_srcs.

    This means a filelist generated from a chain of verilog_library targets
    will be INCOMPLETE: only the top library's direct sources appear, and
    sources from its dependencies are silently omitted.

    This test demonstrates the bug at the bundle.py level by showing that
    collect_files processes only what it receives, with no mechanism to follow
    VerilogInfo links.
    """

    def test_collect_files_only_processes_received_paths(self):
        """Bug: collect_files has no knowledge of VerilogInfo transitive deps.

        The bundle.py tool processes exactly the file paths it receives via
        --src.  It cannot inspect VerilogInfo providers because it runs outside
        of Bazel's analysis phase.

        When verilog_filelist uses $(locations :top_lib), only top_lib's
        DefaultInfo files are expanded — dep chain files are missing.

        This test shows that passing only "top.sv" (simulating the incomplete
        $(locations) expansion) results in a filelist that lacks "leaf.sv"
        (the transitive source).
        """
        bundle = _load_bundle_module()

        with tempfile.TemporaryDirectory() as tmpdir:
            leaf_sv = os.path.join(tmpdir, "leaf.sv")
            top_sv = os.path.join(tmpdir, "top.sv")
            Path(leaf_sv).write_text("module leaf; endmodule\n", encoding = "utf-8")
            Path(top_sv).write_text("module top; endmodule\n", encoding = "utf-8")

            output_f = os.path.join(tmpdir, "out.f")

            # Simulate verilog_filelist with deps=[top_lib] where top_lib has
            # DefaultInfo.files = [top.sv] only (leaf.sv is only in transitive_srcs)
            bundle.create_filelist([top_sv], output_f, relative_to = "")

            filelist_content = Path(output_f).read_text(encoding = "utf-8")

        # top.sv is present (it's in DefaultInfo.files)
        self.assertIn(
            "top.sv",
            filelist_content,
            "top.sv should appear in filelist (it is in DefaultInfo.files)",
        )

        # Bug demonstrated: leaf.sv is absent because it's only in
        # VerilogInfo.transitive_srcs, which $(locations) does not expand.
        self.assertNotIn(
            "leaf.sv",
            filelist_content,
            "Bug: leaf.sv (transitive dep) is absent from filelist — "
            "$(locations) only expands DefaultInfo.files",
        )


if __name__ == "__main__":
    unittest.main()
