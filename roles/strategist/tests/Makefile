BATS      := bats
TESTS_DIR := .
SCRIPTS   := ../scripts

.PHONY: test test-verbose test-tap lint clean

# Запуск всех тестов
test:
	$(BATS) $(TESTS_DIR)/*.bats

# Подробный вывод
test-verbose:
	$(BATS) --verbose-run $(TESTS_DIR)/*.bats

# TAP-формат (для CI)
test-tap:
	$(BATS) --formatter tap $(TESTS_DIR)/*.bats

# Линтинг скриптов
lint:
	shellcheck $(SCRIPTS)/*.sh

# Очистка временных файлов
clean:
	rm -rf /tmp/bats-*
