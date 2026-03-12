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

"""Python-based SymbiYosys formal verification runner for Bazel.

Handles path resolution for Bazel sandbox environments where the .sby
file's [files] section uses relative paths (e.g. ../../rtl/...).
"""

import os
import shutil
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <module.sby>", file=sys.stderr)
        sys.exit(2)

    sby_file = sys.argv[1]

    sby_path = shutil.which("sby")
    if sby_path is None:
        print(f"SKIP: SymbiYosys (sby) not found; skipping formal run for {sby_file}")
        sys.exit(0)

    # Resolve absolute path before changing directory.
    sby_abs = os.path.abspath(sby_file)
    sby_dir = os.path.dirname(sby_abs)

    if not os.path.isfile(sby_abs):
        print(f"ERROR: SBY file not found: {sby_abs}", file=sys.stderr)
        sys.exit(1)

    print(f"Running formal: {sby_file}")

    # Change to the .sby file's directory so that relative [files]
    # paths (e.g. ../../rtl/...) resolve correctly.
    os.chdir(sby_dir)

    result = subprocess.run(
        [sby_path, "-f", sby_abs],
        env=os.environ,
    )
    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
