IMAGE ?= pp-api
WEB_IMAGE ?= pp-web
VERSION ?= dev

.PHONY: build lint test scan up down ci help
build: ## build the images IMAGE:VERSION and WEB_IMAGE:VERSION (pp-api:dev and pp-web:dev by default)
	docker build -t $(IMAGE):$(VERSION) app
	docker build -t $(WEB_IMAGE):$(VERSION) web

lint: ## shellcheck, hadolint, go vet, jq, promtool, amtool, actionlint and gitleaks
	shellcheck scripts/*.sh deploy/*.sh
	hadolint app/Dockerfile web/Dockerfile
	cd app && go vet ./...
	jq empty infra/policies/*.json
	docker run --rm --entrypoint promtool -v "$(CURDIR)/observability:/etc/prometheus:ro" prom/prometheus:v3.15.1 check config /etc/prometheus/prometheus.yml
	docker run --rm --entrypoint promtool -v "$(CURDIR)/observability:/etc/prometheus:ro" prom/prometheus:v3.15.1 test rules /etc/prometheus/alerts.test.yml
	docker run --rm --entrypoint amtool -v "$(CURDIR)/observability:/etc/alertmanager:ro" prom/alertmanager:v0.34.2 check-config /etc/alertmanager/alertmanager.yml
	docker run --rm -v "$(CURDIR):/repo" -w /repo rhysd/actionlint:1.7.12
	docker run --rm -v "$(CURDIR):/repo" -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1 git --redact --no-banner .

test: ## run the Go tests
	cd app && go test ./...

scan: ## stop on a CRITICAL vulnerability in the two images (trivy)
	trivy image --severity CRITICAL --exit-code 1 $(IMAGE):$(VERSION)
	trivy image --severity CRITICAL --exit-code 1 $(WEB_IMAGE):$(VERSION)

ci: lint test build scan ## lint, test, build and scan, the same checks CI runs

# Docker would make a folder owned by root where a mounted file is missing, so a
# fresh clone gets an empty discord.url first.
up: ## build the images and start the stack in the background
	@test -e observability/discord.url || { touch observability/discord.url; echo "observability/discord.url was missing: made it empty, so Alertmanager runs but sends nothing (see docs/observability.md)"; }
	docker compose up -d --build

down: ## stop the stack and remove its containers (the data stays)
	docker compose down

help: ## list the targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  %-8s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

