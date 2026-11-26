# infra

Terraform für die Infrastruktur im OpenStack NetLab: ein RKE2-Kubernetes-Cluster mit einem Controller und einem Worker.

| Pfad                         | Inhalt                                             |
| ---------------------------- | -------------------------------------------------- |
| `bootstrap/`                 | Bucket für den Terraform-State, einmal anlegen     |
| `terraform.tf`               | Terraform-Version, Provider und Backend            |
| `main.tf`                    | Cluster über das RKE2-Modul aus dem Lab-Repo       |
| `variables.tf`, `outputs.tf` | Eingaben und Ergebnisse                            |
| `ssh-keys/`                  | öffentliche SSH-Schlüssel der Gruppe               |
| `netlab-ca.crt`              | Root-CA des NetLab für die Keystone-Endpunkte      |

## Voraussetzungen

- NetLab oder NetLab-VPN
- Terraform ab 1.10
- OpenStack-CLI: `pip install python-openstackclient`
- Für `apply`, damit das Modul die kubeconfig holen kann: unter Windows PowerShell, OpenSSH und yq, unter Linux und macOS ssh, rsync und yq. Der SSH-Agent muss den eigenen Schlüssel anbieten.

## Einmal pro Person

1. `clouds.yaml` im Dashboard unter API-Zugriff herunterladen, das Passwort ergänzen und als `~/.config/openstack/clouds.yaml` ablegen. Vorlage: `clouds.yaml.example`.
2. CA-Datei anlegen. Die Keystone-Endpunkte im Katalog zeigen auf eine interne Adresse mit einem Zertifikat der NetLab-CA. Die CLI vertraut ihr erst, wenn man die normalen Root-Zertifikate und `netlab-ca.crt` zu einer Datei zusammenfügt. Im Ordner `infra/`, in PowerShell:
   ```
   Get-Content (python -c "import certifi; print(certifi.where())"), netlab-ca.crt | Set-Content -Encoding ascii "$HOME\.config\openstack\ca-bundle.pem"
   ```
   In bash:
   ```
   cat "$(python3 -c 'import certifi; print(certifi.where())')" netlab-ca.crt > ~/.config/openstack/ca-bundle.pem
   ```
   Dann in `clouds.yaml` die Zeile `cacert` mit dem absoluten Pfad dieser Datei eintragen, siehe Vorlage.
3. S3-Schlüssel erzeugen. Aus der Ausgabe braucht man `access` und `secret`.
   ```
   openstack ec2 credentials create
   ```
4. Eigenen öffentlichen SSH-Schlüssel als `ssh-keys/<name>.pub` committen. Ein neuer Schlüssel ersetzt beim nächsten `apply` alle VMs.

## Einmal für die Gruppe

Den Bucket für den State anlegen. Das macht eine Person, danach nutzen ihn alle.

```
cd infra/bootstrap
terraform init
terraform apply
```

## Deploy

Die S3-Schlüssel in jedem neuen Terminal setzen, in PowerShell:

```
$env:AWS_ACCESS_KEY_ID = "<access>"
$env:AWS_SECRET_ACCESS_KEY = "<secret>"
```

In bash:

```
export AWS_ACCESS_KEY_ID=<access> AWS_SECRET_ACCESS_KEY=<secret>
```

Dann in `infra/`:

```
terraform init
terraform plan
terraform apply
```

`apply` nur auf aktuellem `main` ausführen, vorher `git pull`. Der State ist gemeinsam, der Code auf dem eigenen Rechner nicht. Mit veraltetem Code löscht `apply` alles, was andere inzwischen gebaut haben.

Nach dem ersten `apply` liegt die kubeconfig in `infra/n8n.rke2.yaml`:

```
$env:KUBECONFIG = terraform output -raw kubeconfig
kubectl get nodes
```

## Teardown

`terraform destroy` in `infra/`. Der Bucket bleibt stehen. Danach im Dashboard auf Reste prüfen, vor allem Volumes, Load Balancer und Floating IPs.

## Eigenes Deployment in einem anderen Projekt

1. In `bootstrap/` einen eigenen Bucket anlegen: `terraform apply -var="bucket_name=<name>"`
2. In `infra/` diesen Bucket verwenden: `terraform init -backend-config="bucket=<name>"`
3. Abweichende Werte in `terraform.tfvars` setzen, Vorlage: `terraform.tfvars.example`
