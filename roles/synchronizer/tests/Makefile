BATS      := bats
TESTS_DIR := .

.PHONY: test test-verbose all

all: test

test:
	$(BATS) $(TESTS_DIR)/*.bats

test-verbose:
	$(BATS) --verbose-run $(TESTS_DIR)/*.bats

test-notify:
	$(BATS) $(TESTS_DIR)/notify.bats

test-adapters:
	$(BATS) $(TESTS_DIR)/adapters.bats

test-templates:
	$(BATS) $(TESTS_DIR)/templates.bats
