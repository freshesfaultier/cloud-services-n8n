output "floating_ip" {
  value = module.rke2.external_ip
}

output "ssh" {
  value = "ssh ${local.system_user}@${module.rke2.external_ip}"
}

# Kein Output für den Pfad der kubeconfig: path.cwd hängt vom Rechner ab, und
# jeder plan auf einem anderen Rechner meldete deshalb eine Änderung. Die Datei
# liegt in infra/n8n.rke2.yaml, siehe README.md.
