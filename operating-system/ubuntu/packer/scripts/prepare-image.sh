#!/usr/bin/env bash
set -euo pipefail

build_user="${1:?The temporary Packer build username is required.}"

if ! id "${build_user}" >/dev/null 2>&1; then
  echo "Build user ${build_user} does not exist." >&2
  exit 1
fi

# Remove the key and privilege path Packer used. The locked account remains as
# an audit marker but cannot authenticate or start an interactive shell.
rm -rf "/home/${build_user}/.ssh"
passwd --lock "${build_user}"
usermod --shell /usr/sbin/nologin "${build_user}"
rm -f /etc/sudoers.d/90-cloud-init-users
gpasswd --delete "${build_user}" sudo >/dev/null 2>&1 || true
gpasswd --delete "${build_user}" adm >/dev/null 2>&1 || true

# Make clones initialize as new machines. cloud-init will rerun, systemd will
# generate a new machine ID, and OpenSSH/cloud-init will generate new host keys.
rm -f /etc/ssh/ssh_host_*

# Subiquity persists the installer datasource and its temporary Packer user in
# this file. If retained, clones select DataSourceNone instead of their CIDATA
# media and recreate cloud-init.disabled during first boot.
rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg
cloud-init clean --logs --seed --machine-id
rm -f /etc/cloud/cloud-init.disabled

# Remove transient identifiers and package/download residue from the artifact.
rm -f /var/lib/systemd/random-seed
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

sync

# Keep the SSH command attached until systemd begins the power-off transaction.
# Packer treats the resulting SSH disconnect as expected and waits for Hyper-V
# to report that the VM reached the Off state.
systemctl poweroff
