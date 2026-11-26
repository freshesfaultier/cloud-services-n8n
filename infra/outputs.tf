output "floating_ip" {
  value = module.rke2.external_ip
}

output "ssh" {
  value = "ssh ${local.system_user}@${module.rke2.external_ip}"
}

# Pfad der geholten kubeconfig. Setzen in PowerShell:
#   $env:KUBECONFIG = terraform output -raw kubeconfig
output "kubeconfig" {
  value = "${path.cwd}/${local.cluster_name}.rke2.yaml"
}
