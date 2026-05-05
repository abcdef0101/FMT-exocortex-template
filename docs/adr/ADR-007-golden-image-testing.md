# ADR-007: Golden Image Build Pipeline for IWE Testing

**Статус:** Implemented
**Дата:** 2026-05-03
**Реализовано:** 2026-05-04
**Контекст:** FMT-exocortex-template, scripts/vm/

---

## Контекст

IWE тестируется в виртуальной машине (QEMU/KVM + libvirt). Текущий цикл создания тестового окружения:

```
create-vm.sh  →  загрузка образа (~600 MB)
              →  cloud-init (установка пакетов, ~5 мин)
              →  provision.sh (клон репо + expect setup.sh, ~3 мин)
              →  Итого: ~15 мин на создание окружения
```

Каждый тестовый прогон повторяет полный цикл. Это делает итерацию медленной.

Проведён SOTA-обзор подходов к сборке золотых образов (см. `docs/golden-image-survey.md`). Результат: 6 релевантных категорий инструментов, взвешенная оценка по 7 критериям, coupling analysis.

---

## Проблема

1. **Скорость:** 15 минут на создание окружения перед каждым тестом — неприемлемо для частых итераций
2. **Сложность:** provision.sh воспроизводит логику setup.sh вручную (дублирование кода)
3. **Нестабильность:** cloud-init падает при отсутствии сети (runcmd не выполняется до конца), приходится доустанавливать пакеты вручную
4. **Нет версионирования:** каждое окружение пересоздаётся с нуля без возможности быстрого отката

---

## Решение

### Выбранный подход: cloud-init + SSH provision + qcow2 snapshots (версионирование)

**Инструмент сборки:** `cloud-init` (минимальный seed с пользователем iwe + SSH) + SSH provision (apt + npm + git clone).

**Почему не virt-customize (как планировалось):**
- `virt-customize` использует passt для сети внутри libguestfs appliance
- На kernel 6.8.0-110-generic passt падает с SIGSEGV — блокирующий баг
- Решение: cloud-init seed (CD-ROM) → загрузка VM → SSH provision → shutdown
- Это добавляет ~2 мин времени сборки (загрузка VM), но надёжнее падающего passt

**Почему не Packer:**
- Packer QEMU builder запускает VM для провижининга (20-40 мин)
- Требует VNC/headless графику
- Packer отсутствует в Ubuntu 24.04 репозиториях
- Knowledge coupling выше (HCL + cloud-init autoinstall + boot_command vs 1 shell-скрипт)
- Неоправданный оверхед для одного образа (Packer оправдан при множественных builder'ах)

**Почему не mkosi:**
- Требует systemd v256+ (Ubuntu 24.04 — v255)
- Молодой проект с ежемесячными breaking changes
- Сложная отладка sandbox-окружения

**Почему не NixOS:**
- NixOS ≠ Ubuntu (разные дистрибутивы)
- IWE требует Ubuntu 24.04

### Архитектура

```
build-golden.sh (однократно, ~6 мин)
│
├─ 1. wget базовый образ (кэшируется, 600 MB)
├─ 2. cloud-init seed: user iwe + SSH ключ (минимальный, без packages)
├─ 3. Boot VM, ждать cloud-init + SSH (~1 мин)
├─ 4. SSH: apt-get install все системные пакеты (~3 мин)
│      (git, gh, ruby, nodejs 20 LTS via NodeSource, npm, expect, jq,
│       shellcheck, vim, neovim via PPA, mc, tmux, build-essential,
│       python3, python3-yaml, software-properties-common)
├─ 5. SSH: packages-firstboot.sh — Слой 2 (~1 мин)
│      (claude-code, codex, opencode + git clone FMT-exocortex-template)
├─ 6. Shutdown, qemu-img snapshot "provisioned", sha256sum
└─ 7. Результат: iwe-golden-0.25.1.qcow2 (2.6 GB, 570 MB COW)

test-from-golden.sh (каждый прогон, ~14 сек)
│
├─ 1. qemu-img create -b golden.qcow2 → ephemeral.qcow2 (COW, <1 сек)
├─ 2. qemu-system-x86_64 -enable-kvm (загрузка VM, ~13 сек)
├─ 3. SSH → source test-phases.sh → 4 фазы тестов
├─ 4. Kill QEMU, rm ephemeral.qcow2 (очистка)
└─ 5. Exit code = количество FAIL (0 = success)

CI (.github/workflows/test-golden.yml):
├─ Self-hosted runner с KVM (iwe-kvm-iwe-demo-2)
├─ Триггеры: push, pull_request, workflow_dispatch
├─ Авто-пересборка: workflow_dispatch --rebuild_golden
└─ Артефакты: test reports → GitHub Actions artifacts
```

### Coupling Model (SOTA.011)

| Измерение | virt-customize | Packer QEMU |
|-----------|:---:|:---:|
| **Knowledge** (сколько концепций нужно знать) | ★ низкий (1 скрипт) | ★★★ средний (HCL + cloud-init + VNC + boot_command) |
| **Distance** (длина цепочки шагов) | ★ низкий (host → libguestfs → qcow2) | ★★ низкий (Packer → QEMU → VNC → SSH → provision → shutdown) |
| **Volatility** (частота изменений контракта) | ★ низкий (libguestfs API c 2010) | ★★ низкий (Packer plugins версионируются) |

### Альтернативы (рассмотрены и отклонены)

| Альтернатива | Причина отклонения |
|-------------|-------------------|
| Packer QEMU | 20-40 мин сборки, VNC-зависимость, knowledge coupling |
| mkosi | systemd v256+ не в Ubuntu 24.04 |
| NixOS | Не Ubuntu |
| Cloud-init (только) | Зависимость от сети, медленный первый запуск |
| Текущий подход (create-vm + provision) | 15 мин на создание окружения, cloud-init нестабилен |

---

## Последствия

### Положительные

- **Скорость:** тестовое окружение создаётся за секунды (qemu-img create -b), а не за 15 минут
- **Надёжность:** офлайн-сборка не зависит от сети (apt внутри libguestfs appliance использует кэш)
- **Воспроизводимость:** золотой образ — артефакт с контрольной суммой
- **Откат:** qcow2 snapshots позволяют мгновенно вернуться к чистому состоянию
- **CI-готовность:** ephemeral VM = «create, use, discard» — стандартный паттерн 2025

### Отрицательные

- **Новый инструмент в цепочке:** libguestfs-tools (1 пакет apt, ~5 MB) — минимальный оверхед
- **Сложность отладки:** libguestfs appliance — «чёрный ящик» при ошибках `--install`
- **Размер:** золотой образ ~3 GB (базовый ~600 MB + слой провижининга ~2 GB)
- **Не кроссплатформенно:** qcow2 снапшоты не поддерживаются libvirt (virsh snapshot-create). Используется `qemu-img snapshot` напрямую

### Нейтральные / требует внимания

- **Синхронизация с provision.sh:** build-golden.sh должен отражать изменения в `user-data.yaml` и `setup.sh`. Процесс: при изменении → пересборка золотого образа
- **Версионирование:** имя файла включает версию репо (`iwe-golden-0.25.1.qcow2`)
- **Кэширование:** базовый образ кэшируется, не скачивается повторно

---

## Связанные документы

| Документ | Связь |
|----------|-------|
| `docs/golden-image-survey.md` | SOTA-обзор 6 подходов, матрица F-G-R, coupling model |
| `docs/adr/ADR-005-update-delivery-architecture.md` | manifest-lib.sh, checksums.yaml |
| `docs/adr/impl/ADR-007-implementation-plan.md` | План реализации M1-M5 |
| `scripts/vm/build-golden.sh` | Сборка золотого образа (virt-customize, 2 слоя) |
| `scripts/vm/verify-golden.sh` | Верификация целостности образа |
| `scripts/vm/test-from-golden.sh` | Ephemeral VM + прогон тестов |
| `scripts/vm/benchmark-golden.sh` | Сравнение скорости (15 мин → <30 сек) |
| `scripts/vm/packages-firstboot.sh` | Слой 2: npm-пакеты + клон репо |
| `scripts/vm/provision.sh` | Текущий провижининг (expect-based, ~3 мин) |
| `scripts/vm/test-phases.sh` | 4 фазы тестирования (setup, update, AI smoke, CI) |
| `scripts/vm/user-data.yaml` | Слой 1: системные пакеты, пользователи, cloud-init |

---

## Реализация

**Дата:** 2026-05-04
**Статус:** M0—M3 завершены, M4 (документирование) — в процессе, M5 (эволюция) — будущее

### M0: Foundation ✅
- SOTA-обзор 6 подходов (`docs/golden-image-survey.md`, 524 строки)
- Анализ пакетов (Layer 1: 16 apt-пакетов, Layer 2: 3 npm-пакета)
- Plan: `docs/adr/impl/ADR-007-implementation-plan.md`

### M1: build-golden.sh ✅
- `scripts/vm/build-golden.sh` (262 строки)
- Метод: cloud-init seed → boot → SSH provision (вместо virt-customize из-за passt SIGSEGV)
- Слой 1: 16 системных пакетов (git, gh, ruby, nodejs 20, neovim, etc.)
- Слой 2: npm (claude-code, codex, opencode) + git clone
- Снапшот "provisioned", SHA256-верификация
- `scripts/vm/verify-golden.sh` (244 строки) — qemu-img + guestfish + SSH

### M2: test-from-golden.sh ✅
- `scripts/vm/test-from-golden.sh` (310 строк)
- Ephemeral VM: qemu-img create -b (COW, <1 сек) + QEMU boot (13 сек)
- 4 фазы тестов из `scripts/vm/test-phases.sh`
- `scripts/vm/benchmark-golden.sh` (129 строк) — сравнение скорости

### M3: CI Integration ✅
- `.github/workflows/test-golden.yml` — self-hosted runner с KVM
- Runner: `iwe-kvm-iwe-demo-2` (systemd-сервис, labels: self-hosted, Linux, X64, kvm)
- Триггеры: push в 0.25.1/main, pull_request, workflow_dispatch
- Авто-пересборка по запросу, continue-on-error для нефатальных тестов

### M5: Runtime/Code separation ✅
- Golden image теперь содержит **только runtime** (apt-пакеты + npm-пакеты)
- Репозиторий клонируется свеже при каждом запуске `test-from-golden.sh`
- Обоснование: runtime (apt/npm) меняется редко, code (репо) — каждый коммит
- Пересборка golden image нужна только при изменении system-зависимостей
- Git clone в ephemeral VM: ~5-10 сек → общее время прогона ~20 сек (всё ещё 45x быстрее чем 15 мин)

### Результаты производительности

| Метрика | До | После |
|---------|----|-------|
| Создание тестового окружения | ~15 мин | **14 сек** |
| Загрузка VM | ~5 мин (cloud-init) | **13 сек** |
| Полный прогон 4 фаз | ~20 мин | **~2 мин** |
| Ускорение | 1x | **~60x** |

**Тестовое покрытие:** 17/18 тестов (1 фейл — checksums.yaml валидность, баг кодобазы)

### Известные ограничения
- `virt-customize` passt SIGSEGV на kernel 6.8.0 — обход через cloud-init + SSH
- OpenCode CLI не устанавливается через `@opencode-ai/plugin` (это библиотека, не CLI) — Phase 3 AI Smoke пропускается
- Git identity не настроена в golden-образе — test-phases.sh устанавливает автоматически
- guestfish: `chmod 600` на `/boot/vmlinuz-*` блокирует supermin (поправлено `chmod +r`). `grep -q` в пайпе с `set -o pipefail` вызывает SIGPIPE на больших выводах `dpkg --list` — заменён на `grep >/dev/null` в `verify-golden.sh`.
