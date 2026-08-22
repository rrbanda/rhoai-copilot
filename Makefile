IMAGE ?= quay.io/rbrhssa/rhoai-copilot
TAG ?= latest
RUNTIME ?= hermes
NAMESPACE ?= rhoai-copilot

.PHONY: validate build deploy eval clean

validate:
	@echo "=== Validating skills ==="
	@errors=0; \
	for skill in $$(find skills -name "SKILL.md" -not -path "skills/_template/*"); do \
		for section in "Description" "Trigger Conditions" "Required MCP Tools" "Procedure" "Output Format" "Safety Constraints"; do \
			if ! grep -q "## $$section" "$$skill"; then \
				echo "ERROR: $$skill missing '## $$section'"; \
				errors=$$((errors + 1)); \
			fi; \
		done; \
	done; \
	if [ $$errors -gt 0 ]; then echo "$$errors errors found"; exit 1; fi
	@echo "All skills valid"

build:
	podman build --platform linux/amd64 \
		-t $(IMAGE):$(TAG) \
		-f runtimes/$(RUNTIME)/Containerfile .

push: build
	podman push $(IMAGE):$(TAG)

deploy:
	oc apply -k runtimes/$(RUNTIME)/

undeploy:
	oc delete -k runtimes/$(RUNTIME)/ --ignore-not-found

eval:
	@echo "=== Running evaluation scenarios ==="
	@echo "TODO: Implement automated eval runner"
	@ls eval/scenarios/*.yaml | wc -l | xargs -I{} echo "{} scenarios available"

clean:
	rm -rf _output/
