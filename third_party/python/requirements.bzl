# This file is auto-generated from requirements.txt
# Run bazel run //third_party/python:requirements.update to regenerate

load("@xarge_py_deps//:requirements.bzl", _requirement = "requirement")

def _clean_name(name):
    return name.replace("-", "_").replace(".", "_").replace("/", "_").replace("+", "_").lower()

def requirement(name):
    return _requirement(name)
