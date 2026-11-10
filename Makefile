########################################################################
#                                                                      #
#                               Makefile                               #
#                                                                      #
########################################################################
# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# One command for each routine task: install the checks, check, test,
# audit, and format and validate the Terraform. CI runs the same
# targets. Applying the Terraform is infra/snowflake.sh's job, from AWS
# CloudShell, never from here.
########################################################################
#                                                                      #
#                           Local constants                            #
#                                                                      #
########################################################################
UV := uv run --no-sync
# Our own packages install from git, not PyPI, so the PyPI audit leaves them out.
KDS := kds-args kds-settings kds-logs kds-standards
AUDIT_FILE := .cache/requirements-audit.txt
ROOTS := infra/snowflake

########################################################################
#                                                                      #
#                            Routine tasks                             #
#                                                                      #
########################################################################
.PHONY: install check test audit fmt validate

install:  ## The checks' environment, from uv.lock
	uv sync --locked

check:  ## Lint, format, strict types and the code standard
	$(UV) ruff check .
	$(UV) ruff format --check .
	$(UV) mypy
	$(UV) kds-standards check .

test:  ## The Terraform read and checked without a cloud account
	$(UV) pytest

audit:  ## Known vulnerabilities in every locked dependency
	mkdir -p .cache
	uv export --locked --all-groups --no-emit-project \
		$(addprefix --no-emit-package ,$(KDS)) --format requirements.txt -o $(AUDIT_FILE) --quiet
	$(UV) pip-audit --strict --require-hashes --disable-pip -r $(AUDIT_FILE)

fmt:  ## Terraform's own format, written in place; needs Terraform
	terraform fmt -recursive infra

validate:  ## Each root against its providers' schemas, with no state; needs Terraform
	for root in $(ROOTS); do \
		terraform -chdir="$$root" init -backend=false -input=false && \
		terraform -chdir="$$root" validate || exit 1; \
	done
