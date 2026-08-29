terraform {
  required_providers {
    hyperv = {
      source  = "windsorcli/hyperv"
      version = "0.4.0"
    }
  }
}

provider "hyperv" {
  # Terraform will run directly on the Windows Hyper-V host.
  backend = "local"
}
