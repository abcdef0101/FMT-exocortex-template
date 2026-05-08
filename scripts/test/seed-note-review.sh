#!/usr/bin/env bash
# seed-note-review.sh — создаёт workspace с заметками для Note Review E2E
# Usage: bash scripts/test/seed-note-review.sh [target_dir]
set -euo pipefail

TARGET="${1:-$(mktemp -d -t notereview-seed-XXXXXX)}"
mkdir -p "$TARGET/DS-strategy/"{inbox,docs,current}
mkdir -p "$TARGET/memory"

# fleeting-notes: 7 заметок разных типов
cat > "$TARGET/DS-strategy/inbox/fleeting-notes.md" <<'EOFN'
# Fleeting Notes

## Bold (новые — требуют классификации)

**Тесты слишком долгие, CI ждать по 3 минуты**
Это замедляет разработку, нужно ускорить пайплайн.

**Добавить ShellCheck в pre-commit hook**
Простейший способ поймать bash-ошибки до CI.

**FPF SOTA.002 про Context Engineering очень релевантен для нашей архитектуры**
Стоит задокументировать как принцип в Pack.

**setup.sh на macOS не создаёт workspace если нет brew**
Нужно добавить fallback для Mac без Homebrew.

**Написать пост про тестовое покрытие IWE**
Можно в клубный канал, тема актуальная после аудита.

**Заметка без особого смысла, просто мысли вслух о погоде**

## Processed (обработанные ранее)
- ~~Старая заметка про Git workflow~~ Обработано W13
EOFN

# Strategy + Dissatisfactions + WeekPlan (контекст для классификации)
cat > "$TARGET/DS-strategy/docs/Strategy.md" <<'EOST'
# Strategy
## Приоритеты месяца
- P1: Test coverage
- P2: CI speed
- P3: Content (2 posts/week)
EOST

cat > "$TARGET/DS-strategy/docs/Dissatisfactions.md" <<'EODS'
# Dissatisfactions
| ID | Описание | Статус |
|----|----------|--------|
| NEP1 | CI slow | active |
EODS

cat > "$TARGET/DS-strategy/current/WeekPlan W14 2026.md" <<'EOWP'
# WeekPlan W14
## План на неделю
| # | РП | Статус | Бюджет |
|---|-----|--------|--------|
| 1 | Test audit | done | 8h |
| 2 | CI gates | done | 4h |
EOWP

cat > "$TARGET/memory/MEMORY.md" <<'EOMEM'
# MEMORY.md
valid_from: 2026-04-01
## РП текущей недели
| # | Название | Статус |
|---|----------|--------|
| 1 | Test audit | done |
| 2 | CI gates | done |
EOMEM

cd "$TARGET"
git init --quiet 2>/dev/null || true
git add -A >/dev/null 2>&1 || true
git commit -m "seed: Note Review test data" --quiet 2>/dev/null || true

echo "$TARGET"
