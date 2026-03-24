# Copyright 2023 Antmicro
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

"""SymbiYosys runner that generates .sby configuration from CLI arguments.

Called by the sby_test() Bazel macro. Generates a .sby file on-the-fly
from --bmc-depth, --prove, --rtl, --properties etc., then runs sby.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile


def _dedupe_strings(values):
    seen = set()
    result = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        result.append(value)
    return result


def _resolve_input_path(path):
    if os.path.isabs(path):
        return path

    test_srcdir = os.environ.get("TEST_SRCDIR")
    test_workspace = os.environ.get("TEST_WORKSPACE")
    if test_srcdir and test_workspace:
        candidate = os.path.join(test_srcdir, test_workspace, path)
        if os.path.exists(candidate):
            return candidate

    return os.path.abspath(path)


def _load_rtl_metadata(path):
    if not path:
        return [], []
    with open(_resolve_input_path(path), encoding = "utf-8") as stream:
        metadata = json.load(stream)
    return (
        _dedupe_strings(metadata.get("includes", [])),
        _dedupe_strings(metadata.get("defines", [])),
    )


def _read_formal_line(source_path, include_dirs, defines):
    tokens = ["read", "-formal"]
    tokens.extend("-I{}".format(_resolve_input_path(include_dir)) for include_dir in include_dirs)
    tokens.extend("-D{}".format(define) for define in defines)
    tokens.append(_resolve_input_path(source_path))
    return " ".join(tokens)


def generate_sby(args):
    """Generate .sby file content from parsed arguments."""
    top = args.top or os.path.splitext(os.path.basename(args.properties))[0]
    metadata_includes, metadata_defines = _load_rtl_metadata(args.rtl_metadata)
    all_includes = _dedupe_strings(metadata_includes)
    all_defines = _dedupe_strings(metadata_defines + list(args.define or []))

    lines = []

    # [tasks]
    lines.append("[tasks]")
    lines.append("bmc")
    if args.prove:
        lines.append("prove")
    lines.append("")

    # [options]
    lines.append("[options]")
    lines.append("bmc: mode bmc")
    lines.append("bmc: depth {}".format(args.bmc_depth))
    if args.prove:
        lines.append("prove: mode prove")
        if "smtbmc" in args.prove_engine:
            depth = args.prove_depth if args.prove_depth else args.bmc_depth
            lines.append("prove: depth {}".format(depth))
    if args.multiclock:
        lines.append("multiclock on")
    lines.append("")

    # [engines]
    lines.append("[engines]")
    if args.prove and args.bmc_engine == args.prove_engine:
        # Same engine for both tasks — no task qualifier needed
        lines.append(args.bmc_engine)
    else:
        lines.append("bmc: {}".format(args.bmc_engine))
        if args.prove:
            lines.append("prove: {}".format(args.prove_engine))
    lines.append("")

    # [script]
    lines.append("[script]")
    rtl_paths = [_resolve_input_path(rtl) for rtl in args.rtl_files]
    properties_path = _resolve_input_path(args.properties)
    for rtl_path in rtl_paths:
        lines.append(_read_formal_line(rtl_path, all_includes, all_defines))
    lines.append(_read_formal_line(properties_path, all_includes, all_defines))
    flatten = " -flatten" if not args.no_flatten else ""
    lines.append("prep -top {}{}".format(top, flatten))
    lines.append("")

    # [files]
    lines.append("[files]")
    for rtl_path in rtl_paths:
        lines.append(rtl_path)
    lines.append(properties_path)
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description = "SymbiYosys formal verification runner",
    )
    parser.add_argument("--bmc-depth", type = int, default = 20)
    parser.add_argument("--bmc-engine", default = "smtbmc")
    parser.add_argument("--prove", action = "store_true")
    parser.add_argument("--prove-engine", default = "abc pdr")
    parser.add_argument("--prove-depth", type = int, default = None)
    parser.add_argument("--multiclock", action = "store_true")
    parser.add_argument("--no-flatten", action = "store_true")
    parser.add_argument("--top", default = None)
    parser.add_argument("--define", action = "append", default = [])
    parser.add_argument("--properties", required = True)
    parser.add_argument("--rtl-metadata", default = None)
    parser.add_argument("--rtl", action = "append", nargs = "+", default = [], dest = "rtl_files")

    args = parser.parse_args()

    # Flatten list-of-lists produced by --rtl with action="append", nargs="+"
    if args.rtl_files:
        args.rtl_files = [rtl for group in args.rtl_files for rtl in group]
    else:
        args.rtl_files = []

    # Decode colon-separated engine tokens (Bazel shell-tokenizes spaces)
    args.bmc_engine = args.bmc_engine.replace(":", " ")
    args.prove_engine = args.prove_engine.replace(":", " ")

    sby_path = shutil.which("sby")
    if sby_path is None:
        allow_skip = os.environ.get("ALLOW_MISSING_SBY", "").lower() in ("1", "true", "yes")
        if allow_skip:
            print("SKIP: SymbiYosys (sby) not found; skipping formal verification")
            sys.exit(0)
        else:
            print("ERROR: SymbiYosys (sby) not found; cannot run formal verification", file = sys.stderr)
            sys.exit(1)

    sby_content = generate_sby(args)

    # Write .sby into TEST_TMPDIR so sby output stays in the sandbox
    tmpdir = os.environ.get("TEST_TMPDIR", tempfile.gettempdir())
    sby_file = os.path.join(tmpdir, "formal.sby")
    with open(sby_file, "w", encoding = "utf-8") as f:
        f.write(sby_content)

    print("Running formal verification")
    print("Generated .sby configuration:")
    for line in sby_content.splitlines():
        print("  " + line)

    os.chdir(tmpdir)
    result = subprocess.run([sby_path, "-f", sby_file], env = os.environ)
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
