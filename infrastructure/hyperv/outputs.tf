output "hyperv_host_name" {
  description = "The name of the Hyper-V host."
  value       = data.hyperv_host.current.computer_name
}

output "hyperv_default_vm_path" {
  description = "The host's default path for virtual machine configuration files."
  value       = data.hyperv_host.current.virtual_machine_path
}

output "hyperv_default_vhd_path" {
  description = "The host's default path for virtual hard disks."
  value       = data.hyperv_host.current.virtual_hard_disk_path
}
