terraform {
  required_providers {
    hyperv = {
      source  = "windsorcli/hyperv"
      version = "0.4.0"
    }
  }
}

provider "hyperv" {
  # Configuration options will be added only if the local Hyper-V host requires them.
}
