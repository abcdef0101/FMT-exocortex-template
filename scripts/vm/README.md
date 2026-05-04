# IWE Test VM

> Полноценная виртуальная машина для 100% тестирования IWE и E2E-сценариев.

## Golden Image Pipeline (ADR-007)

Сборка золотого образа через `virt-customize` + `qcow2 snapshots`. Скорость: 15 мин → <30 сек.

```bash
# 1. Установить зависимости
sudo apt install -y qemu-kvm libguestfs-tools

# 2. Создать SSH-ключ
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_iwe_test -N "" -C "iwe-test"

# 3. Собрать золотой образ (однократно, ~5-10 мин)
bash scripts/vm/build-golden.sh --version 0.25.1

# 4. Проверить образ
bash scripts/vm/verify-golden.sh --image ~/.cache/iwe-golden/iwe-golden-0.25.1.qcow2

# 5. Прогнать тесты из золотого образа (<30 сек на создание окружения)
bash scripts/vm/test-from-golden.sh --version 0.25.1

# 6. Сравнить скорость
bash scripts/vm/benchmark-golden.sh --version 0.25.1
```

**Архитектура:**
- `build-golden.sh` — Слой 1 (apt) + Слой 2 (npm, firstboot)
- `test-from-golden.sh` — copy-on-write клон + прогон test-phases.sh
- `verify-golden.sh` — qemu-img + guestfish инспекция
- `benchmark-golden.sh` — сравнение create-vm vs golden

→ **ADR-007:** `docs/adr/ADR-007-golden-image-testing.md`
→ **План:** `docs/adr/impl/ADR-007-implementation-plan.md`

---

## Быстрый старт (текущий метод, без golden image)

```bash
# 1. Установить гипервизор (один раз)
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst cloud-image-utils
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
# перелогиниться

# 2. Создать SSH-ключ (если нет)
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_iwe_test -N "" -C "iwe-test-vm"

# 3. Создать secrets (НЕ КОММИТИТЬ)
mkdir -p ~/.iwe-test-vm/secrets
cp scripts/vm/secrets.example ~/.iwe-test-vm/secrets/.env
# Отредактировать ~/.iwe-test-vm/secrets/.env — вставить свои токены
chmod 700 ~/.iwe-test-vm/secrets
chmod 600 ~/.iwe-test-vm/secrets/.env

# 4. Создать VM
bash scripts/vm/create-vm.sh

# 5. Запустить полный тест
bash scripts/vm/run-full-test.sh

# 6. Удалить VM (когда больше не нужна)
bash scripts/vm/destroy-vm.sh
```

> **ВАЖНО:** Установка IWE в VM происходит **только через `git clone --branch 0.25.1`**.
> Копирование файлов через `tar`/`scp` не поддерживается — E2E-тесты требуют
> полной git-истории для `update.sh --check`/`--apply`, checksum verification,
> 3-way merge и миграций. Ветка `0.25.1` зафиксирована жёстко — это стабильная
> версия с полной реализацией ADR-005.
```

## Архитектура

```
Хост (Ubuntu 24.04)
├── QEMU/KVM + libvirt
├── ~/.iwe-test-vm/
│   ├── secrets/              # chmod 700: токены, никогда не в git
│   │   └── .env              # OPENAI_API_KEY, GLM_API_KEY, GH_TOKEN
│   ├── iwe-test.qcow2        # диск VM (20G thin)
│   └── seed.img              # cloud-init seed
│
└── VM: iwe-test (Ubuntu 24.04, 4GB, 2CPU)
    ├── OpenCode CLI (DeepSeek V4 Pro + GLM 5.1)
    ├── git, gh, ruby, python3, shellcheck, jq, tmux
    ├── /home/iwe/IWE/FMT-exocortex-template/
    │   ├── setup.sh
    │   ├── update.sh
    │   ├── scripts/test/run-phase0.sh
    │   ├── scripts/test/run-e2e.sh
    │   └── scripts/enforce-semver.sh
    └── /mnt/secrets/ → mount point (опционально)
```

## Безопасность

- Credentials хранятся **только на хосте** (`chmod 700`), передаются в VM через SSH env vars или virtio-fs mount
- VM-образ **не содержит** токенов (cloud-init устанавливает только публичные пакеты)
- `secrets/` директория в `.gitignore` — никогда не попадёт в репозиторий
- После теста VM можно удалить — никаких следов credentials на диске гостя

## Что тестируется

| Категория | Инструмент | Автоматизация |
|-----------|-----------|-------------|
| Установка | `setup.sh` + `apply_manifest` | ✅ |
| Структура | 9 файлов workspace | ✅ |
| Обновление | `update.sh --check` / `--apply` | ✅ |
| Checksums | SHA-256 161 файла | ✅ |
| Миграции | `run-migrations.sh` | ✅ |
| CI enforcement | `enforce-semver.sh` | ✅ |
| 14 unit-тестов | `run-phase0.sh` | ✅ |
| 5 E2E-тестов | `run-e2e.sh` | ✅ |
| OpenCode smoke | «скажи: IWE test OK» | ✅ |
| Day Open/Close | Claude Code | ❌ (нет API-ключа) |
| Роли (launchd) | macOS only | ❌ |
