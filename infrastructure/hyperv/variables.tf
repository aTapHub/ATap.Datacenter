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

variable "nodes" {
  description = "Explicit definitions for the Ubuntu nodes managed by this stack."
  type = map(object({
    name            = string
    instance_id     = string
    disk_path       = string
    disk_size_bytes = number
    memory_bytes    = number
    seed_iso_path   = string
  }))

  default = {
    control_plane = {
      name            = "k8s-cp-01"
      instance_id     = "k8s-cp-01-v3"
      disk_path       = "D:/Homelab/virtual-disks/k8s-cp-01-os.vhdx"
      disk_size_bytes = 40 * 1024 * 1024 * 1024
      memory_bytes    = 4 * 1024 * 1024 * 1024
      seed_iso_path   = "D:/Homelab/cloud-init/k8s-cp-01-cidata.iso"
    }

    worker_01 = {
      name            = "k8s-worker-01"
      instance_id     = "k8s-worker-01-v3"
      disk_path       = "D:/Homelab/virtual-disks/k8s-worker-01-os.vhdx"
      disk_size_bytes = 50 * 1024 * 1024 * 1024
      memory_bytes    = 6 * 1024 * 1024 * 1024
      seed_iso_path   = "D:/Homelab/cloud-init/k8s-worker-01-cidata.iso"
    }

    worker_02 = {
      name            = "k8s-worker-02"
      instance_id     = "k8s-worker-02-v3"
      disk_path       = "D:/Homelab/virtual-disks/k8s-worker-02-os.vhdx"
      disk_size_bytes = 50 * 1024 * 1024 * 1024
      memory_bytes    = 6 * 1024 * 1024 * 1024
      seed_iso_path   = "D:/Homelab/cloud-init/k8s-worker-02-cidata.iso"
    }
  }
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

variable "node_desired_states" {
  description = "Optional per-node power-state overrides, used to keep a newly created node off before first boot."
  type        = map(string)
  default     = {}

  validation {
    condition = (
      length(setsubtract(toset(keys(var.node_desired_states)), toset(keys(var.nodes)))) == 0 &&
      alltrue([for state in values(var.node_desired_states) : contains(["Off", "Running"], state)])
    )
    error_message = "node_desired_states may contain only declared node keys with values Off or Running."
  }
}

variable "vm_desired_state" {
  description = "Default desired power state for nodes without a node_desired_states override."
  type        = string
  default     = "Running"

  validation {
    condition     = contains(["Off", "Running"], var.vm_desired_state)
    error_message = "vm_desired_state must be either Off or Running."
  }
}
