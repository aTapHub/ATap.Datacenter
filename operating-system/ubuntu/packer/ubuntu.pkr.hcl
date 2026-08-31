packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "= 1.1.5"
    }
  }
}

source "hyperv-iso" "ubuntu" {
  vm_name = "packer-ubuntu-24-04"

  iso_url      = var.iso_path
  iso_checksum = var.iso_checksum

  generation            = 2
  enable_secure_boot    = true
  secure_boot_template  = "MicrosoftUEFICertificateAuthority"
  cpus                  = 2
  memory                = 4096
  enable_dynamic_memory = false

  disk_size       = 40960
  disk_block_size = 1

  switch_name       = var.switch_name
  first_boot_device = "DVD"

  # The second CD is a NoCloud data source containing Ubuntu's unattended
  # installation answers. Packer creates it locally and attaches it to the VM.
  cd_files = [
    abspath("${path.root}/autoinstall/meta-data"),
  ]
  cd_content = {
    "user-data" = templatefile(abspath("${path.root}/autoinstall/user-data.pkrtpl"), {
      build_username = var.build_username
      ssh_public_key = var.ssh_public_key
    })
  }
  cd_label = "cidata"

  # Enter the GRUB command line and boot the live installer kernel directly.
  # The cidata CD is discovered automatically; the autoinstall flag removes
  # Ubuntu's final confirmation prompt before destructive disk installation.
  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz quiet autoinstall ---<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>",
  ]

  communicator         = "ssh"
  ssh_username         = var.build_username
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "2h"

  guest_additions_mode = "none"
  headless             = var.headless
  temp_path            = var.temp_path
  output_directory     = "${var.output_root}/${var.image_version}"

  # Terraform needs only the VHDX, not an exported Hyper-V VM definition.
  skip_export     = true
  skip_compaction = false
  keep_registered = false

  shutdown_command = "sudo /usr/local/sbin/prepare-image-for-template ${var.build_username}"
  shutdown_timeout = "15m"
}

build {
  name    = "ubuntu-hyperv-base"
  sources = ["source.hyperv-iso.ubuntu"]

  provisioner "shell" {
    script = abspath("${path.root}/scripts/validate-image.sh")
  }

  provisioner "file" {
    source      = abspath("${path.root}/scripts/prepare-image.sh")
    destination = "/tmp/prepare-image.sh"
  }

  provisioner "shell" {
    inline = [
      "sudo install -o root -g root -m 0755 /tmp/prepare-image.sh /usr/local/sbin/prepare-image-for-template",
      "rm -f /tmp/prepare-image.sh",
    ]
  }
}
