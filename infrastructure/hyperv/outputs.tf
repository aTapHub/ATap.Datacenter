output "control_plane_name" {
  description = "Name of the managed control-plane VM."
  value       = hyperv_vm.control_plane.name
}

output "control_plane_state" {
  description = "Power state Hyper-V reported during the latest refresh."
  value       = hyperv_vm.control_plane.state.current
}

output "control_plane_ip_addresses" {
  description = "IP addresses reported by Hyper-V integration services after the guest boots."
  value       = hyperv_vm.control_plane.ip_addresses
}

output "control_plane_disk_path" {
  description = "Writable per-VM VHDX copied from the immutable Packer image."
  value       = hyperv_vhd.control_plane_os.path
}

output "control_plane_seed_iso_path" {
  description = "NoCloud CIDATA ISO used for this VM's first-boot identity."
  value       = hyperv_image_file.control_plane_seed.destination_path
}
