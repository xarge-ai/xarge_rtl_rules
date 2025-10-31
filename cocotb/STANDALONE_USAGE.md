# Using CocoTB Rules as a Standalone Repository

This document shows how to use the `rules/cocotb` directory as a standalone Bazel rules repository.

## Project Structure

The standalone repository follows industry-standard Bazel rules patterns:

```
rules_cocotb/                    (standalone repository root)
├── MODULE.bazel                 (or WORKSPACE)
├── BUILD.bazel                  (root package)
├── cocotb/                      (main package)
│   ├── defs.bzl                 (public API)
│   ├── BUILD.bazel              (package definition)
│   ├── README.md                (documentation)
│   ├── private/                 (implementation)
│   │   ├── pipeline.bzl         (core rules)
│   │   ├── legacy.bzl           (backward compatibility)
│   │   └── BUILD.bazel          (private package)
│   ├── tools/                   (executables)
│   │   ├── cocotb_driver.py     (main runner)
│   │   ├── cocotb_wrapper.py    (legacy wrapper)
│   │   └── BUILD.bazel          (tools package)
│   └── examples/                (usage examples)
│       ├── BUILD.bazel          (example targets)
│       └── test_*.py            (test files)
└── third_party/                 (dependencies if needed)
```

## Setting Up the Standalone Repository

### Step 1: Extract the Rules

Copy the `rules/cocotb` directory to a new repository:

```bash
# Create new repo
mkdir rules_cocotb
cd rules_cocotb

# Copy the rules directory
cp -r /path/to/original/repo/rules/cocotb ./

# Rename to follow convention (cocotb becomes the main package)
mv cocotb/* .
rmdir cocotb
```

### Step 2: Create Root Files

**MODULE.bazel** (for Bzlmod):
```starlark
module(
    name = "rules_cocotb",
    version = "1.0.0",
    compatibility_level = 1,
)

# Dependencies
bazel_dep(name = "rules_python", version = "0.35.0")
bazel_dep(name = "bazel_skylib", version = "1.7.1")

# Python toolchain and dependencies
python = use_extension("@rules_python//python/extensions:python.bzl", "python")
python.toolchain(python_version = "3.11")

pip = use_extension("@rules_python//python/extensions:pip.bzl", "pip")
pip.parse(
    hub_name = "py_deps",
    python_version = "3.11",
    requirements_lock = "//third_party/python:requirements.txt",
)
use_repo(pip, "py_deps")
```

**WORKSPACE** (legacy, if needed):
```starlark
workspace(name = "rules_cocotb")

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

# rules_python
http_archive(
    name = "rules_python",
    url = "https://github.com/bazelbuild/rules_python/releases/download/0.35.0/rules_python-0.35.0.tar.gz",
    sha256 = "...",
)

load("@rules_python//python:repositories.bzl", "py_repositories", "python_register_toolchains")
py_repositories()
python_register_toolchains(python_version = "3.11")

# Python dependencies
load("@rules_python//python:pip.bzl", "pip_parse")
pip_parse(
    name = "py_deps",
    requirements_lock = "//third_party/python:requirements.txt",
)
load("@py_deps//:requirements.bzl", "install_deps")
install_deps()
```

**BUILD.bazel** (root):
```starlark
# Root package for rules_cocotb

filegroup(
    name = "distribution",
    srcs = glob([
        "**/*.bzl",
        "**/BUILD.bazel",
        "**/*.py",
        "**/*.md",
    ]),
    visibility = ["//visibility:public"],
)

exports_files([
    "MODULE.bazel",
    "WORKSPACE",
])
```

## Using in Other Projects

### Option 1: Bzlmod (Recommended)

In your project's **MODULE.bazel**:
```starlark
# Add the rules repository
bazel_dep(name = "rules_cocotb", version = "1.0.0")

# Or use git_override for development
git_override(
    module_name = "rules_cocotb", 
    remote = "https://github.com/your-org/rules_cocotb.git",
    commit = "...",
)
```

In your **BUILD.bazel**:
```starlark
load("@rules_cocotb//cocotb:defs.bzl", 
     "cocotb_config", "cocotb_library", "cocotb_test",
     "sim_config", "sim_build", "sim_test")

# Use any naming convention you prefer
cocotb_config(name = "verilator_cfg", simulator = "verilator")
cocotb_library(name = "my_lib", cfg = ":verilator_cfg", ...)
cocotb_test(name = "my_test", build = ":my_lib", ...)
```

### Option 2: Legacy WORKSPACE

In your project's **WORKSPACE**:
```starlark
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")

git_repository(
    name = "rules_cocotb",
    remote = "https://github.com/your-org/rules_cocotb.git",
    tag = "v1.0.0",
)

# Load rules_cocotb dependencies
load("@rules_cocotb//third_party:deps.bzl", "rules_cocotb_dependencies")
rules_cocotb_dependencies()
```

## API Compatibility

The standalone repository provides multiple naming conventions:

### Primary API (Industry Standard)
```starlark
load("@rules_cocotb//cocotb:defs.bzl", 
     "cocotb_config", "cocotb_library", "cocotb_test")
```

### Simulation-Focused Aliases
```starlark
load("@rules_cocotb//cocotb:defs.bzl", 
     "sim_config", "sim_build", "sim_test")
```

### Hardware/RTL Aliases
```starlark
load("@rules_cocotb//cocotb:defs.bzl", 
     "hdl_sim_config", "hdl_sim_target", "hdl_testbench")
```

### Legacy Compatibility
```starlark
load("@rules_cocotb//cocotb:defs.bzl", "cocotb_build_test")
```

## Migration Guide

### From Internal Rules to Standalone

1. **Update Load Statements**:
   ```starlark
   # Before (internal)
   load("//rules/cocotb:defs.bzl", "cocotb_test")
   
   # After (standalone)
   load("@rules_cocotb//cocotb:defs.bzl", "cocotb_test")
   ```

2. **Choose Your Preferred API**:
   - Keep using `cocotb_test` (primary)
   - Switch to `sim_test` (simulation-focused)
   - Switch to `hdl_testbench` (hardware-focused)

3. **Update Dependencies**:
   - Add `rules_cocotb` to MODULE.bazel or WORKSPACE
   - Remove internal rules directories

### Extending for Other Rule Types

The repository structure supports expansion:

```starlark
# Future additions
load("@rules_cocotb//uvm:defs.bzl", "uvm_testbench")
load("@rules_cocotb//synthesis:defs.bzl", "fpga_build")
load("@rules_cocotb//formal:defs.bzl", "formal_verify")
```

## Release Process

1. **Tag releases** following semantic versioning
2. **Publish to BCR** (Bazel Central Registry) for Bzlmod
3. **Update documentation** with each release
4. **Maintain backward compatibility** in public APIs

## Example Projects

See the `examples/` directory for complete usage demonstrations of all API variants.