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

"""
Cocotb driver tool for pipeline-based build and test separation.

This tool wraps cocotb's Runner API to enable building once and running multiple
tests against the same build output, with proper Bazel caching.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Any, Union, Optional

# Try to import from cocotb 2.0+ first, fallback to cocotb-tools
try:
    from cocotb.runner import get_runner
    from cocotb.runner import Verilog, VHDL
    try:
        from cocotb.runner import VerilatorControlFile
        HAS_VERILATOR_CONTROL = True
    except ImportError:
        HAS_VERILATOR_CONTROL = False
    USE_COCOTB_TOOLS = False
except ImportError:
    try:
        from cocotb_tools.runner import get_runner
        USE_COCOTB_TOOLS = True
        HAS_VERILATOR_CONTROL = False
    except ImportError:
        print("ERROR: Could not import cocotb runner. Please install cocotb >= 2.0 or cocotb-tools")
        sys.exit(1)

# Import check_results for test result parsing
try:
    if USE_COCOTB_TOOLS:
        from cocotb_tools.check_results import get_results
    else:
        from cocotb.tools.check_results import get_results
except ImportError:
    try:
        from cocotb_tools.check_results import get_results
    except ImportError:
        print("ERROR: Could not import check_results. Please ensure cocotb is properly installed")
        sys.exit(1)


def _parse_tagged_sources(sources: List[str]) -> Dict[str, List[str]]:
    """
    Parse tagged sources list into categorized sources.
    
    Supports tags:
    - VERILOG:path/to/file.sv
    - VHDL:path/to/file.vhd  
    - VERILATORCTL:path/to/file.vlt
    - Untagged files (assumed Verilog)
    
    Returns dict with keys: verilog, vhdl, verilator_ctrl
    """
    result = {
        'verilog': [],
        'vhdl': [],
        'verilator_ctrl': []
    }
    
    for src in sources:
        if ':' in src and src.count(':') == 1:
            tag, path = src.split(':', 1)
            tag = tag.upper()
            
            if tag == 'VERILOG':
                result['verilog'].append(path)
            elif tag == 'VHDL':
                result['vhdl'].append(path)
            elif tag == 'VERILATORCTL':
                result['verilator_ctrl'].append(path)
            else:
                # Unknown tag, treat as untagged
                result['verilog'].append(src)
        else:
            # Untagged, assume Verilog
            result['verilog'].append(src)
    
    return result


def _coerce_value(value: Any) -> Any:
    """
    Coerce scalar values to appropriate types (int/float/bool/str).
    
    JSON deserializes everything as strings, but cocotb expects typed values
    for parameters and defines.
    """
    if not isinstance(value, str):
        return value
    
    # Try boolean first
    if value.lower() == 'true':
        return True
    elif value.lower() == 'false':
        return False
    
    # Try integer
    try:
        if '.' not in value:
            return int(value)
    except ValueError:
        pass
    
    # Try float
    try:
        return float(value)
    except ValueError:
        pass
    
    # Return as string
    return value


def _coerce_dict_values(d: Dict[str, Any]) -> Dict[str, Any]:
    """Coerce all values in a dictionary."""
    return {k: _coerce_value(v) for k, v in d.items()}


def _prepare_sources_for_runner(tagged_sources: Dict[str, List[str]], simulator: str):
    """
    Prepare sources in the format expected by cocotb runner.
    
    For cocotb 2.0+: Use Verilog(), VHDL(), VerilatorControlFile() objects
    For cocotb-tools: Use simple file lists
    """
    if USE_COCOTB_TOOLS:
        # cocotb-tools expects simple lists
        return {
            'verilog_sources': tagged_sources['verilog'],
            'vhdl_sources': tagged_sources['vhdl'],
            'sources': []  # Generic sources parameter
        }
    else:
        # cocotb 2.0+ expects typed source objects
        sources = []
        
        # Add Verilog sources
        for src in tagged_sources['verilog']:
            sources.append(Verilog(src))
        
        # Add VHDL sources
        for src in tagged_sources['vhdl']:
            sources.append(VHDL(src))
        
        # Add Verilator control files if supported
        if HAS_VERILATOR_CONTROL and simulator.lower() == 'verilator':
            for src in tagged_sources['verilator_ctrl']:
                sources.append(VerilatorControlFile(src))
        
        return {
            'sources': sources,
            'verilog_sources': [],  # Deprecated in 2.0+
            'vhdl_sources': []      # Deprecated in 2.0+
        }


def _parse_kwargs_file(filepath):
    """
    Parse a kwargs file in key=value format and convert to proper Python dict with JSON parsing.
    """
    import ast
    import json
    
    kwargs = {}
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or '=' not in line:
                continue
            
            key, value = line.split('=', 1)
            key = key.strip()
            
            # Parse the value using ast.literal_eval for safety
            try:
                # Try to parse as Python literal first
                parsed_value = ast.literal_eval(value)
                kwargs[key] = parsed_value
            except (ValueError, SyntaxError):
                # If that fails, check for special string values
                value = value.strip('"')
                if value.lower() == 'true':
                    kwargs[key] = True
                elif value.lower() == 'false':
                    kwargs[key] = False
                else:
                    kwargs[key] = value
    
    return kwargs


def build_mode(args):
    """Execute build mode: run runner.build() and create stamp file."""
    print(f"=== CocoTB Build Mode (simulator: {args.simulator}) ===")
    
    # Load build configuration
    build_kwargs = _parse_kwargs_file(args.build_kwargs_txt)
    
    print(f"Build config: {build_kwargs}")
    print(f"Build config types: {[(k, type(v)) for k, v in build_kwargs.items()]}")
    
    # Parse and prepare sources
    raw_sources = build_kwargs.get('sources', [])
    print(f"Raw sources type: {type(raw_sources)}")
    print(f"Raw sources value: {raw_sources}")
    
    tagged_sources = _parse_tagged_sources(raw_sources)
    print(f"Parsed sources: {tagged_sources}")
    
    source_kwargs = _prepare_sources_for_runner(tagged_sources, args.simulator)
    
    # Coerce parameter and define values
    if 'parameters' in build_kwargs and isinstance(build_kwargs['parameters'], dict):
        build_kwargs['parameters'] = _coerce_dict_values(build_kwargs['parameters'])
    if 'defines' in build_kwargs and isinstance(build_kwargs['defines'], dict):
        build_kwargs['defines'] = _coerce_dict_values(build_kwargs['defines'])
    
    # Update build_kwargs with prepared sources
    build_kwargs.update(source_kwargs)
    
    # Set build directory
    build_kwargs['build_dir'] = args.build_dir
    
    # Remove our custom 'sources' field if using old API
    if USE_COCOTB_TOOLS and 'sources' in build_kwargs:
        del build_kwargs['sources']
    
    # Get runner and execute build
    try:
        runner = get_runner(args.simulator)
        print(f"Using runner: {runner}")
        
        # Ensure build directory exists
        os.makedirs(args.build_dir, exist_ok=True)
        
        print(f"Calling runner.build with: {build_kwargs}")
        runner.build(**build_kwargs)
        
        # Write stamp file to indicate successful build
        with open(args.stamp_out, 'w') as f:
            f.write(f"Build completed successfully for simulator {args.simulator}\n")
        
        print("Build completed successfully!")
        
    except Exception as e:
        print(f"ERROR: Build failed: {e}")
        sys.exit(1)


def test_mode(args):
    """Execute test mode: run runner.test() and check results."""
    import os
    print(f"=== CocoTB Test Mode (simulator: {args.simulator}) ===")
    
    # Load test configuration
    test_kwargs = _parse_kwargs_file(args.test_kwargs_txt)
    
    print(f"Test config: {test_kwargs}")
    
    # Coerce parameter values
    if 'parameters' in test_kwargs:
        test_kwargs['parameters'] = _coerce_dict_values(test_kwargs['parameters'])
    
    # Set up build and test directories
    # Build directory contains the compiled simulation
    test_kwargs['build_dir'] = os.path.abspath(args.build_dir)
    
    # Test directory: if specified, use it; otherwise use build_dir (CocoTB default)
    if args.test_dir:
        test_kwargs['test_dir'] = os.path.abspath(args.test_dir)
    else:
        # Default behavior: test runs from build directory
        test_kwargs['test_dir'] = test_kwargs['build_dir']
    
    # Set results XML file relative to test directory
    test_kwargs['results_xml'] = 'results.xml'
    
    try:
        # Set up library path for cocotb shared libraries
        import cocotb
        cocotb_lib_dir = os.path.join(os.path.dirname(cocotb.__file__), 'libs')
        
        # Add to LD_LIBRARY_PATH for the subprocess
        current_ld_path = os.environ.get('LD_LIBRARY_PATH', '')
        if current_ld_path:
            os.environ['LD_LIBRARY_PATH'] = f"{cocotb_lib_dir}:{current_ld_path}"
        else:
            os.environ['LD_LIBRARY_PATH'] = cocotb_lib_dir
        
        print(f"Set LD_LIBRARY_PATH to include: {cocotb_lib_dir}")
        print(f"Build directory: {test_kwargs['build_dir']}")
        print(f"Test directory: {test_kwargs['test_dir']}")
        
        runner = get_runner(args.simulator)
        print(f"Using runner: {runner}")
        
        print(f"Calling runner.test with: {test_kwargs}")
        
        # Run the test
        try:
            results_xml_path = runner.test(**test_kwargs)
        except Exception as test_exception:
            # The cocotb runner may raise an exception when Verilator exits with $finish (-11)
            # even though tests passed. Check if results.xml was created with passing tests.
            print(f"Test runner reported exception: {test_exception}")
            # Try to find results.xml in the test directory or build directory
            results_xml_path = Path(test_kwargs.get('test_dir', args.build_dir)) / 'results.xml'
            if not results_xml_path.exists():
                results_xml_path = Path(args.build_dir) / 'results.xml'
        
        # Parse results and determine exit code
        try:
            if isinstance(results_xml_path, str):
                results_xml_path = Path(results_xml_path)
            
            total_tests, failed_tests = get_results(results_xml_path)
            print(f"CocoTB Results: {total_tests} tests run, {failed_tests} failed")
            
            # Copy results.xml to output location if specified
            if args.results_xml_out and results_xml_path.exists():
                import shutil
                shutil.copy2(results_xml_path, args.results_xml_out)
                print(f"Results copied to: {args.results_xml_out}")
            
            if failed_tests > 0:
                print(f"ERROR: {failed_tests} out of {total_tests} tests failed!")
                sys.exit(1)
            else:
                print(f"SUCCESS: All {total_tests} tests passed!")
                sys.exit(0)
                
        except Exception as e:
            print(f"ERROR: Failed to parse test results: {e}")
            # If we can't parse results, assume failure
            sys.exit(1)
            
    except Exception as e:
        print(f"ERROR: Test execution failed: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="CocoTB pipeline driver for build/test separation"
    )
    
    parser.add_argument(
        "--mode",
        choices=["build", "test"],
        required=True,
        help="Operation mode: build or test"
    )
    
    parser.add_argument(
        "--simulator",
        default="verilator",
        help="Simulator name (default: verilator)"
    )
    
    parser.add_argument(
        "--build-dir",
        required=True,
        help="Build directory path"
    )
    
    parser.add_argument(
        "--test-dir",
        help="Test directory path (test mode only)"
    )
    
    parser.add_argument(
        "--build-kwargs-txt",
        help="Text file with build kwargs (build mode only)"
    )
    
    parser.add_argument(
        "--test-kwargs-txt", 
        help="Text file with test kwargs (test mode only)"
    )
    
    parser.add_argument(
        "--results-xml-out",
        help="Output path for results.xml (test mode only)"
    )
    
    parser.add_argument(
        "--stamp-out",
        help="Output path for build stamp file (build mode only)"
    )
    
    args = parser.parse_args()
    
    # Validate mode-specific arguments
    if args.mode == "build":
        if not args.build_kwargs_txt:
            parser.error("--build-kwargs-txt is required for build mode")
        if not args.stamp_out:
            parser.error("--stamp-out is required for build mode")
        build_mode(args)
    
    elif args.mode == "test":
        if not args.test_kwargs_txt:
            parser.error("--test-kwargs-txt is required for test mode")
        test_mode(args)


if __name__ == "__main__":
    main()