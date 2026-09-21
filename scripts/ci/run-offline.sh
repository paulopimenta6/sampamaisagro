#!/usr/bin/env bash
set -euo pipefail
# Known HTTP calls are mocked by test helpers. strace observes descendants too.
# A successful trace is evidence about this run, not a universal network sandbox.
if [[ $# -lt 2 ]]; then
  echo 'Usage: bash scripts/ci/run-offline.sh NEW_EVIDENCE_DIR COMMAND [ARGS...]' >&2
  exit 2
fi
evidence=$1
shift
if [[ -e "$evidence" ]]; then echo 'Evidence directory already exists' >&2; exit 2; fi
mkdir -p "$evidence"
evidence=$(cd "$evidence" && pwd)
export SAMPA_TEST_OFFLINE=1
export R_PROFILE_USER=/dev/null
export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE
checker=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-network-trace.py
python3 "$checker" --self-test
if command -v strace >/dev/null && strace -o "$evidence/ptrace-probe.log" true; then
  printf '%s\n' 'known-http-mocks + descendant syscall observation; no kernel network isolation claimed' > "$evidence/enforcement.txt"
  set +e
  strace -f -s 512 -e trace=connect,sendto,sendmsg -o "$evidence/network.trace" "$@"
  result=$?
  set -e
  python3 "$checker" "$evidence/network.trace"
  exit "$result"
fi
printf '%s\n' 'LIMITED: known-http-mocks only; syscall observation unavailable; child/library traffic not fully covered' > "$evidence/enforcement.txt"
echo 'Network observation unavailable: running known-HTTP negative tests only. See enforcement.txt.' >&2
"$@"
