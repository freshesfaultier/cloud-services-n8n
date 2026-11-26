# Argo CD

Argo CD deployt unsere Anwendungen nach dem GitOps-Prinzip. Der Sollzustand steht in diesem Repo. Argo CD läuft im Cluster, vergleicht laufend Git mit dem Cluster und gleicht Abweichungen an.

| Datei         | Inhalt                                       |
| ------------- | -------------------------------------------- |
| `values.yaml` | unsere Werte für das Helm-Chart `argo/argo-cd` |

## Warum Argo CD

Der Cluster ist nur im NetLab oder über das NetLab-VPN erreichbar. Eine Pipeline in GitHub Actions läuft im Internet und kommt nicht an den API-Server, ein `kubectl apply` aus der Pipeline (Push-Modell) geht also nicht. Argo CD sitzt im Cluster und holt sich den Sollzustand selbst aus Git (Pull-Modell). Es braucht nur ausgehenden Zugang zu GitHub und den Registries, und die kubeconfig muss nicht als Secret zu GitHub.

Flux CD arbeitet ebenfalls nach dem Pull-Modell. Argo CD zeigt den Sync-Status aber in einer Weboberfläche, und das Lab verlangt es.

## Voraussetzungen

- NetLab oder NetLab-VPN
- laufender Cluster und eine kubeconfig, siehe [`infra/README.md`](../../infra/README.md#kubeconfig)
- kubectl
- Helm 3 oder 4

## Installation

Einmal pro Cluster, das macht eine Person. Nach einem `terraform destroy` und neuem `apply` ist Argo CD wieder weg und muss neu installiert werden.

Das Helm-Repo einmal pro Rechner eintragen. `repo add` merkt sich unter dem Kurznamen `argo` die Adresse, `repo update` lädt die Liste der Charts und Versionen:

```
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
```

Dann im Wurzelordner des Repos, mit gesetzter `KUBECONFIG`:

```
helm install argocd argo/argo-cd --version 10.20.0 -n argocd --create-namespace -f k8s/argocd/values.yaml
kubectl -n argocd get pods -w
```

Nach etwa einer Minute sind alle Pods `Running`. `argocd-redis-secret-init` steht auf `Completed`, das ist ein einmaliger Job, der das Redis-Passwort erzeugt.

Die Chart-Version ist gepinnt, damit jede Installation gleich aussieht. Neue Versionen zeigt `helm search repo argo/argo-cd --versions`.

## Oberfläche

Argo CD hat keine öffentliche Adresse. Der Zugang läuft über einen Tunnel durch den API-Server, der nur auf dem eigenen Rechner gilt. Das Fenster bleibt dabei belegt, also ein eigenes Terminal nehmen:

```
kubectl port-forward service/argocd-server -n argocd 8080:443
```

Dann <https://localhost:8080> öffnen. Der Browser warnt vor dem Zertifikat, weil Argo CD sich selbst eines ausgestellt hat. Das ist hier in Ordnung, der Verkehr läuft ohnehin durch den kubectl-Tunnel.

Login mit `admin`. Das Passwort liegt im Passwort-Manager der Gruppe.

## Nach einer neuen Installation: Passwort setzen

Argo CD erzeugt beim Install ein zufälliges Passwort und legt es im Secret `argocd-initial-admin-secret` ab. Kubernetes speichert Secrets nur Base64-kodiert, nicht verschlüsselt. Jede Person mit Zugriff auf den Namespace kann es lesen.

Passwort auslesen, in PowerShell (`base64 -d` gibt es dort nicht):

```
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}")))
```

In bash:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

Dann in dieser Reihenfolge:

1. In der Oberfläche unter **User Info** → **UPDATE PASSWORD** ein neues Passwort setzen und im Passwort-Manager der Gruppe ablegen
2. Erst danach das Secret löschen:
   ```
   kubectl -n argocd delete secret argocd-initial-admin-secret
   ```

## Konfiguration

| Wert                        | Warum                                                                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------- |
| `dex.enabled: false`        | Dex ist für SSO, etwa Login mit GitHub. Wir nutzen den lokalen `admin` und sparen RAM.         |
| `notifications.enabled: false` | Benachrichtigungen an Slack oder Mail nutzen wir nicht.                                     |
| `server.service.type: ClusterIP` | Erreichbar nur im Cluster und per Port-Forward. `LoadBalancer` würde in OpenStack einen Octavia-LB mit Floating IP anlegen. Ein Zugang über Ingress kommt in Frage, sobald der Cluster einen Ingress-Controller hat. Das RKE2-Modul schaltet die mitgelieferten ab. |

Werte ändern oder Chart-Version anheben, im Wurzelordner des Repos:

```
helm upgrade argocd argo/argo-cd --version <version> -n argocd -f k8s/argocd/values.yaml
```

Argo CD ließe sich auch über die Variable `manifests` des RKE2-Moduls in `infra/` gleich beim Bau des Clusters installieren. Die Manifeste landen dort aber per cloud-init auf dem Controller, und jede Änderung ersetzt die VM. Deshalb installieren wir Argo CD per Helm.

## Teardown

Zuerst die Applications in Argo CD löschen. Argo CD räumt dann deren Ressourcen ab. PVCs, die ein StatefulSet selbst angelegt hat, bleiben dabei stehen. Die Standard-StorageClass `csi-cinder-retain` lässt deren Volumes in OpenStack auch nach dem Löschen der PVC liegen. Solche Volumes vorher auf `Delete` umstellen, siehe Troubleshooting.

Dann Argo CD selbst entfernen:

```
helm uninstall argocd -n argocd
kubectl delete namespace argocd
```

Die CRDs (`applications`, `applicationsets` und `appprojects` in `argoproj.io`) lässt das Chart beim Uninstall bewusst stehen, damit keine Applications versehentlich verschwinden. Für einen vollständigen Abbau:

```
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
```

Argo CD selbst legt weder Volumes noch Load Balancer an. Vor einem `terraform destroy` ist der Uninstall deshalb nicht nötig, das Löschen der Applications schon.

## Troubleshooting

| Problem                                          | Lösung                                                                                       |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------- |
| `Error: INSTALLATION FAILED: repo argo not found` | Helm-Repo auf diesem Rechner noch nicht eingetragen, siehe Installation                     |
| `base64` in PowerShell unbekannt                 | PowerShell-Befehl aus „Passwort setzen“ nehmen                                               |
| Port-Forward: `address already in use`           | Port 8080 ist belegt, anderen Port nehmen, z. B. `8081:443` und <https://localhost:8081>     |
| Rollback in der Oberfläche nicht möglich         | Argo CD erlaubt kein Rollback, solange automatischer Sync an ist. Sauberer ist ohnehin `git revert`. |
| Volume bleibt nach dem Löschen in OpenStack liegen | Vor dem Löschen der PVC die Reclaim-Policy umstellen. In PowerShell 5.1 brauchen die Anführungszeichen Backslashes: `kubectl patch pv <name> -p '{\"spec\":{\"persistentVolumeReclaimPolicy\":\"Delete\"}}'`, in bash ohne Backslashes. |
