SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:

# --- defaults ---
SLUG ?=
DOMAIN ?=
PROVIDER ?= hetzner
TF_DIR := infra
COMPOSE_DIR := compose

# --- discovery ---
.PHONY: help
help:
	@echo "self-contained-agent-base — make targets"
	@echo ""
	@echo "  make fmt              # format Terraform + shell"
	@echo "  make lint             # validate Terraform + shellcheck"
	@echo "  make plan             # terraform plan (requires SLUG=, DOMAIN=)"
	@echo "  make apply            # terraform apply"
	@echo "  make destroy          # terraform destroy"
	@echo "  make deploy           # full deploy-client wrapper"
	@echo "  make smoke            # run smoke-test.sh against deployed FQDN"
	@echo "  make local-up         # bring up compose locally (self-signed)"
	@echo "  make local-down       # tear down local compose"
	@echo ""
	@echo "Required env: CLOUDFLARE_API_TOKEN plus HCLOUD_TOKEN or VULTR_API_KEY"
	@echo "Required vars for plan/apply/deploy: SLUG=<slug> DOMAIN=<example.com> [PROVIDER=hetzner|vultr]"

# --- formatting / linting ---
.PHONY: fmt
fmt:
	terraform -chdir=$(TF_DIR) fmt -recursive
	@if command -v shfmt >/dev/null 2>&1; then \
	  shfmt -w -i 2 -ci bin/ scripts/; \
	else \
	  echo "shfmt not installed — skipping shell format"; \
	fi

.PHONY: lint
lint:
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	terraform -chdir=$(TF_DIR) validate
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck bin/deploy-client bin/destroy-client bin/lib/*.sh scripts/*.sh; \
	else \
	  echo "shellcheck not installed — skipping shell lint"; \
	fi

# --- terraform lifecycle ---
.PHONY: init
init:
	terraform -chdir=$(TF_DIR) init

.PHONY: plan
plan: _require_slug_domain init
	terraform -chdir=$(TF_DIR) plan -var "slug=$(SLUG)" -var "domain=$(DOMAIN)" -var "vps_provider=$(PROVIDER)"

.PHONY: apply
apply: _require_slug_domain init
	terraform -chdir=$(TF_DIR) apply -auto-approve -var "slug=$(SLUG)" -var "domain=$(DOMAIN)" -var "vps_provider=$(PROVIDER)"

.PHONY: destroy
destroy: _require_slug_domain
	terraform -chdir=$(TF_DIR) destroy -auto-approve -var "slug=$(SLUG)" -var "domain=$(DOMAIN)" -var "vps_provider=$(PROVIDER)"

# --- top-level deploy wrapper ---
.PHONY: deploy
deploy: _require_slug_domain
	./bin/deploy-client $(SLUG) --domain $(DOMAIN) --provider $(PROVIDER)

.PHONY: smoke
smoke: _require_slug_domain
	./scripts/smoke-test.sh $(SLUG).$(DOMAIN)

# --- local dev ---
.PHONY: local-up
local-up:
	docker compose -f $(COMPOSE_DIR)/docker-compose.yml -f $(COMPOSE_DIR)/docker-compose.local.yml up -d

.PHONY: local-down
local-down:
	docker compose -f $(COMPOSE_DIR)/docker-compose.yml -f $(COMPOSE_DIR)/docker-compose.local.yml down

# --- internal guards ---
.PHONY: _require_slug_domain
_require_slug_domain:
	@if [ -z "$(SLUG)" ] || [ -z "$(DOMAIN)" ]; then \
	  echo "ERROR: SLUG and DOMAIN must be set. Example: make deploy SLUG=acme DOMAIN=example.com"; \
	  exit 1; \
	fi
