variable "iso_path" {
  type        = string
  description = "Absolute path to the Ubuntu Server ISO on the Hyper-V host."
  default     = "D:/Homelab/images/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "iso_checksum" {
  type        = string
  description = "Canonical SHA-256 checksum for the Ubuntu Server ISO."
  default     = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
}

variable "switch_name" {
  type        = string
  description = "Existing external Hyper-V switch used by the temporary build VM."
  default     = "Kubernetes"
}

variable "image_version" {
  type        = string
  description = "Versioned name of the output image directory. Change this rather than overwriting an existing image."
  default     = "ubuntu-24.04.4-base-v1"
}

variable "output_root" {
  type        = string
  description = "Parent directory for versioned Packer image artifacts."
  default     = "D:/Homelab/images"
}

variable "temp_path" {
  type        = string
  description = "Directory for temporary Hyper-V build files; must remain on D:."
  default     = "D:/Homelab/packer-temp"
}

variable "build_username" {
  type        = string
  description = "Temporary account used only while Packer configures and validates the image."
  default     = "packer"
}

variable "ssh_public_key" {
  type        = string
  description = "Public half of the temporary Packer build key."
}

variable "ssh_private_key_file" {
  type        = string
  description = "Absolute path to the private half of the temporary Packer build key; never commit this key."
}

variable "headless" {
  type        = bool
  description = "Run without VMConnect. Keep false for the first build so the automated boot sequence can be observed."
  default     = false
}
