variable "ubuntu_base_image_path" {
  description = "Absolute path on the Hyper-V host to the immutable Packer-built Ubuntu VHDX."
  type        = string
  default     = "D:/Homelab/images/ubuntu-24.04.4-base-v3/Virtual Hard Disks/packer-ubuntu-24-04.vhdx"
}

variable "switch_name" {
  description = "Name of the existing host-owned external Hyper-V switch."
  type        = string
  default     = "Kubernetes"
}

variable "control_plane_name" {
  description = "Hyper-V VM name and Ubuntu hostname for the first control-plane node."
  type        = string
  default     = "k8s-cp-01"
}

variable "control_plane_instance_id" {
  description = "NoCloud instance identity. Change it only when deliberately rebuilding first-boot identity."
  type        = string
  default     = "k8s-cp-01-v3"
}

variable "control_plane_disk_path" {
  description = "Terraform-owned writable copy of the base image for the control-plane VM."
  type        = string
  default     = "D:/Homelab/virtual-disks/k8s-cp-01-os.vhdx"
}

variable "control_plane_disk_size_bytes" {
  description = "Logical size of the copied control-plane OS disk in bytes."
  type        = number
  default     = 40 * 1024 * 1024 * 1024
}

variable "control_plane_seed_iso_path" {
  description = "Terraform-managed NoCloud seed ISO attached to the control-plane VM."
  type        = string
  default     = "D:/Homelab/cloud-init/k8s-cp-01-cidata.iso"
}

variable "operator_username" {
  description = "Administrative Ubuntu account cloud-init creates on first boot."
  type        = string
  default     = "ubuntu"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.operator_username))
    error_message = "operator_username must be a valid lowercase Linux username."
  }
}

variable "operator_ssh_public_key_path" {
  description = "Path on the Terraform runner to the operator's SSH public key. The private key stays outside Terraform."
  type        = string
}

variable "vm_desired_state" {
  description = "Desired Hyper-V power state. Override with Off temporarily for hardware changes or safe destruction."
  type        = string
  default     = "Running"

  validation {
    condition     = contains(["Off", "Running"], var.vm_desired_state)
    error_message = "vm_desired_state must be either Off or Running."
  }
}
