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

"""Runtime helpers shared by the CocoTB driver and compatibility wrapper."""

import json
import os
import re
import shutil
import tempfile
import warnings
import xml.etree.ElementTree as ET
from pathlib import Path
from pathlib import PurePosixPath

try:
    from cocotb_tools.runner import get_runner

    _RUNNER_FLAVOR = "cocotb_tools"
    Verilog = None
    VHDL = None
    VerilatorControlFile = None
except ImportError:
    from cocotb.runner import VHDL
    from cocotb.runner import Verilog
    from cocotb.runner import get_runner

    _RUNNER_FLAVOR = "cocotb"
    try:
        from cocotb.runner import VerilatorControlFile
    except ImportError:
        VerilatorControlFile = None


_INT_RE = re.compile(r"^-?\d+$")
_FLOAT_RE = re.compile(r"^-?(?:\d+\.\d*|\.\d+|\d+[eE][-+]?\d+|\d+\.\d*[eE][-+]?\d+)$")


def _load_plan(plan_path):
    with plan_path.open(encoding = "utf-8") as stream:
        return json.load(stream)


def _coerce_scalar(value):
    if not isinstance(value, str):
        return value

    lowered = value.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if _INT_RE.match(value):
        try:
            return int(value)
        except ValueError:
            return value
    if _FLOAT_RE.match(value):
        try:
            return float(value)
        except ValueError:
            return value
    return value


def _coerce_mapping_values(values):
    return {key: _coerce_scalar(value) for key, value in values.items()}


def _timescale_tuple(plan):
    timescale = plan.get("timescale")
    if not timescale:
        return None
    if len(timescale) != 2:
        raise ValueError("timescale must contain exactly two entries")
    return tuple(timescale)


def _resolve_log_path(value, root_dir):
    if not value:
        return None
    path = Path(value)
    if path.is_absolute():
        return str(path)
    return str(root_dir / path)


def _normalize_wave_output(value):
    if not value:
        return None
    if "\\" in value:
        raise ValueError(
            "Invalid wave_output path: {}. Must use forward slashes and not contain '..'.".format(value),
        )
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts:
        raise ValueError(
            "Invalid wave_output path: {}. Must be a relative path and not contain '..'.".format(value),
        )
    return path.as_posix()


def _normalize_wave_format(simulator, value):
    if not value:
        return None
    wave_format = value.lower()
    if simulator.lower() == "verilator" and wave_format not in ("vcd", "fst"):
        raise ValueError(
            "Invalid wave_format {!r} for simulator {!r}. Supported values: vcd, fst.".format(
                value,
                simulator,
            ),
        )
    return wave_format


def _verilator_wave_source_name(wave_format):
    if wave_format == "fst":
        return "dump.fst"
    return "dump.vcd"


def _wave_artifact_request(plan):
    if not plan.get("waves"):
        return None

    simulator = plan["simulator"]
    wave_output = _normalize_wave_output(plan.get("wave_output"))
    wave_format = _normalize_wave_format(simulator, plan.get("wave_format"))

    if simulator.lower() != "verilator":
        if wave_output or wave_format:
            warnings.warn(
                "wave_output and wave_format are only applied for Verilator; ignoring them for simulator {!r}.".format(simulator),
                stacklevel = 2,
            )
        return None

    effective_wave_format = wave_format or "vcd"
    if wave_output:
        if wave_output.endswith(".fst") and effective_wave_format != "fst":
            raise ValueError("wave_output ending in .fst requires wave_format = 'fst'")
        if wave_output.endswith(".vcd") and effective_wave_format == "fst":
            raise ValueError("wave_output ending in .vcd is incompatible with wave_format = 'fst'")
        return _verilator_wave_source_name(effective_wave_format), wave_output

    if wave_format == "fst":
        source_name = _verilator_wave_source_name(wave_format)
        return source_name, source_name

    return None


def _stage_wave_artifact(runtime_dir, artifacts_dir, source_name, artifact_relpath):
    _copy_directory_contents(runtime_dir, artifacts_dir)

    source_path = runtime_dir / source_name
    if not source_path.exists():
        raise FileNotFoundError(
            "cocotb did not produce the requested waveform at {}".format(source_path),
        )

    artifact_path = Path(artifacts_dir) / artifact_relpath
    if artifact_relpath != source_name:
        default_artifact = Path(artifacts_dir) / source_name
        if default_artifact.exists():
            default_artifact.unlink()
        _ensure_parent(artifact_path)
        shutil.copy2(source_path, artifact_path)


def _prepare_runner_sources(plan):
    entries = plan.get("sources", [])
    if _RUNNER_FLAVOR == "cocotb_tools":
        return {"sources": [entry["path"] for entry in entries]}

    typed_sources = []
    for entry in entries:
        kind = entry.get("kind", "verilog")
        path = entry["path"]
        if kind == "auto":
            lowered = path.lower()
            if lowered.endswith(".vlt"):
                kind = "verilator_control"
            elif lowered.endswith(".vhd") or lowered.endswith(".vhdl"):
                kind = "vhdl"
            else:
                kind = "verilog"
        if kind == "vhdl":
            typed_sources.append(VHDL(path))
        elif kind == "verilator_control" and VerilatorControlFile is not None:
            typed_sources.append(VerilatorControlFile(path))
        else:
            typed_sources.append(Verilog(path))
    return {"sources": typed_sources}


def _ensure_parent(path):
    path.parent.mkdir(parents = True, exist_ok = True)


def _write_text(path, content):
    _ensure_parent(path)
    path.write_text(content, encoding = "utf-8")


def _copy_directory_contents(source_dir, dest_dir):
    dest_dir.mkdir(parents = True, exist_ok = True)
    if not source_dir.exists():
        return

    for child in source_dir.iterdir():
        target = dest_dir / child.name
        if child.is_dir():
            shutil.copytree(child, target, dirs_exist_ok = True)
        else:
            _ensure_parent(target)
            shutil.copy2(child, target)


def _find_python_roots(paths):
    roots = {os.getcwd()}
    for path_str in paths:
        path = Path(path_str)
        parts = path.parts
        for marker in ("site-packages", "dist-packages"):
            if marker in parts:
                marker_index = parts.index(marker)
                roots.add(str(Path(*parts[:marker_index + 1])))
                break
        if path.is_dir():
            roots.add(str(path))
        else:
            roots.add(str(path.parent))
    return sorted(roots)


def _extend_env_path(env, key, values):
    ordered = []
    seen = set()
    existing = env.get(key)
    if existing:
        for value in existing.split(os.pathsep):
            if value and value not in seen:
                ordered.append(value)
                seen.add(value)
    for value in values:
        if value and value not in seen:
            ordered.append(value)
            seen.add(value)
    env[key] = os.pathsep.join(ordered)


def _configure_python_environment(env, plan, tests_dir):
    python_paths = [str(tests_dir)]
    python_paths.extend(entry["path"] for entry in plan.get("python_sources", []))
    _extend_env_path(env, "PYTHONPATH", _find_python_roots(python_paths))


def _configure_cocotb_library_path(env):
    import cocotb

    libs_dir = Path(cocotb.__file__).resolve().parent / "libs"
    if libs_dir.exists():
        _extend_env_path(env, "LD_LIBRARY_PATH", [str(libs_dir)])


def _copy_test_modules(entries, tests_dir):
    tests_dir.mkdir(parents = True, exist_ok = True)
    module_names = []
    seen_names = set()
    for entry in entries:
        module_name = entry["module_name"]
        if module_name in seen_names:
            raise ValueError(
                "duplicate cocotb test module basename '{}' is not supported".format(module_name),
            )
        seen_names.add(module_name)
        shutil.copy2(entry["path"], tests_dir / entry["basename"])
        module_names.append(module_name)
    return module_names


def _parse_results_xml(results_xml):
    root = ET.parse(results_xml).getroot()
    queue = [root]
    total_tests = 0
    failed_tests = 0

    while queue:
        node = queue.pop()
        if node.tag == "testsuite":
            tests_attr = node.attrib.get("tests")
            failures_attr = node.attrib.get("failures")
            errors_attr = node.attrib.get("errors")
            if tests_attr is not None:
                total_tests += int(tests_attr)
                failed_tests += int(failures_attr or "0") + int(errors_attr or "0")
                continue
        queue.extend(list(node))

    if total_tests == 0:
        for testcase in root.iter("testcase"):
            total_tests += 1
            if testcase.find("failure") is not None or testcase.find("error") is not None:
                failed_tests += 1
    return total_tests, failed_tests


def _build_kwargs(plan, build_dir):
    simulator = plan["simulator"]
    wave_format = _normalize_wave_format(simulator, plan.get("wave_format"))
    build_args = list(plan.get("build_args", []))

    if bool(plan.get("waves", False)):
        if simulator.lower() == "verilator":
            if wave_format == "fst" and "--trace-fst" not in build_args:
                build_args.append("--trace-fst")
        elif wave_format:
            warnings.warn(
                "wave_format is only applied for Verilator; ignoring it for simulator {!r}.".format(simulator),
                stacklevel = 2,
            )

    kwargs = {
        "hdl_library": plan["hdl_library"],
        "hdl_toplevel": plan["hdl_toplevel"],
        "includes": plan.get("includes", []),
        "defines": _coerce_mapping_values(plan.get("defines", {})),
        "parameters": _coerce_mapping_values(plan.get("parameters", {})),
        "build_args": build_args,
        "always": bool(plan.get("always", False)),
        "build_dir": str(build_dir),
        "clean": bool(plan.get("clean", False)),
        "verbose": bool(plan.get("verbose", False)),
        "waves": bool(plan.get("waves", False)),
    }
    kwargs.update(_prepare_runner_sources(plan))

    timescale = _timescale_tuple(plan)
    if timescale:
        kwargs["timescale"] = timescale

    log_file = _resolve_log_path(plan.get("log_file"), build_dir)
    if log_file:
        kwargs["log_file"] = log_file

    return kwargs


def run_build_plan(plan_path, build_dir, stamp_out):
    plan = _load_plan(plan_path)
    build_dir.mkdir(parents = True, exist_ok = True)
    runner = get_runner(plan["simulator"])
    runner.build(**_build_kwargs(plan, build_dir))
    _write_text(
        stamp_out,
        "built {label} with {simulator}\n".format(
            label = plan.get("label", "<unknown>"),
            simulator = plan["simulator"],
        ),
    )
    return 0


def _test_kwargs(plan, build_dir, test_dir, results_xml):
    kwargs = {
        "build_dir": str(build_dir),
        "test_dir": str(test_dir),
        "results_xml": str(results_xml),
        "hdl_toplevel": plan["hdl_toplevel"],
        "hdl_toplevel_library": plan["hdl_toplevel_library"],
        "hdl_toplevel_lang": plan["hdl_toplevel_lang"],
        "gpi_interfaces": plan.get("gpi_interfaces", []),
        "testcase": plan.get("testcase", []),
        "elab_args": plan.get("elab_args", []),
        "test_args": plan.get("test_args", []),
        "plusargs": plan.get("plusargs", []),
        "extra_env": plan.get("extra_env", {}),
        "waves": bool(plan.get("waves", False)),
        "gui": bool(plan.get("gui", False)),
        "parameters": _coerce_mapping_values(plan.get("parameters", {})),
        "verbose": bool(plan.get("verbose", False)),
    }

    if plan.get("seed"):
        kwargs["seed"] = plan["seed"]
    if plan.get("pre_cmd"):
        kwargs["pre_cmd"] = plan["pre_cmd"]
    if plan.get("test_filter"):
        kwargs["test_filter"] = plan["test_filter"]

    timescale = _timescale_tuple(plan)
    if timescale:
        kwargs["timescale"] = timescale

    log_file = _resolve_log_path(plan.get("log_file"), test_dir)
    if log_file:
        kwargs["log_file"] = log_file

    return kwargs


def run_test_plan(plan_path, build_dir, results_xml_out, failed_tests_out, artifacts_dir_out):
    plan = _load_plan(plan_path)
    wave_request = _wave_artifact_request(plan)
    runtime_root = Path(tempfile.mkdtemp(prefix = "cocotb_test_"))
    runtime_dir = runtime_root / "run"
    runtime_dir.mkdir(parents = True, exist_ok = True)
    results_xml = runtime_root / "results.xml"

    module_names = _copy_test_modules(plan.get("test_modules", []), runtime_dir)
    env = os.environ.copy()
    _configure_python_environment(env, plan, runtime_dir)
    _configure_cocotb_library_path(env)

    kwargs = _test_kwargs(plan, build_dir, runtime_dir, results_xml)
    kwargs["test_module"] = module_names

    previous_env = os.environ.copy()
    os.environ.clear()
    os.environ.update(env)

    runner = get_runner(plan["simulator"])
    runner_exception = None
    returned_results = None
    try:
        candidate = runner.test(**kwargs)
        if candidate:
            returned_results = Path(candidate)
            if not returned_results.is_absolute():
                returned_results = runtime_dir / returned_results
    except Exception as exc:
        runner_exception = exc
    finally:
        os.environ.clear()
        os.environ.update(previous_env)

    final_results = returned_results if returned_results and returned_results.exists() else results_xml
    if not final_results.exists():
        if runner_exception is not None:
            raise runner_exception
        raise FileNotFoundError(f"cocotb did not produce results XML at {final_results}")

    _total_tests, failed_tests = _parse_results_xml(final_results)
    _ensure_parent(results_xml_out)
    shutil.copy2(final_results, results_xml_out)
    _write_text(failed_tests_out, f"{failed_tests}\n")

    if wave_request:
        _stage_wave_artifact(runtime_dir, artifacts_dir_out, *wave_request)
    else:
        _copy_directory_contents(runtime_dir, artifacts_dir_out)

    return 0


def _split_kv_pairs(values):
    result = {}
    for value in values:
        if "=" in value:
            key, raw = value.split("=", 1)
            result[key] = raw
        else:
            result[value] = ""
    return result


def run_legacy_one_shot(args):
    build_dir = Path(args.build_dir)
    one_shot_root = Path(tempfile.mkdtemp(prefix = "cocotb_oneshot_"))
    build_plan = {
        "simulator": args.sim,
        "hdl_library": args.hdl_library,
        "hdl_toplevel": args.hdl_toplevel,
        "sources": (
            [{"kind": "auto", "path": path, "short_path": path, "basename": Path(path).name} for path in args.sources] +
            [{"kind": "verilog", "path": path, "short_path": path, "basename": Path(path).name} for path in args.verilog_sources] +
            [{"kind": "vhdl", "path": path, "short_path": path, "basename": Path(path).name} for path in args.vhdl_sources]
        ),
        "includes": args.includes,
        "defines": args.defines,
        "parameters": args.parameters,
        "build_args": args.build_args,
        "always": args.always,
        "clean": args.clean,
        "verbose": args.verbose,
        "waves": args.waves,
    }
    if args.timescale:
        build_plan["timescale"] = list(args.timescale)
    if args.log_file:
        build_plan["log_file"] = args.log_file
    if args.wave_format:
        build_plan["wave_format"] = args.wave_format

    build_plan_path = one_shot_root / "build.json"
    build_plan_path.write_text(json.dumps(build_plan, indent = 2) + "\n", encoding = "utf-8")
    run_build_plan(build_plan_path, build_dir, one_shot_root / "build.ok")

    test_plan = {
        "simulator": args.sim,
        "hdl_toplevel": args.hdl_toplevel,
        "hdl_toplevel_library": args.hdl_toplevel_library or args.hdl_library,
        "hdl_toplevel_lang": args.hdl_toplevel_lang,
        "gpi_interfaces": args.gpi_interfaces,
        "testcase": args.testcase,
        "elab_args": args.elab_args,
        "test_args": args.test_args,
        "plusargs": args.plusargs,
        "extra_env": _split_kv_pairs(args.extra_env),
        "waves": args.waves,
        "wave_output": getattr(args, "wave_output", None),
        "wave_format": getattr(args, "wave_format", None),
        "gui": args.gui,
        "parameters": args.parameters,
        "verbose": args.verbose,
        "python_sources": [],
        "test_modules": [
            {
                "basename": Path(module).name if module.endswith(".py") else "{}.py".format(module),
                "module_name": Path(module).stem,
                "path": module if module.endswith(".py") else str(Path.cwd() / "{}.py".format(module)),
                "short_path": module,
            }
            for module in args.test_module
        ],
    }
    if args.seed:
        test_plan["seed"] = args.seed
    if args.timescale:
        test_plan["timescale"] = list(args.timescale)
    if args.log_file:
        test_plan["log_file"] = args.log_file
    if args.pre_cmd:
        test_plan["pre_cmd"] = args.pre_cmd
    if args.test_filter:
        test_plan["test_filter"] = args.test_filter

    test_plan_path = one_shot_root / "test.json"
    test_plan_path.write_text(json.dumps(test_plan, indent = 2) + "\n", encoding = "utf-8")
    results_xml = Path(args.results_xml)
    if not results_xml.is_absolute():
        results_xml = Path.cwd() / results_xml
    return run_test_plan(
        test_plan_path,
        build_dir,
        results_xml,
        one_shot_root / "failed_tests.txt",
        one_shot_root / "artifacts",
    )
