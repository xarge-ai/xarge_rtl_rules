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

import argparse
import os
from pathlib import Path

from cocotb_tools.runner import get_runner
from cocotb_tools.check_results import get_results


def parse_extra_env(extra_env_list):
    """Parse extra environment variables from list format."""
    env_dict = {}
    for env_var in extra_env_list:
        if '=' in env_var:
            key, value = env_var.split('=', 1)
            env_dict[key] = value
        else:
            # If no value provided, set to empty string
            env_dict[env_var] = ''
    return env_dict


def prepare_sources(verilog_sources, vhdl_sources, sources):
    """Prepare sources list, combining language-specific and generic sources."""
    all_sources = []
    
    # Add generic sources first
    all_sources.extend(sources)
    
    # Add language-specific sources (for backwards compatibility)
    all_sources.extend(verilog_sources)
    all_sources.extend(vhdl_sources)
    
    return all_sources


def cocotb_argument_parser():
    class ParseDict(argparse.Action):
        def __call__(self, parser, namespace, values, option_string=None):
            setattr(namespace, self.dest, dict())
            for value in values:
                key, value = value.split("=")
                getattr(namespace, self.dest)[key] = value

    parser = argparse.ArgumentParser(description="Runs the Cocotb framework from Bazel")

    parser.add_argument("--sim", default="icarus", help="Default simulator")
    
    # Build arguments
    parser.add_argument(
        "--hdl_library", default="top", help="The library name to compile into"
    )
    parser.add_argument(
        "--verilog_sources", nargs="*", default=[], help="Verilog source files to build"
    )
    parser.add_argument(
        "--vhdl_sources", nargs="*", default=[], help="VHDL source files to build"
    )
    parser.add_argument(
        "--sources", nargs="*", default=[], help="Language-agnostic source files to build"
    )
    parser.add_argument(
        "--includes", nargs="*", default=[], help="Verilog include directories"
    )
    parser.add_argument(
        "--defines", nargs="*", default={}, action=ParseDict, help="Defines to set"
    )
    parser.add_argument(
        "--parameters",
        nargs="*",
        default={},
        action=ParseDict,
        help="Verilog parameters or VHDL generics",
    )
    parser.add_argument(
        "--build_args",
        nargs="*",
        default=[],
        help="Extra build arguments for the simulator",
    )
    parser.add_argument(
        "--hdl_toplevel", default=None, help="Name of the HDL toplevel module"
    )
    parser.add_argument(
        "--always",
        default=False,
        action="store_true",
        help="Always run the build step",
    )
    parser.add_argument(
        "--build_dir", default="sim_build", help="Directory to run the build step in"
    )
    parser.add_argument(
        "--clean", default=False, action="store_true", help="Delete build_dir before building"
    )
    parser.add_argument(
        "--verbose", default=False, action="store_true", help="Enable verbose messages"
    )
    parser.add_argument(
        "--timescale", nargs=2, default=None, help="Time unit and time precision for simulation"
    )
    parser.add_argument(
        "--waves", default=False, action="store_true", help="Record signal traces"
    )
    parser.add_argument(
        "--log_file", default=None, help="File to write the build log to"
    )
    
    # Test arguments
    parser.add_argument(
        "--test_module",
        nargs="*",
        default=[],
        help="Name(s) of the Python module(s) containing the tests to run",
    )
    parser.add_argument(
        "--hdl_toplevel_library", help="The library name for HDL toplevel module"
    )
    parser.add_argument(
        "--hdl_toplevel_lang",
        default="verilog",
        help="Language of the HDL toplevel module",
    )
    parser.add_argument(
        "--gpi_interfaces",
        nargs="*",
        default=[],
        help="List of GPI interfaces to use",
    )
    parser.add_argument(
        "--testcase", nargs="*", default=[], help="Name(s) of the testcase(s) to run"
    )
    parser.add_argument(
        "--seed", default=None, help="A specific random seed to use"
    )
    parser.add_argument(
        "--elab_args",
        nargs="*",
        default=[],
        help="Extra elaboration arguments for the simulator",
    )
    parser.add_argument(
        "--test_args",
        nargs="*",
        default=[],
        help="Extra arguments for the simulator",
    )
    parser.add_argument(
        "--plusargs", nargs="*", default=[], help="'plusargs' to set for the simulator"
    )
    parser.add_argument(
        "--extra_env",
        nargs="*",
        default=[],
        help="Extra environment variables to set",
    )
    parser.add_argument(
        "--gui", default=False, action="store_true", help="Run with GUI"
    )
    parser.add_argument(
        "--test_dir", default=None, help="Directory to run the test step in"
    )
    parser.add_argument(
        "--results_xml",
        default="results.xml",
        help="Name of xUnit XML file to store test results in",
    )
    parser.add_argument(
        "--pre_cmd", nargs="*", default=[], help="Commands to run before simulation begins"
    )
    parser.add_argument(
        "--test_filter", default=None, help="Regular expression which matches test names"
    )

    return parser


if __name__ == "__main__":
    parser = cocotb_argument_parser()
    args = parser.parse_args()

    # Parse extra environment variables
    extra_env_dict = parse_extra_env(args.extra_env)

    # Prepare sources for the new API
    all_sources = prepare_sources(args.verilog_sources, args.vhdl_sources, args.sources)

    # Get the runner for the specified simulator
    runner = get_runner(args.sim)

    try:
        # Build step with new API
        build_kwargs = {
            'hdl_library': args.hdl_library,
            'sources': all_sources,  # Use the new sources parameter
            'includes': args.includes,
            'defines': args.defines,
            'parameters': args.parameters,
            'build_args': args.build_args,
            'hdl_toplevel': args.hdl_toplevel,
            'always': args.always,
            'build_dir': args.build_dir,
            'clean': args.clean,
            'verbose': args.verbose,
            'waves': args.waves,
        }
        
        # Add optional parameters if provided
        if args.timescale:
            build_kwargs['timescale'] = tuple(args.timescale)
        if args.log_file:
            build_kwargs['log_file'] = args.log_file

        runner.build(**build_kwargs)

        # Test step with new API
        test_kwargs = {
            'test_module': args.test_module,
            'hdl_toplevel': args.hdl_toplevel,
            'hdl_toplevel_library': args.hdl_toplevel_library or args.hdl_library,
            'hdl_toplevel_lang': args.hdl_toplevel_lang,
            'gpi_interfaces': args.gpi_interfaces,
            'testcase': args.testcase,
            'seed': args.seed,
            'elab_args': args.elab_args,
            'test_args': args.test_args,
            'plusargs': args.plusargs,
            'extra_env': extra_env_dict,
            'waves': args.waves,
            'gui': args.gui,
            'parameters': args.parameters,
            'build_dir': args.build_dir,
            'test_dir': args.test_dir,
            'results_xml': args.results_xml,
            'verbose': args.verbose,
        }
        
        # Add optional parameters if provided
        if args.timescale:
            test_kwargs['timescale'] = tuple(args.timescale)
        if args.log_file:
            test_kwargs['log_file'] = args.log_file
        if args.pre_cmd:
            test_kwargs['pre_cmd'] = args.pre_cmd
        if args.test_filter:
            test_kwargs['test_filter'] = args.test_filter

        # Run the tests and get results file path
        try:
            results_xml_path = runner.test(**test_kwargs)
        except Exception as test_exception:
            # The cocotb runner may raise an exception when Verilator exits with $finish (-11)
            # even though tests passed. Check if results.xml was created with passing tests.
            print(f"Test runner reported exception: {test_exception}")
            # Try to find results.xml in the build directory
            results_xml_path = Path(args.build_dir) / args.results_xml
        
        # Parse results and exit with appropriate code
        try:
            # get_results returns (total_tests, failed_tests)
            # Pass Path object instead of string
            total_tests, failed_tests = get_results(results_xml_path)
            print(f"CocoTB Results: {total_tests} tests run, {failed_tests} failed")
            
            if failed_tests > 0:
                print(f"ERROR: {failed_tests} out of {total_tests} tests failed!")
                exit(1)
            else:
                print(f"SUCCESS: All {total_tests} tests passed!")
                exit(0)
                
        except Exception as e:
            print(f"ERROR: Failed to parse test results: {e}")
            # If we can't parse results, assume failure
            exit(1)
            
    except Exception as e:
        print(f"ERROR: Failed to run cocotb test: {e}")
        exit(1)