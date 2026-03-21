#!/usr/bin/env bash
# Validate Template — проверка целостности FMT-exocortex-template
# Targets: Linux, macOS
#
# 5 проверок:
# 1. Нет автор-специфичного контента
# 2. Нет захардкоженных путей /Users/
# 3. Нет захардкоженных путей /opt/homebrew
# 4. MEMORY.md — скелет (мало строк в РП-таблице)
# 5. Обязательные файлы существуют

set -euo pipefail

TEMPLATE_DIR="${1:-$HOME/IWE/FMT-exocortex-template}"
FAIL=0

# shellcheck source=setup/lib/lib-validate-template.sh
source "$(cd "$(dirname "$0")/.." && pwd)/setup/lib/lib-validate-template.sh"

echo "=== Validating: $TEMPLATE_DIR ==="

validate_template_check_author_content "$TEMPLATE_DIR" || FAIL=1
validate_template_check_users_paths "$TEMPLATE_DIR" || FAIL=1
validate_template_check_homebrew_paths "$TEMPLATE_DIR" || FAIL=1
validate_template_check_memory_skeleton "$TEMPLATE_DIR" || FAIL=1
validate_template_check_required_files "$TEMPLATE_DIR" || FAIL=1

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "=== ALL CHECKS PASSED ==="
    exit 0
else
    echo "=== VALIDATION FAILED ==="
    exit 1
fi
