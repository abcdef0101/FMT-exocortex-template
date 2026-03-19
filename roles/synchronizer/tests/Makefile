BATS      := bats
TESTS_DIR := .
SCRIPTS   := ../scripts

.PHONY: test test-verbose lint clean

test:
	$(BATS) $(TESTS_DIR)/*.bats

test-verbose:
	$(BATS) --verbose-run $(TESTS_DIR)/*.bats

lint:
	shellcheck $(SCRIPTS)/*.sh

clean:
	rm -rf /tmp/bats-*
