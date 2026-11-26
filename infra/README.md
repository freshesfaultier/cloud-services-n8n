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

Die S3-Schlüssel in jedem neuen Terminal setzen. `Read-Host` und `read` fragen die Werte ab, so landen sie nicht im Befehlsverlauf. In PowerShell:

```
$env:AWS_ACCESS_KEY_ID = Read-Host "access"
$env:AWS_SECRET_ACCESS_KEY = Read-Host "secret"
```

In bash:

```
read -p "access: " AWS_ACCESS_KEY_ID && export AWS_ACCESS_KEY_ID
read -s -p "secret: " AWS_SECRET_ACCESS_KEY && export AWS_SECRET_ACCESS_KEY
```

Dann in `infra/`:

```
terraform init
terraform plan
terraform apply
```

`apply` nur auf aktuellem `main` ausführen, vorher `git pull`. Der State ist gemeinsam, der Code auf dem eigenen Rechner nicht. Mit veraltetem Code löscht `apply` alles, was andere inzwischen gebaut haben.

## kubeconfig

Die kubeconfig enthält die Adresse des Clusters und den Admin-Zugang. Sie gehört nicht ins Repo und nicht in einen Chat, die `.gitignore` schließt `*.rke2.yaml` aus.

### Wer den Cluster gebaut hat

Das Modul holt die kubeconfig nur, wenn der Controller neu entsteht, und nur auf den Rechner der Person, die `apply` ausgeführt hat. Sie liegt dann in `infra/n8n.rke2.yaml`. In PowerShell im Ordner `infra/`:

```
$env:KUBECONFIG = "$PWD\n8n.rke2.yaml"
kubectl get nodes
```

In bash im Ordner `infra/`:

```
export KUBECONFIG=$PWD/n8n.rke2.yaml
kubectl get nodes
```

`$PWD` macht daraus einen absoluten Pfad, so findet kubectl die Datei auch aus anderen Ordnern.

### Alle anderen

Ein `apply` ohne Änderungen holt keine kubeconfig. Wer den Cluster nicht gebaut hat, holt sie per SSH vom Controller. Das geht, weil alle Schlüssel aus `ssh-keys/` auf den Knoten liegen. Auf dem Controller zeigt die Datei auf `127.0.0.1`, deshalb wird die Adresse durch die Floating IP ersetzt.

In PowerShell im Ordner `infra/`, mit gesetzten S3-Schlüsseln:

```
$ip = terraform output -raw floating_ip
ssh -o StrictHostKeyChecking=accept-new ubuntu@$ip "sudo cat /etc/rancher/rke2/rke2.yaml" | ForEach-Object { $_ -replace '127\.0\.0\.1', $ip } | Set-Content -Encoding ascii n8n.rke2.yaml
$env:KUBECONFIG = "$PWD\n8n.rke2.yaml"
kubectl get nodes
```

In bash im Ordner `infra/`:

```
ip=$(terraform output -raw floating_ip)
ssh -o StrictHostKeyChecking=accept-new ubuntu@$ip "sudo cat /etc/rancher/rke2/rke2.yaml" | sed "s/127\.0\.0\.1/$ip/" > n8n.rke2.yaml
chmod 600 n8n.rke2.yaml
export KUBECONFIG=$PWD/n8n.rke2.yaml
kubectl get nodes
```

Der Kontext heißt in dieser Kopie `default` statt `n8n`, das ändert nichts an der Funktion.

Nach einem Neuaufbau hat der Controller einen neuen Host-Schlüssel. Bekommt er dieselbe IP, bricht `ssh` mit „REMOTE HOST IDENTIFICATION HAS CHANGED“ ab. Dann zuerst den alten Eintrag entfernen: `ssh-keygen -R <floating-ip>`.

### Wann man sie neu holen muss

Alle Kopien sind gleichwertig und funktionieren parallel. Der Cluster merkt sich nicht, wer eine Kopie hat.

| Situation                                     | Vorhandene Kopien                                                |
| --------------------------------------------- | ---------------------------------------------------------------- |
| `apply` ohne Änderungen                       | bleiben gültig                                                   |
| Controller ersetzt, z. B. neuer SSH-Schlüssel | bleiben gültig, CA und Zertifikate liegen auf dem eigenen Volume |
| `destroy` und neues `apply`                   | ungültig, neue CA und meist neue Floating IP, alle holen sie neu |

## Teardown

`terraform destroy` in `infra/`. Der Bucket bleibt stehen. Danach im Dashboard auf Reste prüfen, vor allem Volumes, Load Balancer und Floating IPs.

## Eigenes Deployment in einem anderen Projekt

1. In `bootstrap/` einen eigenen Bucket anlegen: `terraform apply -var="bucket_name=<name>"`
2. In `infra/` diesen Bucket verwenden: `terraform init -backend-config="bucket=<name>"`
3. Abweichende Werte in `terraform.tfvars` setzen, Vorlage: `terraform.tfvars.example`
