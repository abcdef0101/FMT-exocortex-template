# ADR-007: Golden Image Build Pipeline for IWE Testing

**Статус:** Accepted
**Дата:** 2026-05-03
**Реализация:** 2026-05-04
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

### Выбранный подход: virt-customize (офлайн-сборка) + qcow2 snapshots (версионирование)

**Инструмент сборки:** `virt-customize` (libguestfs-tools) — модификация образа БЕЗ запуска VM.

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
build-golden.sh (однократно, ~5 мин)
│
├─ 1. wget базовый образ (кэшируется)
├─ 2. virt-customize: Слой 1 — системные пакеты (git, gh, ruby, nodejs, npm,
│      expect, jq, shellcheck, vim, neovim via PPA, mc, tmux, build-essential)
├─ 3. --firstboot packages-firstboot.sh: Слой 2 — npm для iwe
│      (claude-code, codex, opencode) + git clone + setup.sh
├─ 4. qemu-img create (copy-on-write от базового)
├─ 5. qemu-img snapshot -c "provisioned"
└─ 6. sha256sum

test-from-golden.sh (каждый прогон, ~секунды)
│
├─ 1. qemu-img create -b golden.qcow2 → ephemeral.qcow2
├─ 2. qemu-system-x86_64 (запуск VM)
├─ 3. SSH → run test suite
└─ 4. rm ephemeral.qcow2 (очистка)

Откат: qemu-img snapshot -a provisioned golden.qcow2
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
**Статус:** M1—M2 завершены, M3-M4 в очереди

Скрипты созданы согласно архитектуре из §Решение:
- `build-golden.sh` — однократная офлайн-сборка (virt-customize, 2 слоя)
- `test-from-golden.sh` — copy-on-write клон + прогон тестов (секунды)
- `verify-golden.sh` — проверка целостности образа (qemu-img + guestfish)
- `benchmark-golden.sh` — сравнительный замер скорости

**KPI:** время создания тестового окружения: 15 мин → <30 сек (30x ускорение).
