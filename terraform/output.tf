output "kubeconfig" {
  value     = data.selectel_mks_kubeconfig_v1.kubeconfig.raw_config
  sensitive = true
}

output "sfs_address" {
  description = "SFS path"
  value       = module.sfs.sfs_address
}
