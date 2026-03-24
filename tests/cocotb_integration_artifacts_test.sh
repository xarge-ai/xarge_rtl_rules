#!/usr/bin/env bash
set -euo pipefail

ROOT="${TEST_SRCDIR}/${TEST_WORKSPACE}"

check_target() {
  local target_name="$1"
  local expected_wave="$2"
  local unexpected_wave="${3:-}"
  local results="${ROOT}/tests/${target_name}.results.xml"
  local failed="${ROOT}/tests/${target_name}.failed_tests.txt"
  local artifacts="${ROOT}/tests/${target_name}.artifacts"

  if [[ ! -f "$results" ]]; then
    echo "missing results XML: $results" >&2
    exit 1
  fi

  if [[ ! -f "$failed" ]]; then
    echo "missing failed-tests file: $failed" >&2
    exit 1
  fi

  if [[ ! -d "$artifacts" ]]; then
    echo "missing artifacts dir: $artifacts" >&2
    exit 1
  fi

  local failed_count
  failed_count="$(tr -d '[:space:]' < "$failed")"
  if [[ "$failed_count" != "0" ]]; then
    echo "cocotb integration run reported failures for $target_name: $failed_count" >&2
    cat "$results" >&2 || true
    exit 1
  fi

  if [[ ! -f "$artifacts/$expected_wave" ]]; then
    echo "missing expected waveform $expected_wave in $artifacts" >&2
    find "$artifacts" -maxdepth 4 -type f | sort >&2 || true
    exit 1
  fi

  if [[ -n "$unexpected_wave" && -f "$artifacts/$unexpected_wave" ]]; then
    echo "unexpected waveform $unexpected_wave found in $artifacts" >&2
    find "$artifacts" -maxdepth 4 -type f | sort >&2 || true
    exit 1
  fi
}

check_target "cocotb_integration_artifacts" "dump.vcd"
check_target "cocotb_integration_custom_artifacts" "waves/custom.vcd" "dump.vcd"
