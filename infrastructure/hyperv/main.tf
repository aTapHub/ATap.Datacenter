resource "hyperv_vm" "control_plane" {
  name                 = "k8s-cp-01"
  generation           = 2
  secure_boot          = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"

  cpu = {
    count = 2
  }

  memory = {
    startup_bytes = 4 * 1024 * 1024 * 1024
  }

  network_adapter = [
    {
      name        = "primary"
      switch_name = hyperv_virtual_switch.lan.name
    }
  ]

  hard_disk_drive = [
    {
      path                = hyperv_vhd.control_plane.path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    }
  ]

  dvd_drive = [
    {
      iso_path            = "D:/Homelab/images/ubuntu-24.04.4-live-server-amd64.iso"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    }
  ]

  boot_order = [
    {
      type                = "dvd_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    },
    {
      type                = "hard_disk_drive"
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    },
    {
      type = "network_adapter"
      name = "primary"
    }
  ]
}

resource "hyperv_vhd" "control_plane" {
  path       = "D:/Homelab/virtual-disks/k8s-cp-01.vhdx"
  size_bytes = 40 * 1024 * 1024 * 1024 # 40 GiB
  vhd_type   = "dynamic"
}

resource "hyperv_virtual_switch" "lan" {
  name              = "Kubernetes"
  switch_type       = "External"
  net_adapter_names = ["Ethernet"]

  # Keep the Windows host connected to the physical LAN through the switch.
  allow_management_os = true

  # Destroying an external switch can briefly interrupt host networking.
  # Direct console access provides a recovery path if IP migration fails.
  force_management_os_migration = true
}
