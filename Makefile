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
#   make size    print the line counts and enforce the two budgets
#
# A Makefile is not a .sh file, so it does not count against the shell budget.
# That is not a loophole to exploit: logic belongs in lib/ where shellcheck and
# the tests can see it. This file only calls things.

# Scripts that ship to a user's machine. Tests are checked too, but separately:
# shfmt formats the bats helper, and bats checks the rest.
SHIPPED := install.sh bin/dot lib/*.sh core/*.sh modules/*/apply.sh modules/*/doctor.sh
FORMATTED := install.sh bin/dot lib/*.sh core/*.sh modules/*/*.sh tests/helper.bash

# shfmt: 2-space indent, and indent the bodies of case statements.
SHFMT_FLAGS := -i 2 -ci

# TWO budgets, not one. v1 reached ~20,700 lines and the single 1500-line cap
# that replaced it was right about the danger and wrong about where it lives.
#
# The ENGINE -- install.sh, bin/dot, lib/, core/ -- is the part v1 rotted in,
# and it is finished: it knows how to link a file, read a config and run a
# hook, and none of those get harder as you own more things. Its cap is tight
# enough that growing it has to be a deliberate act rather than a drift.
#
# MODULES are the axis this repo is meant to grow along. One more thing you own
# is one more directory, and a shared pool would make the tenth module compete
# for room with an engine that does not need it -- which is a rule that tells
# you to delete working code for owning a laptop properly. So their sum is
# reported and not capped.
#
# What a module must never become is v1's feature.sh, so each is capped ON ITS
# OWN. 150 lines is roughly twice the biggest one here: enough for an apply and
# a doctor with comments, not enough for a subsystem. A module that wants more
# is either two modules, or one that belongs in the engine.
ENGINE_BUDGET := 1300
MODULE_BUDGET := 150

# The engine is listed rather than found: it is a closed set, and the point of
# the cap is that adding a file to it is a decision someone makes here, in the
# open. Modules are the opposite -- found by glob, because the directory
# listing is the registry and a new one must never need an edit in this file.
ENGINE := install.sh bin/dot lib/*.sh core/*.sh

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
	@over=0; \
	engine=$$(wc -l $(ENGINE) | tail -1 | awk '{print $$1}'); \
	if [ "$$engine" -gt $(ENGINE_BUDGET) ]; then \
	  echo "    engine:   $$engine lines -- OVER the $(ENGINE_BUDGET)-line budget" >&2; \
	  over=1; \
	else \
	  echo "    engine:   $$engine lines (budget $(ENGINE_BUDGET))"; \
	fi; \
	modules=0; \
	for dir in modules/*/; do \
	  name=$$(basename "$$dir"); \
	  n=$$(cat "$$dir"*.sh 2>/dev/null | wc -l | tr -d ' '); \
	  modules=$$((modules + n)); \
	  if [ "$$n" -gt $(MODULE_BUDGET) ]; then \
	    echo "      $$name: $$n lines -- OVER the $(MODULE_BUDGET)-line cap" >&2; \
	    over=1; \
	  elif [ "$$n" -gt 0 ]; then \
	    echo "      $$name: $$n"; \
	  fi; \
	done; \
	echo "    modules:  $$modules lines (each capped at $(MODULE_BUDGET); the sum is not)"; \
	tests=$$(find tests -type f | xargs wc -l | tail -1 | awk '{print $$1}'); \
	echo "    tests:    $$tests lines (uncapped)"; \
	if [ "$$over" -ne 0 ]; then \
	  echo "    cut something, or move it -- do not raise the number." >&2; \
	  exit 1; \
	fi
