# Marketplace — Helm chart (minikube)

Deploys the full stack (infra + Spring services + newsletter + frontend) via a
single chart, pulling app images from your Docker Hub account.

## Layout

```
charts/marketplace/
├── Chart.yaml
├── values.yaml            # all configurable settings — dockerhub user, ports, credentials
├── files/
│   └── postgres-init.sql  # <- replace with your real ./docker/postgres-init.sql
└── templates/
    ├── secrets.yaml            # mysql/postgres/keycloak/newsletter dev credentials
    ├── configmap-common.yaml   # spring-env-config + db-hosts-config
    ├── configmap-postgres-init.yaml
    ├── infra-*.yaml            # mysql, postgres, mongo, rabbitmq, mailpit, keycloak
    ├── apps.yaml               # loop template: configserver, eureka, gateway, 6 business services
    ├── newsletter.yaml
    ├── frontend.yaml
    └── NOTES.txt
```

`apps.yaml` is a single generic template that loops over `values.apps` — each
entry becomes a Deployment + Service. configserver and eureka are special-cased
(different env, no wait-for-configserver initContainer); everything else gets
`spring-env-config` + `db-hosts-config` injected and waits for configserver.

## 1. Point images at your Docker Hub account

Either edit `values.yaml` directly:
```yaml
dockerhubUser: <your-dockerhub-username>
```
or pass it at install time (see below) with `--set`.

## 2. Drop in your real Postgres init script

Replace the placeholder content of `files/postgres-init.sql` with your actual
`./docker/postgres-init.sql`. It's loaded via `.Files.Get` into a ConfigMap and
mounted into the postgres container automatically.

## 3. Start minikube and install

```bash
minikube start
helm install marketplace ./charts/marketplace \
  -n marketplace --create-namespace \
  --set dockerhubUser=<your-dockerhub-username>

kubectl -n marketplace get pods -w
```

## 4. Reach the app

Minikube can open a NodePort service directly for you — no manual IP/port math,
no ingress controller needed:

```bash
minikube service gateway  -n marketplace --url
minikube service keycloak -n marketplace --url
minikube service frontend -n marketplace --url
```

Each command prints a URL like `http://127.0.0.1:xxxxx` (or opens your browser
directly if you drop `--url`).

**Important — update two values once you have those URLs**, since JWT issuer
validation and the frontend's API calls both need the *actual* reachable URL,
not the placeholder:

```bash
helm upgrade marketplace ./charts/marketplace -n marketplace \
  --set dockerhubUser=<your-dockerhub-username> \
  --set springEnv.keycloakIssuerUri="<keycloak url>/realms/microservice-project" \
  --set frontend.apiBaseUrl="<gateway url>"

kubectl -n marketplace rollout restart deployment/gateway deployment/frontend
```

(`helm upgrade` needs the full set of `--set` flags again, or keep them in a
`my-values.yaml` overrides file and pass `-f my-values.yaml` instead — see below.)

## Using an overrides file instead of --set

Create `my-values.yaml`:
```yaml
dockerhubUser: yourusername
springEnv:
  keycloakIssuerUri: "http://127.0.0.1:xxxxx/realms/microservice-project"
frontend:
  apiBaseUrl: "http://127.0.0.1:yyyyy"
```
then:
```bash
helm install marketplace ./charts/marketplace -n marketplace --create-namespace -f my-values.yaml
# later:
helm upgrade marketplace ./charts/marketplace -n marketplace -f my-values.yaml
```

## Uninstall

```bash
helm uninstall marketplace -n marketplace
kubectl delete namespace marketplace
```

## Notes / things you may want to change later

- **Storage:** all databases use `emptyDir` volumes (data lost on pod restart)
  — simplest for minikube testing. Swap to a `PersistentVolumeClaim` if you
  need data to survive restarts (`minikube` ships a default StorageClass, so
  PVCs work out of the box if you want to switch).
- **Credentials:** `secrets.yaml` uses the same plaintext dev credentials as
  your docker-compose file (root/root, postgres/postgres, admin/admin) —
  overridable via `values.yaml`, fine for testing only.
- **Probes:** only mysql, postgres, and configserver have health probes wired
  up (mirroring your compose healthchecks). Add more via `values.yaml` /
  `apps.yaml` if you want stricter readiness gating.
- **Single replica, no resource requests/limits** — add these (`values.yaml`
  → per-service `resources:` blocks) before using this outside a scratch/test
  cluster.
- **No dependency ordering beyond configserver** — services don't wait on
  their specific databases being ready, only on configserver. Add an
  initContainer per service if you hit startup race conditions.
