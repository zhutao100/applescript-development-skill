.PHONY: compile policy test run integration-vm

compile:
	./scripts/compile.sh

policy:
	./scripts/policy_scan.sh --src ./src

test:
	./scripts/test_unit.sh

run:
	./scripts/run.sh

# Requires: Tart installed on the host.
# Usage: make integration-vm [BASE=<golden-vm-or-image-ref>]
integration-vm:
	if [ -n "$(BASE)" ]; then ./scripts/test_integration_vm_tart.sh --base "$(BASE)"; else ./scripts/test_integration_vm_tart.sh; fi
