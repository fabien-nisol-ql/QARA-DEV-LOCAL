BUILD := ./build
INFRA := src/infra
KIND_VERSION := v0.23.0
KIND_CLUSTER_NAME := qara-dev-local
KIND_TEMPLATE := $(INFRA)/kind-config.template.yaml
KIND_CONFIG_FILE := $(BUILD)/kind-config.yaml
DOCKER_NETWORK := kind-compose-net
INSTALL_PATH := /usr/local/bin/kind
KIND_URL_LINUX := https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-linux-amd64
KIND_URL_DARWIN := https://kind.sigs.k8s.io/dl/$(KIND_VERSION)/kind-darwin-amd64
POSTGRES_MANIFEST := $(INFRA)/postgres-deployment.yaml

# services
DB_TIMEOUT := 60
VALUES_DIR := src/services
CHART_DIR := src/helm

.DEFAULT_GOAL := help

.PHONY: help check-kind install-kind create-network create-cluster start cleanup microservices check-helm install-helm reset-database

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Available targets:"
	@echo "  help             Show this help message"
	@echo "  check-kind       Check if 'kind' is installed, install if missing"
	@echo "  install-kind     Force install 'kind' CLI (macOS, Linux, or WSL)"
	@echo "  create-network   Create shared Docker network for kind and compose"
	@echo "  create-cluster   Create kind cluster and attach to shared network"
	@echo "  start            Create network, cluster, and deploy services"
	@echo "  clean            Delete kind cluster, stop Docker services, remove network and kind binary"

check-kind:
	@echo "🔍 Checking if 'kind' is installed..."
	@if ! command -v kind >/dev/null 2>&1; then \
		$(MAKE) install-kind; \
	else \
		echo "✅ kind is already installed at $$(command -v kind)"; \
	fi

install-kind:
	@echo "📦 Installing kind $(KIND_VERSION)..."
	@if uname | grep -qi "darwin"; then \
		echo "Detected macOS"; \
		curl -Lo kind $(KIND_URL_DARWIN); \
	elif grep -qi microsoft /proc/version 2>/dev/null; then \
		echo "Detected WSL (Linux)"; \
		curl -Lo kind $(KIND_URL_LINUX); \
	else \
		echo "Detected Linux"; \
		curl -Lo kind $(KIND_URL_LINUX); \
	fi && \
	chmod +x kind && \
	sudo mv kind $(INSTALL_PATH) && \
	echo "✅ kind installed successfully to $(INSTALL_PATH)"


check-helm:
	@echo "🔍 Checking if 'helm' is installed..."
	@if ! command -v helm >/dev/null 2>&1; then \
		$(MAKE) install-helm; \
	else \
		echo "✅ helm is already installed at $$(command -v helm)"; \
	fi

install-helm:
	@echo "📦 Installing Helm..."
	@if uname | grep -qi "darwin"; then \
		echo "Detected macOS"; \
		brew install helm; \
	elif grep -qi microsoft /proc/version 2>/dev/null; then \
		echo "Detected WSL (Linux)"; \
		curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
	else \
		echo "Detected Linux"; \
		curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
	fi
	@echo "✅ Helm installed successfully"


create-network:
	@echo "🌐 Creating shared Docker network '${DOCKER_NETWORK}'..."
	@if ! docker network inspect $(DOCKER_NETWORK) >/dev/null 2>&1; then \
		docker network create $(DOCKER_NETWORK); \
	else \
		echo "✅ Docker network '$(DOCKER_NETWORK)' already exists"; \
	fi

$(BUILD):
	mkdir -p $(BUILD)

create-cluster: check-kind create-network
	@if kind get clusters | grep -qx "$(KIND_CLUSTER_NAME)"; then \
		echo "✅ KinD cluster '$(KIND_CLUSTER_NAME)' already exists. Skipping creation."; \
	else \
		echo "⛴️ Creating KinD cluster '$(KIND_CLUSTER_NAME)'..."; \
		sed 's/{{CLUSTER_NAME}}/$(KIND_CLUSTER_NAME)/g' $(KIND_TEMPLATE) > $(KIND_CONFIG_FILE); \
		kind create cluster --name $(KIND_CLUSTER_NAME) --config $(KIND_CONFIG_FILE); \
		echo "🔗 Connecting '$(KIND_CLUSTER_NAME)-control-plane' to network '$(DOCKER_NETWORK)'..."; \
		docker network connect $(DOCKER_NETWORK) $(KIND_CLUSTER_NAME)-control-plane; \
		rm -f $(KIND_CONFIG_FILE); \
		echo "✅ KinD cluster created and attached to network."; \
	fi


database:
	@echo "🚀 Deploying PostgreSQL to Kubernetes..."
	@kubectl apply -f $(POSTGRES_MANIFEST)
	@echo "✅ PostgreSQL deployed."

reset-database:
	@echo "🧨 Resetting PostgreSQL deployment..."
	@kubectl delete pvc postgres-pvc -n postgres || true
	@kubectl delete pod -l app=postgres -n postgres || true
	@kubectl apply -f postgres-deployment.yaml
	@echo "✅ PostgreSQL has been reset with fresh volume and credentials."

wait-for-postgres:
	@echo "⏳ Waiting for PostgreSQL to be ready..."
	@i=0; until kubectl run pgwait --image=postgres:15 --rm -i --restart=Never \
		-n postgres -- pg_isready -h postgres -U postgres > /dev/null 2>&1; do \
		i=$$((i+1)); \
		if [ $$i -gt $(DB_TIMEOUT) ]; then \
			echo "❌ PostgreSQL not ready after $(DB_TIMEOUT) seconds"; \
			exit 1; \
		fi; \
		echo "⏱  Waiting... ($$i)"; \
		sleep 1; \
	done
	@echo "✅ PostgreSQL is ready!"

microservices: check-helm wait-for-postgres
	@echo "🚀 Deploying microservices from Helm values in $(VALUES_DIR)/..."
	@for values_file in `ls $(VALUES_DIR)/*.yaml`; do \
		namespace=$$(basename $$values_file .yaml); \
		echo "🔧 Deploying to namespace '$$namespace' using $$values_file..."; \
		kubectl get ns $$namespace >/dev/null 2>&1 || kubectl create namespace $$namespace; \
		helm upgrade --install $$namespace $(CHART_DIR) -n $$namespace -f $$values_file; \
	done
	@echo "✅ All Helm charts deployed."



start: create-cluster database microservices

clean:
	@echo "🧹 Cleaning up KinD, Kubernetes resources, and network..."
	@if test -f $(POSTGRES_MANIFEST); then \
		kubectl delete -f $(POSTGRES_MANIFEST) || true; \
	fi
	@if command -v kind >/dev/null 2>&1 && kind get clusters | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "Deleting kind cluster..."; \
		kind delete cluster --name $(KIND_CLUSTER_NAME); \
	fi
	@if docker network inspect $(DOCKER_NETWORK) >/dev/null 2>&1; then \
		docker network rm $(DOCKER_NETWORK); \
	fi
	@if [ -f $(INSTALL_PATH) ]; then \
		echo "Removing kind binary from $(INSTALL_PATH)..."; \
		sudo rm -f $(INSTALL_PATH); \
	fi
	@echo "✅ Cleanup complete."