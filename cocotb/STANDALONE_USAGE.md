# Standalone Usage Note

`cocotb/` is maintained as a package inside `xarge_rtl_rules`, not as a separately published `rules_cocotb` repository.

If you want to extract it into its own repo, treat that as a packaging exercise rather than an officially documented distribution path:

- keep `LICENSE`
- keep `THIRD_PARTY.md`
- update load statements and repository names
- audit `MODULE.bazel`, Python dependencies, and examples for the new repo layout

The supported and documented entrypoint is the in-repo package:

```starlark
load("@xarge_rtl_rules//cocotb:defs.bzl", "cocotb_cfg", "cocotb_build", "cocotb_test")
```
