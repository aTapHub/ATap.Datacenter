#!/usr/bin/env bash
set -euo pipefail

source /etc/os-release

if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != "24.04" ]]; then
  echo "Expected Ubuntu 24.04, found ${PRETTY_NAME:-unknown}." >&2
  exit 1
fi

if systemctl is-enabled --quiet ssh.socket; then
  systemctl is-active --quiet ssh.socket
  echo "SSH is available through systemd socket activation."
elif systemctl is-enabled --quiet ssh.service; then
  systemctl is-active --quiet ssh.service
  echo "SSH is available through an enabled systemd service."
else
  echo "Neither ssh.socket nor ssh.service is enabled." >&2
  exit 1
fi

sudo /usr/sbin/sshd -t
command -v cloud-init >/dev/null
cloud-init status --wait

test -x /usr/sbin/hv_kvp_daemon
test "$(findmnt --noheadings --output FSTYPE /)" = "ext4"

echo "Ubuntu image validation passed."
