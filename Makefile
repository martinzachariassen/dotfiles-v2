# Every check this repo runs, in one place.
#
# CI, the README and CLAUDE.md all used to spell out the same shellcheck and
# shfmt invocations, and they had already drifted -- the README linted fewer
# files than CI did. Now they all say `make check`, and this file is the only
# copy of the actual commands.
#
#   make check   everything below, in order (this is what CI runs)
#   make lint    shellcheck
#   make fmt     rewrite files to the project's formatting
#   make test    the bats suite
#   make size    print the line count and enforce the budget
#
# A Makefile is not a .sh file, so it does not count against the 1500-line
# shell budget. That is not a loophole to exploit: logic belongs in lib/ where
# shellcheck and the tests can see it. This file only calls things.

# Scripts that ship to a user's machine. Tests are checked too, but separately:
# shfmt formats the bats helper, and bats checks the rest.
SHIPPED := install.sh bin/dot lib/*.sh core/*.sh modules/*/apply.sh modules/*/doctor.sh
FORMATTED := install.sh bin/dot lib/*.sh core/*.sh modules/*/*.sh tests/helper.bash

# shfmt: 2-space indent, and indent the bodies of case statements.
SHFMT_FLAGS := -i 2 -ci

# The budget exists because v1 reached ~20,700 lines. Going over is a signal to
# cut something, not to raise the number.
BUDGET := 1500

# Every shipped script, found rather than listed, so a new one is counted
# without anyone remembering to add it here. `dot` is named explicitly because
# it is the one shipped script with no .sh extension.
FIND_SHIPPED := find . -path ./.git -prune -o -path ./tests -prune -o \
  \( -name '*.sh' -o -name 'dot' \) -type f -print

.PHONY: check lint fmt fmt-check test size

check: lint fmt-check test size

lint:
	@echo "==> shellcheck"
	@shellcheck -x $(SHIPPED)

# Rewrites files in place. Run this; `make check` only reports.
fmt:
	@echo "==> shfmt (writing)"
	@shfmt -w $(SHFMT_FLAGS) $(FORMATTED)

fmt-check:
	@echo "==> shfmt"
	@shfmt -d $(SHFMT_FLAGS) $(FORMATTED)

test:
	@echo "==> bats"
	@bats tests/

# TESTS ARE EXCLUDED from the budget, deliberately. A budget that counts tests
# is a budget that buys compliance by deleting them, which is the opposite of
# what this repo needs -- lib/fs.sh moves files in $$HOME for a living. Test
# code is reported, never capped.
size:
	@echo "==> size"
	@shipped=$$($(FIND_SHIPPED) | xargs wc -l | tail -1 | awk '{print $$1}'); \
	tests=$$(find tests -type f | xargs wc -l | tail -1 | awk '{print $$1}'); \
	echo "    shipped shell: $$shipped lines (budget $(BUDGET))"; \
	echo "    tests:         $$tests lines (uncapped)"; \
	if [ "$$shipped" -gt $(BUDGET) ]; then \
	  echo "    over the $(BUDGET)-line budget -- cut something." >&2; \
	  exit 1; \
	fi
