#!/usr/bin/env bash
# Run all build children under the server's shared Dayflow memory budget.
set -euo pipefail

if (( $# == 0 )); then
    echo 'Usage: scripts/run_build.sh COMMAND [ARG ...]' >&2
    exit 2
fi
if [[ ! -f /etc/systemd/system/dayflow-build.slice ]]; then
    echo 'Install scripts/dayflow-build.slice into /etc/systemd/system/ first, then run systemctl daemon-reload.' >&2
    exit 1
fi
if grep -q '/dayflow-build.slice/' /proc/self/cgroup; then
    exec "$@"
fi
exec systemd-run --scope --quiet --collect --slice=dayflow-build.slice "$@"
