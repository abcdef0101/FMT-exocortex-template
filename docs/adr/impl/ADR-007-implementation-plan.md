# ADR-007 Implementation Plan: Golden Image Build Pipeline

> **ADR:** `docs/adr/ADR-007-golden-image-testing.md` (Proposed)
> **SOTA Survey:** `docs/golden-image-survey.md`
> **Created:** 2026-05-04

---

## Цель

Заменить 15-минутный цикл `create-vm.sh → cloud-init → provision.sh` на секундный `test-from-golden.sh (qemu-img create -b golden.qcow2 → ephemeral VM)`.

**KPI:** время создания тестового окружения: 15 мин → <30 сек.

---

## M0: Foundation ✅

| # | Задача | Статус | Артефакт |
|---|--------|:----:|----------|
| 0.1 | SOTA-обзор 6 подходов | ✅ | `docs/golden-image-survey.md` (524 строки, 10 секций) |
| 0.2 | ADR-007 (Proposed) | ✅ | `docs/adr/ADR-007-golden-image-testing.md` (140 строк) |
| 0.3 | Анализ полноты пакетов (Layer 1 + 2) | ✅ | `user-data.yaml`, `packages-firstboot.sh` |
| 0.4 | Существующий VM-инфраструктура | ✅ | `create-vm.sh`, `provision.sh`, `destroy-vm.sh`, `test-phases.sh`, `run-full-test.sh` |
| 0.5 | Test suite (unit + E2E) | ✅ | 14 unit-тестов (`scripts/test/run-phase0.sh`) + 5 E2E (`scripts/test/run-e2e.sh`) |

---

## M1: build-golden.sh — сборка золотого образа

**Срок:** ~2h | **Код:** ~200 строк | **Зависимость:** libguestfs-tools

### 1.1 Создать `scripts/vm/build-golden.sh`

Архитектура (из ADR-007 + survey §8):

```
build-golden.sh [--version 0.25.1] [--force] [--keep-base]
│
├─ Pre-flight: проверить virt-customize, qemu-img, wget
├─ 1. Скачать/проверить кэш базового образа (~600 MB)
│     cache: $HOME/.cache/iwe-golden/noble-server-cloudimg-amd64.img
├─ 2. virt-customize — Слой 1: системные пакеты (офлайн)
│     --install: git, gh, ruby, nodejs, npm, expect, jq, shellcheck,
│                vim, mc, tmux, curl, ca-certificates, gnupg,
│                build-essential, python3, python3-yaml,
│                software-properties-common
│     --run-command: add-apt-repository -y ppa:neovim-ppa/stable
│     --run-command: apt-get update && apt-get install -y neovim
│     --run-command: useradd -m -s /bin/bash iwe + sudoers
│     --run-command: mkdir -p IWE .local/bin .opencode
│     --ssh-inject: iwe:file:$SSH_KEY
│     --copy-in: packages-firstboot.sh:/home/iwe/
│     --firstboot: packages-firstboot.sh
│     --selinux-relabel
├─ 3. qemu-img create -f qcow2 -b base.img -F qcow2 golden.qcow2 20G
├─ 4. qemu-img snapshot -c "provisioned" golden.qcow2
├─ 5. sha256sum golden.qcow2 > golden.qcow2.sha256
└─ 6. Вердикт: размер, список снапшотов, checksum
```

**Ключевые решения:**
- `--force` — перезаписать существующий `iwe-golden-{version}.qcow2`
- `--keep-base` — не удалять базовый образ после сборки
- Версия из `MANIFEST.yaml` (поле `version`) или `--version`
- `SSH_KEY` из `--ssh-key` или `$HOME/.ssh/id_ed25519_iwe_test`
- Ошибки `--install` (libguestfs appliance без сети) — retry с `--network` флагом `virt-customize`

**Проверка:** `bash scripts/vm/build-golden.sh --version 0.25.1` → создан `iwe-golden-0.25.1.qcow2`

### 1.2 Доработать `packages-firstboot.sh` под golden image

Текущий `packages-firstboot.sh` (60 строк) написан для `virt-customize --firstboot`. Адаптации:

- [ ] Обнаружение контекста запуска (firstboot vs manual)
- [ ] `--skip-clone` — если FMT-exocortex-template уже в ~/IWE
- [ ] `--verify-only` — проверить наличие пакетов без установки
- [ ] Таймаут на npm install (30s на пакет) — сеть в VM может быть недоступна

### 1.3 Создать `scripts/vm/verify-golden.sh`

```bash
verify-golden.sh [--image iwe-golden-0.25.1.qcow2] [--quick]

# Проверки:
# 1. qemu-img info: формат qcow2, virtual size 20G, backing file, снапшоты
# 2. sha256sum: совпадает с .sha256 файлом
# 3. guestfish --ro -a image.qcow2:
#    - /etc/os-release содержит "Ubuntu 24.04"
#    - dpkg --list: git, gh, ruby, nodejs, npm, expect, jq, shellcheck,
#                  vim, mc, tmux, neovim, build-essential
#    - id iwe: user exists, uid 1000
#    - /home/iwe/.ssh/authorized_keys: содержит публичный ключ
#    - /home/iwe/packages-firstboot.sh: exists
# 4. (--full) Запустить VM, дождаться SSH:
#    - git --version, node --version, npm --version
#    - ~/IWE/FMT-exocortex-template exists, git branch = 0.25.1
#    - npm list -g --depth=0: claude-code, codex
#    - ls ~/.opencode/bin/opencode
```

### 1.4 Первый прогон и запись результатов

```bash
time bash scripts/vm/build-golden.sh --version 0.25.1
bash scripts/vm/verify-golden.sh --image iwe-golden-0.25.1.qcow2
```

Записать в `scripts/vm/results/golden-build-*.txt`:
- Время сборки (цель: <10 мин)
- Размер золотого образа (цель: <3 GB)
- Количество снапшотов

---

## M2: test-from-golden.sh — быстрый прогон тестов

**Срок:** ~3h | **Код:** ~150 строк | **Зависимость:** M1 (золотой образ готов)

### 2.1 Создать `scripts/vm/test-from-golden.sh`

```
test-from-golden.sh [--version 0.25.1] [--phase N] [--keep] [--port N]
│
├─ 1. Проверить: золотой образ существует + sha256sum
├─ 2. qemu-img create -f qcow2 -b golden.qcow2 -F qcow2 ephemeral_$$.qcow2
│     (copy-on-write — секунды, а не минуты)
├─ 3. Найти свободный порт (2222-2232) для hostfwd
├─ 4. Запуск QEMU:
│     qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
│       -drive file=ephemeral.qcow2,if=virtio \
│       -netdev user,id=net0,hostfwd=tcp::PORT-:22 \
│       -device virtio-net,netdev=net0 \
│       -display none -daemonize
├─ 5. Ожидание SSH (loop: до 30 попыток × 2s)
├─ 6. SSH: загрузить secrets (если есть ~/.iwe-test-vm/secrets/.env)
├─ 7. SSH: source test-phases.sh && run phase N (или все)
├─ 8. Собрать результаты (PASS/FAIL count)
├─ 9. Если --keep: вывести SSH-команду и остановиться
│    Иначе: kill QEMU PID, rm ephemeral.qcow2
└─ 10. Exit code = количество FAIL (0 = все PASS)
```

**Ключевые решения:**
- `--keep` — оставить VM для ручной отладки
- `--phase N` — пройти конкретную фазу (1-4) вместо всех
- `--port N` — фиксированный порт (по умолчанию авто-поиск)
- Поиск свободного порта: `ss -tlnp | grep :2222` → инкремент до 2232
- Сигнал SIGINT/SIGTERM — гарантированная очистка (trap cleanup EXIT)

### 2.2 Интеграция с test-phases.sh

`test-phases.sh` сейчас source'ится из `run-full-test.sh`. Для `test-from-golden.sh`:

- [ ] Добавить `--json-output` режим в test-phases.sh (stdout: JSON lines)
- [ ] `phase3_ai_smoke` — передавать `OPENAI_API_KEY` из host secrets через SSH env
- [ ] Добавить `phase0_smoke` — быстрая проверка (только `setup.sh --validate` + git branch)
- [ ] Результаты писать в `scripts/vm/results/golden-test-{timestamp}.json`

### 2.3 Создать `scripts/vm/benchmark-golden.sh`

Сравнительный замер трёх подходов:

```bash
benchmark-golden.sh
# ┌─────────────────────┬──────────┬──────────┬──────────┐
# │ Подход              │ Прогон 1 │ Прогон 2 │ Прогон 3 │
# ├─────────────────────┼──────────┼──────────┼──────────┤
# │ create-vm+provision │  14:32   │  15:01   │  14:45   │
# │ build-golden (одно) │  06:12   │    —     │    —     │
# │ test-from-golden    │  00:18   │  00:21   │  00:19   │
# └─────────────────────┴──────────┴──────────┴──────────┘
```

### 2.4 Верификация: прогнать все 4 фазы тестов из золотого образа

```bash
bash scripts/vm/test-from-golden.sh --version 0.25.1
# Ожидаемый результат:
# Phase 1 (Clean Install): 12/12 PASS
# Phase 2 (Update):         6/6 PASS
# Phase 3 (AI Smoke):       SKIP (no API key)
# Phase 4 (CI + Migrations): 5/5 PASS
# Total: 23/23 PASS, 0 FAIL
```

---

## M3: CI-интеграция (GitHub Actions)

**Срок:** ~2h | **Код:** ~80 строк YAML | **Зависимость:** M2

### 3.1 Подготовка self-hosted runner

Требования к bare-metal машине:
- Ubuntu 24.04 с KVM (вложенная виртуализация: `/dev/kvm`)
- Пакеты: `qemu-kvm`, `libguestfs-tools`, `cloud-image-utils`
- Золотой образ предварительно собран: `~/iwe-golden-*.qcow2`
- SSH-ключ: `~/.ssh/id_ed25519_iwe_test`

### 3.2 Workflow: `.github/workflows/test-golden.yml`

```yaml
name: IWE Golden Image Tests
on:
  push:
    branches: [0.25.1, main]
    paths:
      - 'scripts/vm/user-data.yaml'
      - 'scripts/vm/packages-firstboot.sh'
      - 'setup.sh'
      - 'seed/manifest.yaml'
      - 'checksums.yaml'
      - 'MANIFEST.yaml'
  pull_request:
    branches: [0.25.1, main]
  workflow_dispatch:
    inputs:
      rebuild_golden:
        description: 'Force rebuild golden image'
        type: boolean
        default: false
      test_phase:
        description: 'Specific phase (1-4, or all)'
        type: string
        default: 'all'

jobs:
  golden-test:
    runs-on: self-hosted
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Rebuild golden image (if needed)
        if: |
          inputs.rebuild_golden ||
          steps.changed_files.outputs.user_data == 'true'
        run: bash scripts/vm/build-golden.sh --version ${{ github.ref_name }}

      - name: Run tests from golden image
        run: |
          bash scripts/vm/test-from-golden.sh \
            --version ${{ github.ref_name }} \
            --phase ${{ inputs.test_phase }}

      - name: Archive test report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: test-report-${{ github.run_id }}
          path: scripts/vm/results/golden-test-*.json
```

### 3.3 Авто-пересборка: триггеры

Золотой образ пересобирается когда изменились:
- `scripts/vm/user-data.yaml` (системные пакеты)
- `scripts/vm/packages-firstboot.sh` (npm-пакеты)
- `setup.sh` (логика установки)
- `seed/manifest.yaml` (артефакты)
- `MANIFEST.yaml` (версия репо)

Реализация: шаг `changed_files` через `dorny/paths-filter@v2` или `tj-actions/changed-files`.

### 3.4 Локальный CI через act

```bash
# Прогнать workflow локально без пуша
act workflow_dispatch \
  -W .github/workflows/test-golden.yml \
  --input rebuild_golden=true \
  --container-architecture linux/amd64
```

---

## M4: Документация и ADR-promotion

**Срок:** ~1h | **Код:** ~100 строк (документация)

### 4.1 Обновить ADR-007

- [ ] Добавить секцию **«Implementation»** со ссылками на скрипты
- [ ] Добавить **«Performance Results»** (цифры из benchmark-golden.sh)
- [ ] Обновить последствия: реальные цифры скорости вместо оценок
- [ ] Статус: `Proposed → Accepted → Implemented`
- [ ] Дата: обновить на дату реализации

### 4.2 Обновить связанные документы

| Документ | Изменения |
|----------|----------|
| `scripts/vm/README.md` | Добавить секцию «Golden Image Pipeline»: build-golden, test-from-golden, verify-golden, benchmark-golden |
| `docs/golden-image-survey.md` §8 | Заменить «(референсная реализация)» на ссылку на реальный `scripts/vm/build-golden.sh` |
| `CHANGELOG.md` | v0.27.0: ADR-007 implemented — golden image build pipeline |
| `docs/adr/README.md` | Обновить статус ADR-007: Proposed → Implemented |

### 4.3 LEARNINGS.md (в репо или memory)

Записать минимум 3 урока:
1. `virt-customize --install` не поддерживает PPA — решение через `--run-command add-apt-repository`
2. qcow2 backing file: модификация базового образа ломает все производные → копировать базовый образ перед `virt-customize`
3. `--firstboot` script запускается от root → `su - iwe -c` для npm install в домашнюю директорию пользователя

### 4.4 Финальная верификация

```bash
# Полный цикл: сборка → верификация → тест
bash scripts/vm/build-golden.sh --version 0.25.1
bash scripts/vm/verify-golden.sh --image iwe-golden-0.25.1.qcow2 --full
bash scripts/vm/test-from-golden.sh --version 0.25.1
bash scripts/vm/benchmark-golden.sh
```

---

## M5: Долгосрочная эволюция (future)

| # | Задача | Приоритет | Обоснование |
|---|--------|:---------:|-------------|
| 5.1 | **Кэш apt-пакетов** для `virt-customize --install` (без сети) | Medium | Сетевая зависимость при каждой пересборке |
| 5.2 | **Multi-version golden images** (`0.25.1`, `0.26.0`, `main`) | Low | Пока одна активная ветка |
| 5.3 | **virtio-fs** для передачи credentials (вместо scp) | Low | SOTA-паттерн 2025, credentials не покидают хост-память |
| 5.4 | **Интеграция с act** (локальный CI без пуша) | Low | Удобство разработки |
| 5.5 | **Автоматический smoketest** после каждой пересборки | Medium | Гарантия что золотой образ не сломан |
| 5.6 | **Packer QEMU** как альтернативный builder | Low | Если понадобится multi-builder (AWS AMI + QEMU) |

---

## Сводка

| Milestone | Артефакты | Строк кода | Время | Статус |
|-----------|----------|:----------:|:-----:|:------:|
| **M0** | survey, ADR-007, user-data.yaml, packages-firstboot.sh | — | — | ✅ |
| **M1** | build-golden.sh, verify-golden.sh, packages-firstboot.sh (update) | 457 | 2h | ✅ |
| **M2** | test-from-golden.sh, benchmark-golden.sh | 418 | 3h | ✅ |
| **M3** | test-golden.yml, self-hosted runner config | ~80 | 2h | ○ |
| **M4** | ADR update, README update, CHANGELOG, LEARNINGS | ~100 | 1h | ○ |
| **M5** | Future evolution | — | — | ○ |

**Всего:** 875 строк кода (M1-M2), ~4h remaining (M3-M4).

**Ключевой KPI:**
- До: 15 мин на создание тестового окружения
- После (M2): **<30 сек** на `test-from-golden.sh`
- Ускорение: **30x**

**Начать с M1: build-golden.sh.**

---

*План создан: 2026-05-04 | Ревизия: 1*
