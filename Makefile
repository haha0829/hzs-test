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