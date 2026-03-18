# Third-Party Provenance

Unless a file carries a more specific notice, this repository is licensed under
Apache-2.0. Some files in this repository are derived from third-party work or
carry file-specific notices that should be preserved when redistributed.

## hdl/bazel_rules_hdl

- Source: <https://github.com/hdl/bazel_rules_hdl>
- License: Apache-2.0
- Notes: earlier revisions of the CocoTB package were explored against the
  upstream CocoTB rules while this repo's API was taking shape. In March 2026,
  the public docs, Starlark backend, Python driver, and wrapper were rewritten
  in this repository around the local `cocotb_cfg` / `cocotb_build` /
  `cocotb_test` API. This entry is retained as historical provenance, not as a
  claim that current files are still carrying the earlier source text.

## Antmicro-Header Formal Files

The following files currently carry Antmicro/Apache notices, but their exact
upstream source has not yet been traced during this cleanup pass:

- `formal/BUILD.bazel`
- `formal/defs.bzl`
- `formal/run_sby.py`

Recommendation: keep the current notices intact until the original source is
documented or the implementation is rewritten.
