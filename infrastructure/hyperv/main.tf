resource "hyperv_vm" "control_plane" {
  name       = "k8s-cp-01"
  generation = 2

  cpu = {
    count = 2
  }

  memory = {
    startup_bytes = 4 * 1024 * 1024 * 1024
  }
}
