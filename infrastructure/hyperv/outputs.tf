output "control_plane_name" {
  description = "Name of the managed control-plane VM."
  value       = hyperv_vm.node["control_plane"].name
}

output "control_plane_state" {
  description = "Power state Hyper-V reported during the latest refresh."
  value       = hyperv_vm.node["control_plane"].state.current
}

output "control_plane_ip_addresses" {
  description = "IP addresses reported by Hyper-V integration services after the guest boots."
  value       = hyperv_vm.node["control_plane"].ip_addresses
}

output "control_plane_disk_path" {
  description = "Writable per-VM VHDX copied from the immutable Packer image."
  value       = hyperv_vhd.node_os["control_plane"].path
}

output "control_plane_seed_iso_path" {
  description = "NoCloud CIDATA ISO used for this VM's first-boot identity."
  value       = hyperv_image_file.node_seed["control_plane"].destination_path
}

output "nodes" {
  description = "Names, current power states, IP addresses, and artifact paths for all managed nodes."
  value = {
    for key, vm in hyperv_vm.node : key => {
      name          = vm.name
      current_state = vm.state.current
      ip_addresses  = vm.ip_addresses
      disk_path     = hyperv_vhd.node_os[key].path
      seed_iso_path = hyperv_image_file.node_seed[key].destination_path
    }
  }
}
