###########################################################
#
# RKE2-Kubernetes-Cluster in OpenStack, 1 Controller + Worker
#
# Grundlage ist examples/hs-fulda/main.tf aus
# https://github.com/srieger1/terraform-openstack-rke2 (Branch hsfulda-example).
#
# Hinweis des Beispiels: nicht produktionsreif, u. a. ist die kubeconfig auf
# dem Controller mit 0644 für alle lesbar.
#
###########################################################

locals {
  # Taucht in VM-, Netz-, Router- und Load-Balancer-Namen auf und ist der
  # Kontextname in der kubeconfig
  cluster_name = "n8n"

  # /v3/ ist nötig, sonst landet gophercloud (Basis des OpenStack-Providers)
  # beim Abfragen der Keystone-Version auf einer internen VIP mit einem
  # Zertifikat, dem wir nicht vertrauen
  auth_url = "https://private-cloud.informatik.hs-fulda.de:5000/v3/"

  image_name       = "ubuntu-26.04-resolute-server-cloud-image-amd64"
  system_user      = "ubuntu"
  floating_ip_pool = "ext_net"
  dns_server       = "10.33.16.100"
  rke2_version     = "v1.36.2+rke2r1"

  # Alle öffentlichen Schlüssel aus ssh-keys/. Sie landen per cloud-init auf
  # den Knoten. Ein neuer Schlüssel ersetzt deshalb beim nächsten apply alle VMs.
  ssh_keys = [
    for f in sort(fileset("${path.module}/ssh-keys", "*.pub")) :
    trimspace(file("${path.module}/ssh-keys/${f}"))
  ]
}

module "rke2" {
  # Modul aus dem Repo des Profs, gepinnt auf Commit b652f3e vom Branch
  # hsfulda-example. Ein späterer Push dort ändert unseren Cluster also nicht
  # unbemerkt. terraform init lädt es nach .terraform/modules/.
  #
  # Als Tar-Archiv statt per git::, weil Git für Windows (core.autocrlf=true)
  # beim Klonen alle Zeilenenden auf CRLF umstellt. Die Shell-Skripte des
  # Moduls landen per cloud-init auf den Knoten und scheitern dort mit
  # "/bin/bash^M: bad interpreter". Das Archiv entpackt Terraform ohne Git,
  # die Zeilenenden bleiben LF. Hinter // steht der Ordner im Archiv.
  source = "https://github.com/srieger1/terraform-openstack-rke2/archive/b652f3e0708de2fd4847b8cb622a27bac12f91ce.tar.gz//terraform-openstack-rke2-b652f3e0708de2fd4847b8cb622a27bac12f91ce"

  # true für einen Cluster mit nur einem Server (Controller)
  bootstrap = true
  name      = local.cluster_name

  ssh_authorized_keys = local.ssh_keys

  floating_pool = local.floating_ip_pool
  # Floating IPs sind nur im NetLab und über das VPN erreichbar. Enger wäre
  # eine Beschränkung auf diese Adressbereiche.
  rules_ssh_cidr = ["0.0.0.0/0"]
  rules_k8s_cidr = ["0.0.0.0/0"]

  servers = [{
    name               = "controller"
    flavor_name        = var.flavor_name
    image_name         = local.image_name
    system_user        = local.system_user
    boot_volume_size   = 6
    rke2_version       = local.rke2_version
    rke2_volume_size   = 8
    rke2_volume_device = "/dev/vdb"
    # https://docs.rke2.io/install/install_options/server_config/
    rke2_config = <<EOF
write-kubeconfig-mode: "0644"
EOF
  }]

  agents = [
    {
      name               = "worker"
      nodes_count        = var.worker_count
      flavor_name        = var.flavor_name
      image_name         = local.image_name
      system_user        = local.system_user
      boot_volume_size   = 6
      rke2_version       = local.rke2_version
      rke2_volume_size   = 8
      rke2_volume_device = "/dev/vdb"
    }
  ]

  # Kleine Requests, damit die Control Plane auf m1.medium Platz lässt
  kube_apiserver_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube_scheduler_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube_controller_manager_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  etcd_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  dns_nameservers4 = [local.dns_server]
  # Worker beim Abbau aus dem Cluster austragen (max. 30 s warten)
  ff_autoremove_agent = "30s"
  # kubeconfig nach n8n.rke2.yaml in diesen Ordner holen
  ff_write_kubeconfig = true
  # etcd-Backup nach S3 kommt mit dem Thema Backup, bis dahin aus
  ff_native_backup = false
  # apply wartet, bis RKE2 auf den Knoten läuft
  ff_wait_ready = true

  identity_endpoint = local.auth_url

  # "*" gilt für alle Registries. Ist der Mirror nicht erreichbar, ziehen die
  # Knoten direkt von der Original-Registry.
  registries = {
    mirrors = var.registry_mirror == "" ? {} : {
      "*" = {
        endpoint = [var.registry_mirror]
      }
    }
  }
}
