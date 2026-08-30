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
      switch_name = data.hyperv_virtual_switch.lan.name
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

  boot_order = [
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

data "hyperv_virtual_switch" "lan" {
  # The external switch belongs to the stable Hyper-V host infrastructure.
  # This VM stack uses it without creating, changing, or destroying it.
  name = "Kubernetes"
}
