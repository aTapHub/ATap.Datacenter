#!/usr/bin/env bash
set -euo pipefail

source /etc/os-release

if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
  echo "Expected Ubuntu 24.04, found ${PRETTY_NAME:-unknown}." >&2
  exit 1
fi

systemctl is-enabled ssh.service
systemctl is-active ssh.service
command -v cloud-init >/dev/null
cloud-init status --wait

test -x /usr/sbin/hv_kvp_daemon
test "$(findmnt --noheadings --output FSTYPE /)" = "ext4"

echo "Ubuntu image validation passed."
