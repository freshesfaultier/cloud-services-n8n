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
- yq von [mikefarah](https://github.com/mikefarah/yq), nicht das gleichnamige Python-Paket aus apt
- Für `apply`, damit das Modul die kubeconfig holen kann: unter Windows PowerShell und OpenSSH, unter Linux und macOS ssh und rsync. Der SSH-Agent muss den eigenen Schlüssel anbieten.

## Einmal pro Person

Die OpenStack-CLI und Terraform suchen die Zugangsdaten im Ordner `.config/openstack` im eigenen Home-Ordner:

| System  | Ordner                                 |
| ------- | -------------------------------------- |
| Windows | `C:\Users\<name>\.config\openstack\`   |
| Linux   | `/home/<name>/.config/openstack/`      |
| macOS   | `/Users/<name>/.config/openstack/`     |

Dort liegen die Zugangsdaten außerhalb des Repos, und alle Werkzeuge finden sie aus jedem Ordner. In PowerShell steht `$HOME` für den Home-Ordner, in bash `~`.

### 1. `clouds.yaml` ablegen

Im Dashboard unter API-Zugriff herunterladen und das Passwort ergänzen, Vorlage: `clouds.yaml.example`. In PowerShell:

```
New-Item -ItemType Directory -Force "$HOME\.config\openstack"
Copy-Item <heruntergeladene Datei> "$HOME\.config\openstack\clouds.yaml"
```

In bash, `chmod` macht die Datei nur für einen selbst lesbar:

```
mkdir -p ~/.config/openstack
cp <heruntergeladene Datei> ~/.config/openstack/clouds.yaml
chmod 600 ~/.config/openstack/clouds.yaml
```

### 2. CA-Datei anlegen

Die Keystone-Endpunkte im Katalog zeigen auf eine interne Adresse mit einem Zertifikat der NetLab-CA. Ohne diesen Schritt scheitern Keystone-Befehle wie `openstack ec2 credentials create` am Zertifikat. Die Lösung: die normalen Root-Zertifikate und `netlab-ca.crt` zu einer Datei zusammenfügen und sie in `clouds.yaml` als `cacert` eintragen.

In PowerShell im Ordner `infra/`, die normalen Root-Zertifikate kommen von Python:

```
Get-Content (python -c "import certifi; print(certifi.where())"), netlab-ca.crt | Set-Content -Encoding ascii "$HOME\.config\openstack\ca-bundle.pem"
$env:CAB = "$HOME\.config\openstack\ca-bundle.pem"
yq -i '.clouds.openstack.cacert = strenv(CAB)' "$HOME\.config\openstack\clouds.yaml"
```

In bash im Ordner `infra/`, die normalen Root-Zertifikate kommen vom System. Der Pfad gilt für Debian und Ubuntu, unter macOS ist es `/etc/ssl/cert.pem`:

```
cat /etc/ssl/certs/ca-certificates.crt netlab-ca.crt > ~/.config/openstack/ca-bundle.pem
CAB=~/.config/openstack/ca-bundle.pem yq -i '.clouds.openstack.cacert = strenv(CAB)' ~/.config/openstack/clouds.yaml
```

Ohne yq die Zeile `cacert` von Hand eintragen, mit absolutem Pfad, siehe Vorlage.

### 3. Testen

```
openstack ec2 credentials list
```

Keine Fehlermeldung heißt, die CLI erreicht Keystone. Gibt es noch keine S3-Schlüssel, bleibt die Ausgabe leer. Bei „SSL exception“ mit der Adresse `10.32.4.29` hat Schritt 2 nicht geklappt.

### 4. S3-Schlüssel erzeugen

```
openstack ec2 credentials create
```

Aus der Ausgabe braucht man `access` und `secret`. Beides gehört in einen Passwort-Manager, nicht ins Repo und nicht in einen Chat.

### 5. SSH-Schlüssel eintragen

Den eigenen öffentlichen Schlüssel als `ssh-keys/<name>.pub` committen. Ein neuer Schlüssel ersetzt beim nächsten `apply` alle VMs.

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

Nach dem ersten `apply` liegt die kubeconfig in `infra/n8n.rke2.yaml`. In PowerShell:

```
$env:KUBECONFIG = terraform output -raw kubeconfig
kubectl get nodes
```

In bash:

```
export KUBECONFIG=$(terraform output -raw kubeconfig)
kubectl get nodes
```

## Teardown

`terraform destroy` in `infra/`. Der Bucket bleibt stehen. Danach im Dashboard auf Reste prüfen, vor allem Volumes, Load Balancer und Floating IPs.

## Eigenes Deployment in einem anderen Projekt

1. In `bootstrap/` einen eigenen Bucket anlegen: `terraform apply -var="bucket_name=<name>"`
2. In `infra/` diesen Bucket verwenden: `terraform init -backend-config="bucket=<name>"`
3. Abweichende Werte in `terraform.tfvars` setzen, Vorlage: `terraform.tfvars.example`
