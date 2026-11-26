# Die Standardwerte gelten für unser gemeinsames Deployment. Andere Werte nur
# für ein eigenes Deployment setzen, siehe terraform.tfvars.example.

variable "flavor_name" {
  type        = string
  description = "OpenStack-Flavor für Controller und Worker"
  default     = "m1.medium"
}

variable "worker_count" {
  type        = number
  description = "Anzahl der Worker-Knoten"
  default     = 1
}

variable "registry_mirror" {
  type        = string
  description = "Registry-Mirror für die Knoten, leer lassen für Docker Hub direkt"
  # Harbor des Fachbereichs, nur im Hochschulnetz erreichbar
  default = "https://harbor.cs.hs-fulda.de"
}
