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

"""Plan-driven CocoTB backend entrypoint."""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import cocotb_runtime


def _build_parser():
    parser = argparse.ArgumentParser(
        description = "Run the xarge_rtl_rules CocoTB backend.",
    )
    subparsers = parser.add_subparsers(dest = "command")

    build_parser = subparsers.add_parser(
        "build",
        help = "Compile a CocoTB simulator build from a JSON plan.",
    )
    build_parser.add_argument("--plan", required = True, help = "Path to the build plan JSON file.")
    build_parser.add_argument("--build-dir", required = True, help = "Output build directory.")
    build_parser.add_argument("--stamp-out", required = True, help = "Path to the build stamp file.")

    test_parser = subparsers.add_parser(
        "test",
        help = "Run a CocoTB test from a JSON plan.",
    )
    test_parser.add_argument("--plan", required = True, help = "Path to the test plan JSON file.")
    test_parser.add_argument("--build-dir", required = True, help = "Compiled build directory.")
    test_parser.add_argument(
        "--results-xml-out",
        required = True,
        help = "Path to the xUnit XML file written for Bazel.",
    )

    return parser


def main(argv = None):
    args = _build_parser().parse_args(argv)
    if not args.command:
        raise SystemExit("expected one of: build, test")
    if args.command == "build":
        return cocotb_runtime.run_build_plan(
            plan_path = Path(args.plan),
            build_dir = Path(args.build_dir),
            stamp_out = Path(args.stamp_out),
        )
    return cocotb_runtime.run_test_plan(
        plan_path = Path(args.plan),
        build_dir = Path(args.build_dir),
        results_xml_out = Path(args.results_xml_out),
    )


if __name__ == "__main__":
    sys.exit(main())
