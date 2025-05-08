# Local PostgreSQL Deployment on KinD for Development

This project sets up a local Kubernetes cluster using [KinD (Kubernetes in Docker)](https://kind.sigs.k8s.io/) and deploys a PostgreSQL database inside it using standard Kubernetes manifests.

## 📦 Prerequisites

Make sure the following are installed (linux, macos, or windows subsystem for linux)

- [Docker](https://www.docker.com/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [make](https://www.gnu.org/software/make/)
- [helm](https://helm.sh/) (if you're deploying microservices via Helm)

## 🚀 Quick Start

To spin up everything for local development:

```bash
make start
```

This will:

1. Check and install KinD if missing
2. Create a `kind` cluster
3. Create a shared Docker network
4. Attach the KinD cluster to that network
5. Deploy PostgreSQL in the `postgres` namespace

## 📂 File Structure

```
.
├── Makefile                    # Automation commands
├── postgres-deployment.yaml   # Kubernetes manifests (PVC + Deployment + Service)
├── kind-config.template.yaml  # Templated KinD config (used by Makefile)
```

## 🛠 Connecting to PostgreSQL

To access PostgreSQL from inside the cluster:

```bash
kubectl run psql \
  --image=postgres:15 \
  --rm -it \
  --restart=Never \
  -n postgres \
  -- psql -h postgres -U user -d mydb
```

**Default credentials:**

- User: `user`
- Password: `password`
- DB: `mydb`

## 🧹 Clean Up

To tear everything down (cluster, network, Helm binaries, and manifests):

```bash
make cleanup
```

## 📦 Optional: Deploy Microservices via Helm

If you have multiple microservices defined via Helm charts and value files:

1. Put Helm values in `./values/`, e.g.:
    - `values/auth.yaml`
    - `values/billing.yaml`

2. Run:

```bash
make deploy-microservices
```

Each file will be deployed to a namespace matching its filename.

---

## 📘 Notes

- PostgreSQL is deployed in the `postgres` namespace
- Persistent volume is ephemeral (no external storage plugin)
- Helm is installed automatically if missing

---

## 🔗 Resources

- [KinD](https://kind.sigs.k8s.io/)
- [Helm](https://helm.sh/)
- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)
