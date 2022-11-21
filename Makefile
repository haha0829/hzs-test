# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.24.1

# Image URL to use all building/pushing image targets
IMG ?= registry.jihulab.com/jashbook/hzs-test
VERSION ?= latest
CHART_PATH=deploy/helm


GO ?= go
GOOS ?= $(shell $(GO) env GOOS)
GOARCH ?= $(shell $(GO) env GOARCH)
# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell $(GO) env GOBIN))
GOBIN=$(shell $(GO) env GOPATH)/bin
else
GOBIN=$(shell $(GO) env GOBIN)
endif

export GONOPROXY=jihulab.com/infracreate
export GONOSUMDB=jihulab.com/infracreate
export GOPRIVATE=jihulab.com/infracreate
## 中国地域需要 GOPROXY
export GOPROXY=https://goproxy.cn


# Go module support: set `-mod=vendor` to use the vendored sources.
# See also hack/make.sh.
ifeq ($(shell go help mod >/dev/null 2>&1 && echo true), true)
  GO:=GO111MODULE=on $(GO)
  MOD_VENDOR=-mod=vendor
endif

ifneq ($(BUILDX_ENABLED), false)
	ifeq ($(shell docker buildx inspect 2>/dev/null | awk '/Status/ { print $$2 }'), running)
		BUILDX_ENABLED ?= true
	else
		BUILDX_ENABLED ?= false
	endif
endif

define BUILDX_ERROR
buildx not enabled, refusing to run this recipe
endef

# Which architecture to build - see $(ALL_ARCH) for options.
# if the 'local' rule is being run, detect the ARCH from 'go env'
# if it wasn't specified by the caller.
local : ARCH ?= $(shell go env GOOS)-$(shell go env GOARCH)
ARCH ?= linux-amd64


# BUILDX_PLATFORMS ?= $(subst -,/,$(ARCH))
BUILDX_PLATFORMS ?= linux/amd64,linux/arm64
BUILDX_OUTPUT_TYPE ?= docker

LD_FLAGS="-s -w -X main.version=v${VERSION} -X main.buildDate=`date -u +'%Y-%m-%dT%H:%M:%SZ'` -X main.gitCommit=`git rev-parse HEAD`"

TAG_LATEST ?= false

ifeq ($(TAG_LATEST), true)
	IMAGE_TAGS ?= $(IMG):$(VERSION) $(IMG):latest
else
	IMAGE_TAGS ?= $(IMG):$(VERSION)
endif



.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases
	@cp config/crd/bases/* deploy/helm/crds/

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	$(GO) fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	$(GO) vet ./...

.PHONY: lint
lint: ## Run golangci-lint against code.
	golangci-lint run ./... --timeout=5m

.PHONY: staticcheck
staticcheck: ## Run staticcheck against code. 
	staticcheck ./...

.PHONY: mod-download
mod-download: ## Run go mod download against go modules.
	$(GO) mod download

.PHONY: mod-vendor
mod-vendor: ## Run go mod tidy->vendor->verify against go modules.
	$(GO) mod tidy
	$(GO) mod vendor
	$(GO) mod verify


.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" go test ./... -coverprofile cover.out
	go tool cover -html=cover.out -o cover.html
	go tool cover -func=cover.out -o cover_total.out

##@ Build

.PHONY: build
build: generate fmt vet ## Build manager binary.
	go build -ldflags=${LD_FLAGS} -o bin/manager main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

# Run with Delve for development purposes against the configured Kubernetes cluster in ~/.kube/config
# Delve is a debugger for the Go programming language. More info: https://github.com/go-delve/delve
run-delve: manifests generate fmt vet 
	go build -gcflags "all=-trimpath=$(shell go env GOPATH)" -o bin/manager main.go
	dlv --listen=:2345 --headless=true --api-version=2 --accept-multiclient exec ./bin/manager


.PHONY: docker-build
docker-build: ## test ## Build docker image with the manager.
ifneq ($(BUILDX_ENABLED), true)
	DOCKER_BUILDKIT=1 docker build . -t ${IMG}:${VERSION} 
else
	docker buildx build . --pull --platform $(BUILDX_PLATFORMS) -t ${IMG}:${VERSION}
endif



.PHONY: docker-push
docker-push: ## Push docker image with the manager.
ifneq ($(BUILDX_ENABLED), true)
	docker push ${IMG}:${VERSION}
else
	docker buildx build . --pull --platform $(BUILDX_PLATFORMS) -t ${IMG}:${VERSION} --push
endif

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: dry-run
dry-run: manifests kustomize
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	mkdir -p dry-run
	$(KUSTOMIZE) build config/default > dry-run/manifests.yaml

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: bump-chart-version
bump-chart-version: ## Bump helm chart version
	sed -i '' "s/^version:.*/version: $(VERSION)/" $(CHART_PATH)/Chart.yaml
	sed -i '' "s/^appVersion:.*/appVersion: $(VERSION)/" $(CHART_PATH)/Chart.yaml

.PHONY: helm-package
helm-package: bump-chart-version # Do helm package
	helm package $(CHART_PATH)



##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v3.8.7
CONTROLLER_TOOLS_VERSION ?= v0.9.0

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	#curl -s $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest


.PHONY: docker-buildx
docker-buildx:
	docker buildx create --platform linux/amd64,linux/arm64 --name x-builder --driver docker-container --use

## Dependencies

.PHONY: mac-install-prerequisite
mac-install-prerequisite:
	brew install docker --cask
	brew install k3d go kubebuilder delve golangci-lint staticcheck kustomize


.PHONY: check-cover
check-cover:
	python3 /datatestsuites/infratest.py -t 0 -c filepath:./cover_total.out,percent:60%


.PHONY: helm-test-local
helm-test-local:
	helm upgrade --install --create-namespace kube-operator deploy/helm -n github-runner  -f ./deploy/helm/ci/ci-values.yaml --kubeconfig=.github/kubeconfig
	helm test kube-operator -n github-runner --logs --kubeconfig=.github/kubeconfig
	helm uninstall kube-operator -n github-runner --kubeconfig=.github/kubeconfig

.PHONY: helm-test
helm-test:
	helm upgrade --install --create-namespace kube-operator deploy/helm -n github-runner  -f ./deploy/helm/ci/ci-values.yaml
	helm test kube-operator -n github-runner --logs
	helm uninstall kube-operator -n github-runner


.PHONY: minikube
minikube: ## Download minikube locally if necessary.
ifeq (, $(shell which minikube))
	@{ \
	set -e ;\
	echo 'installing minikube' ;\
	curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-$(GOOS)-$(GOARCH) && chmod +x minikube && sudo mv minikube /usr/local/bin ;\
	echo 'Successfully installed' ;\
	}
endif
MINIKUBE=$(shell which minikube)


.PHONY: brew-install-prerequisite
brew-install-prerequisite: ## Use `brew install` to install required dependencies.
	brew install go@1.19 kubebuilder delve golangci-lint staticcheck kustomize step cue oras jq yq git-hooks-go

##@ Minikube
K8S_VERSION ?= v1.22.15
MINIKUBE_REGISTRY_MIRROR ?= https://tenxhptk.mirror.aliyuncs.com
MINIKUBE_IMAGE_REPO ?= registry.cn-hangzhou.aliyuncs.com/google_containers
MINIKUBE_START_ARGS = --memory=4g --cpus=4

KICBASE_IMG=$(MINIKUBE_IMAGE_REPO)/kicbase:v0.0.33
PAUSE_IMG=$(MINIKUBE_IMAGE_REPO)/pause:3.5
METRICS_SERVER_IMG=$(MINIKUBE_IMAGE_REPO)/metrics-server:v0.6.1
CSI_PROVISIONER_IMG=$(MINIKUBE_IMAGE_REPO)/csi-provisioner:v2.1.0
CSI_ATTACHER_IMG=$(MINIKUBE_IMAGE_REPO)/csi-attacher:v3.1.0
CSI_EXT_HMC_IMG=$(MINIKUBE_IMAGE_REPO)/csi-external-health-monitor-controller:v0.2.0
CSI_EXT_HMA_IMG=$(MINIKUBE_IMAGE_REPO)/csi-external-health-monitor-agent:v0.2.0
CSI_NODE_DRIVER_REG_IMG=$(MINIKUBE_IMAGE_REPO)/csi-node-driver-registrar:v2.0.1
LIVENESSPROBE_IMG=$(MINIKUBE_IMAGE_REPO)/livenessprobe:v2.2.0
CSI_RESIZER_IMG=$(MINIKUBE_IMAGE_REPO)/csi-resizer:v1.1.0
CSI_SNAPSHOTTER_IMG=$(MINIKUBE_IMAGE_REPO)/csi-snapshotter:v4.0.0
HOSTPATHPLUGIN_IMG=$(MINIKUBE_IMAGE_REPO)/hostpathplugin:v1.6.0
STORAGE_PROVISIONER_IMG=$(MINIKUBE_IMAGE_REPO)/storage-provisioner:v5
SNAPSHOT_CONTROLLER_IMG=$(MINIKUBE_IMAGE_REPO)/snapshot-controller:v4.0.0

.PHONY: pull-all-images
pull-all-images: # Pull required container images
	docker pull -q $(PAUSE_IMG) &
	docker pull -q $(HOSTPATHPLUGIN_IMG) &
	docker pull -q $(LIVENESSPROBE_IMG) &
	docker pull -q $(CSI_PROVISIONER_IMG) &
	docker pull -q $(CSI_ATTACHER_IMG) &
	docker pull -q $(CSI_RESIZER_IMG) &
	docker pull -q $(CSI_RESIZER_IMG) &
	docker pull -q $(CSI_SNAPSHOTTER_IMG) &
	docker pull -q $(SNAPSHOT_CONTROLLER_IMG) &
	docker pull -q $(CSI_EXT_HMC_IMG) &
	docker pull -q $(CSI_NODE_DRIVER_REG_IMG) &
	docker pull -q $(STORAGE_PROVISIONER_IMG) &
	docker pull -q $(METRICS_SERVER_IMG) &
	docker pull -q $(KICBASE_IMG)

.PHONY: minikube-start
# minikube-start: IMG_CACHE_CMD=ssh --native-ssh=false docker pull
minikube-start: IMG_CACHE_CMD=image load --daemon=true
minikube-start: pull-all-images minikube ## Start minikube cluster.
ifneq (, $(shell which minikube))
ifeq (, $(shell $(MINIKUBE) status -n minikube -ojson | jq -r '.Host' | grep Running))
	$(MINIKUBE) start --kubernetes-version=$(K8S_VERSION) --registry-mirror=$(REGISTRY_MIRROR) --image-repository=$(MINIKUBE_IMAGE_REPO) $(MINIKUBE_START_ARGS)
endif
endif
	$(MINIKUBE) update-context
	$(MINIKUBE) $(IMG_CACHE_CMD) $(HOSTPATHPLUGIN_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(LIVENESSPROBE_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_PROVISIONER_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_ATTACHER_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_RESIZER_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_SNAPSHOTTER_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_EXT_HMA_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_EXT_HMC_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(CSI_NODE_DRIVER_REG_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(STORAGE_PROVISIONER_IMG)
	$(MINIKUBE) $(IMG_CACHE_CMD) $(METRICS_SERVER_IMG)
	$(MINIKUBE) addons enable metrics-server
	$(MINIKUBE) addons enable volumesnapshots
	$(MINIKUBE) addons enable csi-hostpath-driver
	kubectl patch storageclass standard -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
	kubectl patch storageclass csi-hostpath-sc -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
	kubectl patch volumesnapshotclass/csi-hostpath-snapclass --type=merge -p '{"metadata": {"annotations": {"snapshot.storage.kubernetes.io/is-default-class": "true"}}}'


.PHONY: minikube-delete
minikube-delete: minikube ## Delete minikube cluster.
	$(MINIKUBE) delete