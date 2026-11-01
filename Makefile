IMAGE ?= pp-api
WEB_IMAGE ?= pp-web
VERSION ?= dev

.PHONY: build lint test scan up down ci help
build: ## build the images IMAGE:VERSION and WEB_IMAGE:VERSION (pp-api:dev and pp-web:dev by default)
	docker build -t $(IMAGE):$(VERSION) app
	docker build -t $(WEB_IMAGE):$(VERSION) web

lint: ## shellcheck, hadolint, go vet, actionlint and gitleaks
	shellcheck scripts/*.sh
	hadolint app/Dockerfile web/Dockerfile
	cd app && go vet ./...
	docker run --rm -v "$(CURDIR):/repo" -w /repo rhysd/actionlint:1.7.12
	docker run --rm -v "$(CURDIR):/repo" -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1 git --redact --no-banner .

test: ## run the Go tests
	cd app && go test ./...

scan: ## stop on a CRITICAL vulnerability in the two images (trivy)
	trivy image --severity CRITICAL --exit-code 1 $(IMAGE):$(VERSION)
	trivy image --severity CRITICAL --exit-code 1 $(WEB_IMAGE):$(VERSION)

ci: lint test build scan ## lint, test, build and scan, the same checks CI runs

up: ## build the images and start the stack in the background
	docker compose up -d --build

down: ## stop the stack and remove its containers (the data stays)
	docker compose down

help: ## list the targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-8s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

