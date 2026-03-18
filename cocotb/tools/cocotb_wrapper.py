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

"""Legacy single-step CocoTB wrapper."""

import argparse
import sys

import cocotb_runtime


class _ParseDict(argparse.Action):
    def __call__(self, parser, namespace, values, option_string = None):
        parsed = {}
        for value in values:
            key, item = value.split("=", 1)
            parsed[key] = item
        setattr(namespace, self.dest, parsed)


def _parser():
    parser = argparse.ArgumentParser(
        description = "Run a one-shot CocoTB build and test from Bazel-compatible arguments.",
    )
    parser.add_argument("--sim", default = "icarus", help = "Simulator name.")
    parser.add_argument("--hdl_library", default = "top", help = "HDL library to compile into.")
    parser.add_argument("--verilog_sources", nargs = "*", default = [], help = "Verilog source files.")
    parser.add_argument("--vhdl_sources", nargs = "*", default = [], help = "VHDL source files.")
    parser.add_argument("--sources", nargs = "*", default = [], help = "Language-agnostic source files.")
    parser.add_argument("--includes", nargs = "*", default = [], help = "Include directories.")
    parser.add_argument("--defines", nargs = "*", default = {}, action = _ParseDict, help = "Defines as KEY=VALUE pairs.")
    parser.add_argument(
        "--parameters",
        nargs = "*",
        default = {},
        action = _ParseDict,
        help = "Parameters or generics as KEY=VALUE pairs.",
    )
    parser.add_argument("--build_args", nargs = "*", default = [], help = "Extra build arguments.")
    parser.add_argument("--hdl_toplevel", required = True, help = "HDL toplevel name.")
    parser.add_argument("--always", action = "store_true", help = "Always rerun the build step.")
    parser.add_argument("--build_dir", default = "sim_build", help = "Simulator build directory.")
    parser.add_argument("--clean", action = "store_true", help = "Clean the build directory first.")
    parser.add_argument("--verbose", action = "store_true", help = "Enable verbose output.")
    parser.add_argument("--timescale", nargs = 2, default = None, help = "Timescale unit and precision.")
    parser.add_argument("--waves", action = "store_true", help = "Enable waveform capture.")
    parser.add_argument("--log_file", default = None, help = "Optional build or runtime log file.")
    parser.add_argument("--test_module", nargs = "*", default = [], help = "Python test module file paths.")
    parser.add_argument("--hdl_toplevel_library", default = None, help = "Override HDL toplevel library.")
    parser.add_argument("--hdl_toplevel_lang", default = "verilog", help = "HDL toplevel language.")
    parser.add_argument("--gpi_interfaces", nargs = "*", default = [], help = "GPI interfaces to enable.")
    parser.add_argument("--testcase", nargs = "*", default = [], help = "Specific testcase names to run.")
    parser.add_argument("--seed", default = None, help = "Random seed for the test run.")
    parser.add_argument("--elab_args", nargs = "*", default = [], help = "Extra elaboration arguments.")
    parser.add_argument("--test_args", nargs = "*", default = [], help = "Extra simulator runtime arguments.")
    parser.add_argument("--plusargs", nargs = "*", default = [], help = "Simulator plusargs.")
    parser.add_argument("--extra_env", nargs = "*", default = [], help = "Extra environment variables as KEY=VALUE.")
    parser.add_argument("--gui", action = "store_true", help = "Run with GUI mode enabled.")
    parser.add_argument("--test_dir", default = None, help = "Deprecated and ignored.")
    parser.add_argument("--results_xml", default = "results.xml", help = "xUnit XML output path.")
    parser.add_argument("--pre_cmd", nargs = "*", default = [], help = "Commands run before simulation.")
    parser.add_argument("--test_filter", default = None, help = "Regex used to select tests.")
    return parser


def main(argv = None):
    args = _parser().parse_args(argv)
    return cocotb_runtime.run_legacy_one_shot(args)


if __name__ == "__main__":
    sys.exit(main())
