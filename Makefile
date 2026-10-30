IMAGE ?= pp-api
VERSION ?= dev

.PHONY: build lint test up down ci help
build: ## build the image IMAGE:VERSION (pp-api:dev by default)
	docker build -t $(IMAGE):$(VERSION) app

lint: ## shellcheck, hadolint, go vet, actionlint and gitleaks
	shellcheck scripts/*.sh
	hadolint app/Dockerfile
	cd app && go vet ./...
	docker run --rm -v "$(CURDIR):/repo" -w /repo rhysd/actionlint:1.7.12
	docker run --rm -v "$(CURDIR):/repo" -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1 git --redact --no-banner .

test: ## run the Go tests
	cd app && go test ./...

ci: lint test build ## lint, test and build, the same checks CI runs

up: ## build the images and start the stack in the background
	docker compose up -d --build

down: ## stop the stack and remove its containers (the data stays)
	docker compose down

help: ## list the targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-8s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

