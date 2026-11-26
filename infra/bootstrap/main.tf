# Legt einmalig den Bucket an, in dem infra/ seinen Terraform-State ablegt.
#
# Der Bucket muss existieren, bevor infra/ ihn als Backend nutzen kann. Deshalb
# ist er hier getrennt: Ein terraform destroy in infra/ lässt ihn stehen.
# Der State dieses Ordners bleibt lokal bei der Person, die ihn angelegt hat.
# Er enthält nur den Namen des Buckets und kein Secret.

variable "bucket_name" {
  type        = string
  description = "Name des Buckets, muss zu bucket im backend-Block von infra/terraform.tf passen"
  # Mit Projektnamen, falls Ceph die Bucket-Namen nicht pro Projekt trennt
  default = "cloudserv8-n8n-tfstate"
}

locals {
  auth_url = "https://private-cloud.informatik.hs-fulda.de:5000/v3/"
}

# Swift-Container und S3-Bucket sind im NetLab dasselbe: Ceph bietet beide
# Schnittstellen auf denselben Speicher an.
resource "openstack_objectstorage_container_v1" "tfstate" {
  name = var.bucket_name
  # Kein force_destroy: Ein destroy scheitert, solange noch ein State im
  # Bucket liegt. So löscht niemand versehentlich den gemeinsamen State.
}

output "bucket_name" {
  value = openstack_objectstorage_container_v1.tfstate.name
}

# Zugangsdaten aus clouds.yaml, Eintrag "openstack", siehe infra/README.md
provider "openstack" {
  cloud = "openstack"

  # Keystone-Public-Endpoint zeigt noch auf eine VIP mit internem Zertifikat,
  # deshalb den Endpoint erzwingen
  endpoint_overrides = {
    "identity" = local.auth_url
  }
}

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }
}
