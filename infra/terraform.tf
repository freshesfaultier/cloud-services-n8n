terraform {
  # use_lockfile im S3-Backend gibt es ab Terraform 1.10
  required_version = ">= 1.10.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }

  # Gemeinsamer State im Bucket aus bootstrap/. Die Zugangsdaten kommen aus
  # AWS_ACCESS_KEY_ID und AWS_SECRET_ACCESS_KEY, siehe README.md.
  #
  # Im backend-Block sind keine Variablen erlaubt, weil Terraform ihn vor allem
  # anderen liest. Für einen anderen Bucket den Namen beim init überschreiben:
  #   terraform init -backend-config="bucket=<name>"
  backend "s3" {
    bucket    = "cloudserv8-n8n-tfstate"
    key       = "infra/terraform.tfstate"
    region    = "eu-central-1" # Pflichtfeld, Ceph ignoriert den Wert
    endpoints = { s3 = "https://s3.private-cloud.informatik.hs-fulda.de" }

    # Sperrt den State über eine .tflock-Datei neben dem State, solange
    # jemand plan oder apply ausführt
    use_lockfile = true

    # Ceph ist kein AWS: AWS-eigene Prüfungen abschalten, Bucket im Pfad
    # statt als Subdomain ansprechen
    use_path_style              = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}

# Zugangsdaten aus clouds.yaml, Eintrag "openstack", siehe README.md
provider "openstack" {
  cloud = "openstack"

  # Keystone-Public-Endpoint zeigt noch auf eine VIP mit internem Zertifikat,
  # deshalb den Endpoint erzwingen
  endpoint_overrides = {
    "identity" = local.auth_url
  }
}
