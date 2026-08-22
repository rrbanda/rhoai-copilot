IMAGE ?= quay.io/rbrhssa/rhoai-copilot
TAG ?= latest
RUNTIME ?= hermes
NAMESPACE ?= rhoai-copilot

.PHONY: validate build push deploy deploy-mcp deploy-all undeploy status eval clean

## --- Validation ---

validate:
	@echo "=== Validating skills ==="
	@errors=0; \
	for skill in $$(find skills -name "SKILL.md" -not -path "skills/_template/*"); do \
		if ! head -1 "$$skill" | grep -q "^---"; then \
			echo "ERROR: $$skill missing YAML frontmatter (must start with ---)"; \
			errors=$$((errors + 1)); \
		fi; \
		if ! grep -q "^name:\|^skill:" "$$skill"; then \
			echo "ERROR: $$skill missing 'name:' or 'skill:' in frontmatter"; \
			errors=$$((errors + 1)); \
		fi; \
		if ! grep -q "^description:" "$$skill"; then \
			echo "ERROR: $$skill missing 'description:' in frontmatter"; \
			errors=$$((errors + 1)); \
		fi; \
		if ! grep -qi "## .*procedure\|## .*steps\|## .*step-by-step\|## .*automation\|## .*step 1\|## .*phase [0-9]" "$$skill"; then \
			echo "ERROR: $$skill missing procedure/steps section"; \
			errors=$$((errors + 1)); \
		fi; \
	done; \
	if [ $$errors -gt 0 ]; then echo "$$errors errors found"; exit 1; fi
	@echo "All $$(find skills -name 'SKILL.md' -not -path 'skills/_template/*' | wc -l) skills valid"

## --- Build ---

build:
	podman build --platform linux/amd64 \
		-t $(IMAGE):$(TAG) \
		-f runtimes/$(RUNTIME)/Containerfile .

push: build
	podman push $(IMAGE):$(TAG)

## --- Deploy ---

deploy:
	oc apply -k .

undeploy:
	oc delete -k . --ignore-not-found

## --- Operations ---

status:
	@echo "=== Agent Pod ==="
	@oc get pods -n $(NAMESPACE) -l app=rhoai-copilot 2>/dev/null || echo "Not deployed"
	@echo ""
	@echo "=== RHOAI MCP Pod ==="
	@oc get pods -n $(NAMESPACE) -l app=rhoai-mcp 2>/dev/null || echo "Not deployed"
	@echo ""
	@echo "=== Route ==="
	@oc get route rhoai-copilot -n $(NAMESPACE) -o jsonpath='https://{.spec.host}' 2>/dev/null && echo "" || echo "Not deployed"

logs:
	oc logs deployment/rhoai-copilot -n $(NAMESPACE) --tail=50

restart:
	oc rollout restart deployment/rhoai-copilot -n $(NAMESPACE)

## --- Evaluation ---

eval:
	@python3 eval/run_eval.py --list
	@echo ""
	@python3 eval/run_eval.py --output eval/results/report-$$(date +%Y%m%d).md
	@echo "=== Report generated ==="

eval-list:
	@python3 eval/run_eval.py --list

eval-report:
	@mkdir -p eval/results
	@python3 eval/run_eval.py --output eval/results/report-$$(date +%Y%m%d).md

eval-persona:
	@python3 eval/run_eval.py --persona $(PERSONA)

eval-phase:
	@python3 eval/run_eval.py --phase $(PHASE)

eval-score:
	@python3 eval/run_eval.py --mode=score

## --- Cleanup ---

clean:
	rm -rf _output/

## --- Help ---

help:
	@echo "RHOAI Copilot Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make build        Build agent image (linux/amd64)"
	@echo "  make push         Build and push to registry"
	@echo "  make deploy       Deploy agent + RHOAI MCP (Kustomize)"
	@echo "  make undeploy     Remove all components"
	@echo "  make status       Check deployment status"
	@echo "  make logs         Tail agent logs"
	@echo "  make restart      Restart agent pod"
	@echo "  make validate     Validate all skills"
	@echo ""
	@echo "Configuration:"
	@echo "  IMAGE=$(IMAGE)"
	@echo "  TAG=$(TAG)"
	@echo "  NAMESPACE=$(NAMESPACE)"
	@echo "  RUNTIME=$(RUNTIME)"
