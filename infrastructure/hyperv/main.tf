resource "hyperv_vm" "control_plane" {
  name       = "k8s-cp-01"
  generation = 2

  cpu = {
    count = 2
  }

  memory = {
    startup_bytes = 4 * 1024 * 1024 * 1024
  }

  hard_disk_drive = [
    {
      path                = hyperv_vhd.control_plane.path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    }
  ]
}

resource "hyperv_vhd" "control_plane" {
  path       = "D:/Homelab/virtual-disks/k8s-cp-01.vhdx"
  size_bytes = 40 * 1024 * 1024 * 1024 # 40 GiB
  vhd_type   = "dynamic"
}

resource "hyperv_virtual_switch" "lan" {
  name              = "homelab-external"
  switch_type       = "External"
  net_adapter_names = ["Ethernet"]

  # Keep the Windows host connected to the physical LAN through the switch.
  allow_management_os = true

  # Destroying an external switch can briefly interrupt host networking.
  # Direct console access provides a recovery path if IP migration fails.
  force_management_os_migration = true
}
