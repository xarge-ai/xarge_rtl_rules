#!/usr/bin/env python3

"""Runs Corsair either from csrconfig inputs or via a user-authored Python workflow."""

import argparse
import importlib.util
import os
import shutil
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Iterable, List, Set, Tuple

import corsair


class RunnerError(RuntimeError):
    """Raised when the Bazel-facing Corsair contract is violated."""


def _split_assignment(raw: str, option: str) -> Tuple[str, str]:
    if "=" not in raw:
        raise RunnerError(f"{option} expects NAME=PATH, got {raw!r}")
    return raw.split("=", 1)


def _coerce_globcfg_value(raw: str):
    try:
        return corsair.utils.str2int(raw)
    except ValueError:
        return raw


def _load_module(script_path: Path):
    spec = importlib.util.spec_from_file_location("xarge_rtl_rules_corsair_user_script", script_path)
    if spec is None or spec.loader is None:
        raise RunnerError(f"Failed to load workflow script {script_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _add_sys_path(path: Path, seen: Set[str]) -> None:
    resolved = str(path.resolve())
    if resolved not in seen:
        sys.path.insert(0, resolved)
        seen.add(resolved)


@contextmanager
def _pushd(path: Path):
    oldpwd = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(oldpwd)


def _is_under(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
        return True
    except ValueError:
        return False


def _iter_generated_paths(
    source_root: Path,
    *,
    want_directory: bool,
    excluded_roots: Iterable[Path],
) -> Iterable[Path]:
    for path in source_root.rglob("*"):
        if any(_is_under(path, root) for root in excluded_roots):
            continue
        if want_directory and path.is_dir():
            yield path
        elif not want_directory and path.is_file():
            yield path


def _format_available(paths: Iterable[Path], source_root: Path) -> str:
    available = sorted(path.relative_to(source_root).as_posix() for path in paths)
    if not available:
        return "(none)"
    if len(available) > 20:
        shown = ", ".join(available[:20])
        return f"{shown}, ... ({len(available)} total)"
    return ", ".join(available)


def _resolve_generated_path(
    name: str,
    *,
    source_root: Path,
    want_directory: bool,
    excluded_roots: Iterable[Path],
) -> Path:
    kind = "directory" if want_directory else "file"
    exact = source_root / name

    if exact.exists() and not any(_is_under(exact, root) for root in excluded_roots):
        if want_directory and exact.is_dir():
            return exact
        if not want_directory and exact.is_file():
            return exact
        expected = "directory" if want_directory else "file"
        actual = "directory" if exact.is_dir() else "file"
        raise RunnerError(
            f"Declared {kind} output {name!r} matched {exact}, but it is a {actual}; expected a {expected}."
        )

    candidates = list(
        _iter_generated_paths(
            source_root,
            want_directory=want_directory,
            excluded_roots=excluded_roots,
        )
    )
    basename = Path(name).name
    matches = [path for path in candidates if path.name == basename]
    if not matches:
        available = _format_available(candidates, source_root)
        raise RunnerError(f"No generated {kind} matched {name!r}. Available {kind}s: {available}")
    if len(matches) > 1:
        joined = ", ".join(sorted(path.relative_to(source_root).as_posix() for path in matches))
        raise RunnerError(f"Multiple generated {kind}s matched {name!r}: {joined}")
    return matches[0]


def _copy_declared_outputs(
    *,
    source_root: Path,
    outputs: Dict[str, Path],
    output_dirs: Dict[str, Path],
    excluded_roots: Iterable[Path],
) -> None:
    excluded_roots = tuple(excluded_roots)

    for name, dst in outputs.items():
        src = _resolve_generated_path(
            name,
            source_root=source_root,
            want_directory=False,
            excluded_roots=excluded_roots,
        )
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    for name, dst in output_dirs.items():
        src = _resolve_generated_path(
            name,
            source_root=source_root,
            want_directory=True,
            excluded_roots=excluded_roots,
        )
        dst.mkdir(parents=True, exist_ok=True)
        shutil.copytree(src, dst, dirs_exist_ok=True)


def _copy_input(src: Path, dst_dir: Path) -> Path:
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return dst


def _resolve_generator(target_name: str, generator_name: str, *, allow_custom: bool):
    if ".py::" in generator_name:
        if not allow_custom:
            raise RunnerError(
                "csrconfig target {!r} uses custom generator {!r}. "
                "Use corsair_workflow for custom Python generators.".format(
                    target_name,
                    generator_name,
                )
            )

        custom_module_path, custom_generator_name = generator_name.split("::", 1)
        custom_module_name = Path(custom_module_path).stem
        spec = importlib.util.spec_from_file_location(custom_module_name, custom_module_path)
        if spec is None or spec.loader is None:
            raise RunnerError(
                f"Failed to load custom generator module {custom_module_path!r} for target {target_name!r}"
            )
        custom_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(custom_module)
        try:
            return getattr(custom_module, custom_generator_name)
        except AttributeError as exc:
            raise RunnerError(
                "Generator {!r} from module {!r} does not exist for target {!r}".format(
                    custom_generator_name,
                    custom_module_path,
                    target_name,
                )
            ) from exc

    try:
        return getattr(corsair.generators, generator_name)
    except AttributeError as exc:
        raise RunnerError(f"Generator {generator_name!r} does not exist for target {target_name!r}") from exc


def _validate_simple_target_paths(target_name: str, target: Dict[str, str]) -> None:
    path = target.get("path")
    if path and Path(path).is_absolute():
        raise RunnerError(
            "csrconfig target {!r} uses absolute path {!r}. "
            "Use relative paths with corsair_generate or switch to corsair_workflow.".format(
                target_name,
                path,
            )
        )

    image_dir = target.get("image_dir")
    if image_dir and Path(image_dir).is_absolute():
        raise RunnerError(
            "csrconfig target {!r} uses absolute image_dir {!r}. "
            "Use relative paths with corsair_generate or switch to corsair_workflow.".format(
                target_name,
                image_dir,
            )
        )


def _run_targets(targets: Dict[str, Dict[str, str]], rmap, *, allow_custom_generators: bool) -> None:
    if not targets:
        raise RunnerError("No targets were specified! Nothing to do!")

    for target_name, target in targets.items():
        generator_name = target.get("generator")
        if not generator_name:
            raise RunnerError(f"Target {target_name!r} did not declare a generator.")

        generator_cls = _resolve_generator(
            target_name,
            generator_name,
            allow_custom=allow_custom_generators,
        )
        try:
            generator_cls(rmap, **dict(target)).generate()
        except (AssertionError, OSError, ValueError) as exc:
            raise RunnerError(f"Failed to generate target {target_name!r}: {exc}") from exc


class CorsairContext:
    """Context object passed to the user workflow entrypoint."""

    def __init__(
        self,
        *,
        script_path: Path,
        args: List[str],
        data_files: List[Path],
        outputs: Dict[str, Path],
        output_dirs: Dict[str, Path],
        globcfg: Dict[str, str],
        tmpdir: Path,
    ) -> None:
        self.script_path = script_path
        self.args = tuple(args)
        self.data_files = tuple(data_files)
        self.outputs = dict(outputs)
        self.output_dirs = dict(output_dirs)
        self.tmpdir = tmpdir

        merged_globcfg = corsair.config.default_globcfg()
        for key, value in globcfg.items():
            merged_globcfg[key] = _coerce_globcfg_value(value)
        corsair.config.set_globcfg(merged_globcfg)
        self._globcfg = merged_globcfg

    @property
    def globcfg(self) -> Dict[str, Any]:
        return dict(self._globcfg)

    def default_globcfg(self) -> Dict[str, Any]:
        return corsair.config.default_globcfg()

    def set_globcfg(self, **overrides) -> Dict[str, Any]:
        merged = dict(self._globcfg)
        merged.update(overrides)
        corsair.config.set_globcfg(merged)
        self._globcfg = merged
        return dict(self._globcfg)

    def input_path(self, name: str) -> Path:
        if os.path.isabs(name):
            return Path(name)

        matches = []
        for path in self.data_files:
            path_text = str(path)
            if path_text == name or path.name == name or path_text.endswith("/" + name):
                matches.append(path)

        if not matches:
            available = ", ".join(str(path) for path in self.data_files)
            raise RunnerError(f"No data input matched {name!r}. Available inputs: {available}")
        if len(matches) > 1:
            names = ", ".join(str(path) for path in matches)
            raise RunnerError(f"Multiple data inputs matched {name!r}: {names}")
        return matches[0]

    def output_path(self, name: str) -> Path:
        return self._resolve_named_path(name, self.outputs, "file output")

    def output_dir(self, name: str) -> Path:
        return self._resolve_named_path(name, self.output_dirs, "directory output")

    def read_register_map(self, name: str) -> corsair.RegisterMap:
        rmap = corsair.RegisterMap()
        rmap.read_file(str(self.input_path(name)))
        rmap.validate()
        return rmap

    def _resolve_named_path(self, name: str, mapping: Dict[str, Path], kind: str) -> Path:
        if name in mapping:
            return mapping[name]

        matches = [key for key in mapping if key.endswith("/" + name) or Path(key).name == name]
        if not matches:
            available = ", ".join(sorted(mapping))
            raise RunnerError(f"No {kind} matched {name!r}. Available values: {available}")
        if len(matches) > 1:
            joined = ", ".join(sorted(matches))
            raise RunnerError(f"Multiple {kind}s matched {name!r}: {joined}")
        return mapping[matches[0]]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["config", "workflow"], required=True)
    parser.add_argument("--script")
    parser.add_argument("--function", default="generate")
    parser.add_argument("--src", action="append", default=[])
    parser.add_argument("--data", action="append", default=[])
    parser.add_argument("--arg", action="append", default=[])
    parser.add_argument("--import-root", action="append", default=[])
    parser.add_argument("--globcfg", action="append", default=[])
    parser.add_argument("--regmap")
    parser.add_argument("--csrconfig")
    parser.add_argument("--output", action="append", default=[])
    parser.add_argument("--output-dir", action="append", default=[])
    args = parser.parse_args()

    if args.mode == "workflow":
        if not args.script:
            parser.error("--script is required when --mode=workflow")
    elif args.mode == "config":
        if not args.regmap:
            parser.error("--regmap is required when --mode=config")
        if not args.csrconfig:
            parser.error("--csrconfig is required when --mode=config")

    return args


def _validate_outputs(outputs: Dict[str, Path], output_dirs: Dict[str, Path]) -> None:
    missing_files = [name for name, path in outputs.items() if not path.is_file()]
    if missing_files:
        raise RunnerError(
            "Corsair run did not create declared file outputs: {}".format(", ".join(sorted(missing_files)))
        )

    missing_dirs = [name for name, path in output_dirs.items() if not path.is_dir()]
    if missing_dirs:
        raise RunnerError(
            "Corsair run did not create declared directory outputs: {}".format(", ".join(sorted(missing_dirs)))
        )


def _run_workflow_mode(
    args: argparse.Namespace,
    *,
    outputs: Dict[str, Path],
    output_dirs: Dict[str, Path],
    globcfg: Dict[str, str],
) -> None:
    script_path = Path(args.script)
    src_paths = [Path(path) for path in args.src]
    data_files = [Path(path) for path in args.data]

    seen = set()
    _add_sys_path(script_path.parent, seen)
    for src_path in src_paths:
        _add_sys_path(src_path.parent, seen)
    for import_root in args.import_root:
        path = Path(import_root)
        if not path.is_absolute():
            path = script_path.parent / path
        _add_sys_path(path, seen)

    module = _load_module(script_path)
    if not hasattr(module, args.function):
        raise RunnerError(
            f"Workflow script {script_path} does not define the entrypoint {args.function!r}"
        )

    entrypoint = getattr(module, args.function)
    if not callable(entrypoint):
        raise RunnerError(
            f"Workflow entrypoint {args.function!r} in {script_path} is not callable"
        )

    with tempfile.TemporaryDirectory(prefix="corsair_", dir=os.getcwd()) as tmpdir:
        context = CorsairContext(
            script_path=script_path,
            args=args.arg,
            data_files=data_files,
            outputs=outputs,
            output_dirs=output_dirs,
            globcfg=globcfg,
            tmpdir=Path(tmpdir),
        )
        entrypoint(context)


def _run_config_mode(
    args: argparse.Namespace,
    *,
    outputs: Dict[str, Path],
    output_dirs: Dict[str, Path],
) -> None:
    regmap_input = Path(args.regmap)
    csrconfig_input = Path(args.csrconfig)

    with tempfile.TemporaryDirectory(prefix="corsair_", dir=os.getcwd()) as tmpdir_text:
        tmpdir = Path(tmpdir_text)
        inputs_root = tmpdir / "_inputs"
        regmap_path = _copy_input(regmap_input, inputs_root / "regmap")
        csrconfig_path = _copy_input(csrconfig_input, inputs_root / "csrconfig")

        with _pushd(tmpdir):
            try:
                globcfg, targets = corsair.config.read_csrconfig(str(csrconfig_path))
            except (OSError, ValueError) as exc:
                raise RunnerError(f"Failed to read csrconfig {csrconfig_input}: {exc}") from exc

            for target_name, target in targets.items():
                _validate_simple_target_paths(target_name, target)

            globcfg["regmap_path"] = regmap_path.relative_to(tmpdir).as_posix()
            try:
                corsair.config.set_globcfg(globcfg)
            except AssertionError as exc:
                raise RunnerError(f"Invalid Corsair global configuration in {csrconfig_input}: {exc}") from exc

            rmap = corsair.RegisterMap()
            try:
                rmap.read_file(str(regmap_path))
                rmap.validate()
            except (AssertionError, OSError, ValueError) as exc:
                raise RunnerError(f"Failed to read register map {regmap_input}: {exc}") from exc

            _run_targets(targets, rmap, allow_custom_generators=False)

        _copy_declared_outputs(
            source_root=tmpdir,
            outputs=outputs,
            output_dirs=output_dirs,
            excluded_roots=[inputs_root],
        )


def main() -> int:
    args = _parse_args()

    outputs = dict(_split_assignment(item, "--output") for item in args.output)
    output_dirs = dict(_split_assignment(item, "--output-dir") for item in args.output_dir)
    globcfg = dict(_split_assignment(item, "--globcfg") for item in args.globcfg)

    for name, path in list(outputs.items()):
        outputs[name] = Path(path)
    for name, path in list(output_dirs.items()):
        output_dirs[name] = Path(path)
        output_dirs[name].mkdir(parents=True, exist_ok=True)

    if args.mode == "workflow":
        _run_workflow_mode(
            args,
            outputs=outputs,
            output_dirs=output_dirs,
            globcfg=globcfg,
        )
    else:
        _run_config_mode(
            args,
            outputs=outputs,
            output_dirs=output_dirs,
        )

    _validate_outputs(outputs, output_dirs)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RunnerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
