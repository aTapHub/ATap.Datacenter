data "hyperv_virtual_switch" "lan" {
  # The external switch belongs to the stable Hyper-V host infrastructure.
  # This VM stack uses it without creating, changing, or destroying it.
  name = var.switch_name
}

data "hyperv_iso_volume" "node_seed" {
  for_each = var.nodes

  # NoCloud recognizes an ISO whose volume label is CIDATA and reads these two
  # files during the first boot of a generalized image.
  volume_label = "CIDATA"

  files = {
    "meta-data" = templatefile("${path.module}/../../operating-system/ubuntu/cloud-init/meta-data.tftpl", {
      hostname    = each.value.name
      instance_id = each.value.instance_id
    })

    "user-data" = templatefile("${path.module}/../../operating-system/ubuntu/cloud-init/user-data.tftpl", {
      hostname                = each.value.name
      operator_username       = var.operator_username
      operator_ssh_public_key = trimspace(file(var.operator_ssh_public_key_path))
    })
  }
}

resource "hyperv_image_file" "node_seed" {
  for_each = var.nodes

  destination_path = each.value.seed_iso_path
  content_base64   = data.hyperv_iso_volume.node_seed[each.key].content_base64

  # A seed change may be planned while the ISO is mounted. The provider safely
  # pivots the mounted file during updates and detaches it during destruction.
  replace_while_mounted = true
  force_destroy         = true
}

resource "hyperv_vhd" "node_os" {
  for_each = var.nodes

  # The VM writes only to this standalone copy. The Packer base image remains
  # immutable and can be reused for later nodes.
  path        = each.value.disk_path
  source_path = var.ubuntu_base_image_path
  size_bytes  = each.value.disk_size_bytes
}

resource "hyperv_vm" "node" {
  for_each = var.nodes

  name                 = each.value.name
  generation           = 2
  secure_boot          = true
  secure_boot_template = "MicrosoftUEFICertificateAuthority"

  cpu = {
    count = 2
  }

  memory = {
    startup_bytes = each.value.memory_bytes
  }

  network_adapter = [
    {
      name        = "primary"
      mac_address = each.value.mac_address
      switch_name = data.hyperv_virtual_switch.lan.name
    }
  ]

  hard_disk_drive = [
    {
      path                = hyperv_vhd.node_os[each.key].path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 0
    }
  ]

  dvd_drive = [
    {
      iso_path            = hyperv_image_file.node_seed[each.key].destination_path
      controller_type     = "SCSI"
      controller_number   = 0
      controller_location = 1
    }
  ]

  # The CIDATA ISO is configuration media, not boot media. The VM boots from
  # its cloned OS disk while cloud-init discovers the attached ISO separately.
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

  state = {
    desired       = lookup(var.node_desired_states, each.key, var.vm_desired_state)
    shutdown_mode = "graceful"
  }
}

# Preserve the existing control-plane objects while changing from singular
# resources to keyed node resources.
moved {
  from = data.hyperv_iso_volume.control_plane_seed
  to   = data.hyperv_iso_volume.node_seed["control_plane"]
}

moved {
  from = hyperv_image_file.control_plane_seed
  to   = hyperv_image_file.node_seed["control_plane"]
}

moved {
  from = hyperv_vhd.control_plane_os
  to   = hyperv_vhd.node_os["control_plane"]
}

moved {
  from = hyperv_vm.control_plane
  to   = hyperv_vm.node["control_plane"]
}
