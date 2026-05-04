# Golden Image Build Pipeline — SOTA Survey

> **Type:** Knowledge artifact (Pack-equivalent — «что существует в индустрии»)
> **Governance decision:** → `docs/adr/ADR-007-golden-image-testing.md`
> **Generated:** 2026-05-03 | **Edition:** 1 | **F-G-R legend:** [F]=Fact (verified), [G]=Guess (docs), [R]=Rumor (community)

---

## §1. Scope (контекст с границами) — A.1.1 Bounded Context

| Параметр | Значение |
|----------|----------|
| **Целевая система (SoI)** | IWE test VM на Ubuntu 24.04 |
| **Конструктор (constructor)** | QEMU/KVM + libvirt (virsh) |
| **Где запускается** | Локально (bare metal Linux) или CI (GitHub Actions self-hosted runner) |
| **Размер образа** | ~2 GB (базовый qcow2) + ~1 GB (провижининг-слой) |
| **Частота пересборки** | При изменении `user-data.yaml`, `setup.sh`, или версии репо (~1-2 раза/неделю) |
| **Что НЕ в scope** | Cloud-AMI (AWS/Azure/GCP), Windows, macOS, ARM64, контейнеры (OCI) |

### Почему исключены

| Инструмент | Причина |
|-----------|---------|
| AWS EC2 Image Builder, Azure Image Builder, GCP Image Builder | Cloud-only builders. Нет QEMU-провайдера. Неприменимы к локальному libvirt |
| Vagrant | Ориентирован на dev-окружения (интерактивный `vagrant up`), не на CI. HashiCorp рекомендует Packer для продакшен-боксов |
| RHEL Image Builder | RHEL/CentOS-only. Не поддерживает Ubuntu |
| KIWI | openSUSE/SLES-only. Не поддерживает Ubuntu |
| OCI/контейнеры | Конвертация OCI → qcow2 нестандартна (только Proxmox 9.1, 2025). Нет boot-слоя для VM |
| Debos | Функционально эквивалентен virt-customize для Debian/Ubuntu. Не добавляет нового паттерна |

---

## §2. Таксономия подходов — A.7 (метод ≠ инструмент)

Подходы разделены по **методу** (что происходит), а не по инструменту (чем):

```
              Сборка золотого образа
                      │
        ┌─────────────┼──────────────┐
        │             │              │
   Декларативный  Императивный   Гибридный
   (спецификация  (модификация   (декларативный
    → сборка)      образа)        базис + императив)
        │             │              │
   NixOS          virt-customize  Packer+Ansible
   mkosi          libguestfs      cloud-init+runcmd
```

**Различение (strict distinction):**
- **Декларативный метод** — система описана как желаемое состояние (Nix-выражение, HCL-шаблон). Конструктор (constructor) интерпретирует описание и строит образ.
- **Императивный метод** — скрипт/команда непосредственно модифицирует образ (установка пакетов, копирование файлов). Конструктор = скрипт.
- **Гибридный** — декларативная основа (cloud-init YAML) + императивные действия (runcmd, bootcmd).

---

## §3. Шесть категорий инструментов (релевантных Scope)

### 3.1 Декларативная сборка: NixOS/nixos-generators

**Метод:** система описана как Nix-выражение. Сборка даёт побайтово идентичный результат.

```nix
# iwe-test-image.nix — пример
{ config, pkgs, ... }: {
  users.users.iwe = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAA..." ];
  };
  environment.systemPackages = with pkgs; [
    git nodejs_20 ruby expect jq shellcheck
  ];
}
```

```bash
nixos-generate -f qcow2 -c iwe-test-image.nix -o iwe-golden.qcow2
```

| Сильные стороны | Слабые стороны |
|-----------------|----------------|
| Бит-в-бит воспроизводимость (Nix store hash) **[F+]** | Крутая кривая обучения (Nix-язык, Flakes) **[F]** |
| Атомарное обновление поколений (rollback) **[F]** | NixOS — специфичный дистрибутив, не Ubuntu **[F]** |
| Nix Flakes: lock-файл для зависимостей **[F]** | Сборка из исходников → медленно (часы) **[G]** |

**Применимость к IWE:** ★☆☆☆☆ — NixOS ≠ Ubuntu. Эталон воспроизводимости, но не для IWE.
**Источники:** [NixOS Reproducible Builds ISO](https://discourse.nixos.org/t/nixos-reproducible-builds-minimal-installation-iso-successfully-independently-rebuilt/34756) (2025) **[F]**

---

### 3.2 Императивная офлайн-сборка: virt-customize

**Метод:** модификация образа БЕЗ запуска VM. libguestfs запускает мини-апплаенс, монтирует ФС, применяет изменения.

```bash
virt-customize -a noble-server-cloudimg-amd64.img \
  --install git,ruby,nodejs,npm,expect,jq,shellcheck \
  --run-command 'useradd -m -s /bin/bash iwe' \
  --ssh-inject iwe:file=/home/iwe/.ssh/id_ed25519_iwe_test.pub \
  --copy-in provision.sh:/home/iwe/ \
  --firstboot /home/iwe/provision.sh
```

**Как работает под капотом [F]:** libguestfs запускает appliance (мини-VM через QEMU), монтирует диск внутри appliance, предоставляет доступ к ФС через RPC API. Поддерживает все форматы QEMU (qcow2, raw, vmdk, vdi).

| Сильные стороны | Слабые стороны |
|-----------------|----------------|
| **Офлайн:** не нужна запущенная VM **[F+]** | `--install` зависит от apt внутри appliance (может зависнуть без сети) **[F]** |
| `--firstboot` откладывает тяжёлые операции до первого запуска **[F]** | Требует root или sudo для некоторых операций **[F]** |
| `--copy-in`, `--run`, `--write`, `--ssh-inject` — полный контроль ФС **[F]** | Сложная отладка (апплаенс внутри QEMU) **[F]** |
| Production use: Red Hat OpenShift Virtualization (2025) **[F+]** | libguestfs API сложнее shell-скриптов **[G]** |
| 0 новых зависимостей: `apt install libguestfs-tools` **[F]** | |

**Применимость к IWE:** ★★★★★ — лучший выбор. Проверено в IWE VM.
**Источники:** [TIL: virt-customize](https://patrickod.com/2025/11/22/til-using-virt-customize-to-modify-vm-images/) (2025) **[F]**, [Red Hat OpenShift golden image pipeline](https://developers.redhat.com/articles/2025/06/03/automate-vm-golden-image-management-openshift) (2025) **[F+]**

---

### 3.3 Императивная онлайн-сборка: Packer (QEMU builder)

**Метод:** HCL-шаблон описывает source image + provisioners. Packer запускает QEMU VM, ждёт SSH, выполняет provisioner, экспортирует образ.

```hcl
# iwe-golden.pkr.hcl
source "qemu" "iwe-golden" {
  iso_url      = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  disk_image   = true
  ssh_username = "iwe"
  ssh_private_key_file = "~/.ssh/id_ed25519_iwe_test"
}

build {
  sources = ["source.qemu.iwe-golden"]
  provisioner "shell" {
    inline = ["bash /home/iwe/provision.sh"]
  }
}
```

| Сильные стороны | Слабые стороны |
|-----------------|----------------|
| 8 builders (QEMU, Proxmox, AWS, Azure, GCP, Docker) **[F+]** | **Сборка 20-40 минут** (ISO install + cloud-init + provision) **[G]** |
| Provisioners: shell, ansible, chef, puppet, file **[F+]** | Требует VNC/headless графику для QEMU **[F]** |
| post-processors: manifest, compress, checksum **[F]** | HCL-шаблоны — сложная отладка (PACKER_LOG=1) **[F]** |
| GitHub Actions интеграция готовая **[F]** | Packer отсутствует в Ubuntu 24.04 repos (нужен ручной install) **[F]** |
| 2025: KubeVirt plugin — сборка VM-образов в Kubernetes **[F]** | `ssh_timeout` при медленной cloud-init инициализации **[F]** |

**Применимость к IWE:** ★★★☆☆ — индустриальный стандарт, но оверхед для одного образа.
**Источники:** [Packer + cloud-init Ubuntu build](https://oneuptime.com/blog/post/2026-03-02-how-to-use-cloud-init-with-packer-for-automated-builds-on-ubuntu/view) (2026) **[G]**, [Red Hat OpenShift + Packer KVM](https://developers.redhat.com/articles/2025/11/07/automate-vm-golden-image-builds-openshift-packer) (2025) **[F+]**

---

### 3.4 systemd-нативная сборка: mkosi

**Метод:** конфигурационный файл описывает дистрибутив и пакеты. mkosi строит образ через systemd-repart, запускает через systemd-nspawn или `mkosi qemu`.

```ini
# mkosi.conf
[Distribution]
Distribution=ubuntu
Release=noble

[Output]
Format=disk

[Content]
Packages=git,nodejs,ruby,expect,jq,shellcheck,openssh-server

[Host]
Ssh=always
```

```bash
mkosi build    # сборка
mkosi qemu     # запуск VM
mkosi ssh      # SSH через vsock (systemd v256+)
```

| Сильные стороны | Слабые стороны |
|-----------------|----------------|
| Встроенная QEMU-интеграция: `mkosi qemu`, `mkosi ssh` **[G]** | Требует systemd v256+ для vsock (Ubuntu 24.04 — v255) **[F]** |
| Sandbox-сборка: непривилегированные user namespaces **[F]** | Молодой проект (ежемесячные breaking changes) **[F]** |
| systemd-repart для декларативной разметки **[G]** | Сложная отладка sandbox-окружения **[G]** |
| UKI (Unified Kernel Image) + Secure Boot **[G]** | `--install` пакетов опосредованно (через apt внутри sandbox) **[G]** |

**Применимость к IWE:** ★★☆☆☆ — перспективный, но нестабильный. systemd v255 в Ubuntu 24.04 не поддерживает vsock SSH.
**Источники:** [mkosi: First Impressions](https://blog.wang-lu.com/2025/08/mkosi-first-impressions.html) (2025) **[G]**

---

### 3.5 Низкоуровневый API: libguestfs / guestfish

**Метод:** C-библиотека + интерактивная оболочка `guestfish` для прямого манипулирования ФС внутри образа. virt-customize — высокоуровневая обёртка над libguestfs.

```bash
# guestfish — интерактивный shell внутри образа
guestfish --ro -a noble-server-cloudimg-amd64.img
><fs> run
><fs> list-filesystems
/dev/sda1: ext4
><fs> mount /dev/sda1 /
><fs> cat /etc/os-release
```

| Сильные стороны | Слабые стороны |
|-----------------|----------------|
| Полный доступ к ФС: чтение, запись, создание файлов **[F+]** | Низкоуровневый API: нужна ручная работа с монтированием **[F]** |
| Поддерживает: ext2/3/4, XFS, btrfs, NTFS, VFAT, LVM2, MBR, GPT **[F+]** | Не для прямого использования в pipeline (используется через virt-customize) |
| Форматы: qcow2, raw, VDI, VMDK, VHD/VHDX **[F+]** | |

**Применимость к IWE:** ★★★☆☆ — API под капотом у virt-customize. Используется опосредованно.
**Источники:** [libguestfs Wikipedia](https://en.wikipedia.org/wiki/Libguestfs) **[F]**, [Red Hat libguestfs guide](https://www.redhat.com/en/blog/libguestfs-manage-vm) **[F]**

---

### 3.6 Версионирование артефактов: qcow2 snapshots

**Метод:** qcow2 поддерживает внутренние снапшоты (дельта от базового состояния). Создание/откат за секунды.

```bash
# Создание снапшота после провижининга
qemu-img snapshot -c provisioned iwe-golden.qcow2

# Список снапшотов
qemu-img snapshot -l iwe-golden.qcow2
# 1    provisioned    1.2G    2026-05-03 14:00:00
# 2    tests-passed   300M    2026-05-03 14:10:00

# Откат к чистому состоянию
qemu-img snapshot -a provisioned iwe-golden.qcow2

# Создание тестовой VM из золотого образа (copy-on-write)
qemu-img create -f qcow2 -b iwe-golden.qcow2 -F qcow2 test-ephemeral.qcow2
```

| Сильные стороны | Слабые стороны |
|-----------------|----------------|
| Мгновенное создание/откат (секунды) **[F]** | Снапшоты растут (дельта накапливается) **[F]** |
| Несколько снапшотов в одном файле **[F]** | libvirt НЕ поддерживает внутренние снапшоты (только внешние) **[F]** |
| Встроено в QEMU — ноль новых зависимостей **[F]** | Не переносимо между ФС без `qemu-img convert` **[F]** |
| Идеально для CI: `qemu-img create -b golden.qcow2` → ephemeral VM **[F]** | |

**Применимость к IWE:** ★★★★★ — идеальный компаньон к virt-customize. Не сборка, а версионирование.

---

## §4. Матрица сравнения — Lawful Comparison (A.19)

Все инструменты оценены по одинаковым критериям, единая шкала (★). Каждая оценка маркирована F-G-R.

### Шкала

| Звёзды | F-G-R | Значение |
|--------|-------|----------|
| ★★★★★ | F+ | Gold standard (production use, multiple sources) |
| ★★★★ | F | Проверено в IWE VM ИЛИ industry consensus |
| ★★★ | G+ | Подтверждено community, не проверено в IWE |
| ★★ | G | Из документации |
| ★ | R | Из community / неподтверждено |

### Матрица

| Критерий | virt-customize | Packer QEMU | mkosi | NixOS |
|----------|:---:|:---:|:---:|:---:|
| **Поддержка Ubuntu 24.04** | ★★★★★ [F+] | ★★★★ [F] | ★★ [G] | — [F] |
| **Скорость сборки** | ★★★★ [F] | ★★ [G] | ★★★ [G] | ★ [F] |
| **Скорость запуска VM** | ★★★★★ [F] | ★★★★★ [F] | ★★★★ [G] | ★★★★ [F] |
| **Воспроизводимость** | ★★★ [F] | ★★★★ [F] | ★★★ [G] | ★★★★★ [F+] |
| **0 новых зависимостей** | ★★★★★ [F] | ★★ [F] | ★★ [F] | ★ [F] |
| **CI-интеграция** | ★★★ [G] | ★★★★ [F] | ★★ [G] | ★★ [G] |
| **Кривая обучения** | ★★★★ [F] | ★★★ [F] | ★★ [G] | ★ [F] |

**Примечания к оценкам:**
- **virt-customize / скорость сборки ★★★★:** офлайн-модификация — 2-5 минут (apt install внутри libguestfs appliance) **[F]**
- **Packer QEMU / скорость сборки ★★:** 20-40 минут по документации (ISO install + cloud-init + SSH provision) **[G]** — требует верификации в IWE
- **NixOS / Ubuntu:** NixOS — отдельный дистрибутив. Неприменим к Ubuntu-образам **[F]**
- **mkosi / Ubuntu:** поддерживает `Distribution=ubuntu`, но требуется systemd v256+ для полной функциональности (vsock SSH). Ubuntu 24.04 = v255 **[F]**

---

## §5. Взвешенные критерии для IWE — Lawful Comparison (A.19)

Общие критерии из §4 имеют разный вес для контекста IWE-тестирования.

| # | Критерий | Вес (1-5) | Обоснование |
|---|----------|:---------:|-------------|
| 1 | Поддержка Ubuntu 24.04 | 5 | IWE = Ubuntu-only. Нет смысла в кроссплатформе |
| 2 | Скорость сборки | 5 | Каждый коммит в FMT-exocortex-template → потенциальная пересборка |
| 3 | 0 новых зависимостей | 4 | Минимизация knowledge coupling (см. §6). Цель: 1 пакет apt |
| 4 | Интеграция с qcow2 snapshots | 4 | Версионирование «из коробки» без внешних инструментов |
| 5 | CI-интеграция (GitHub Actions) | 3 | Будущее требование. Текущий приоритет — локальное тестирование |
| 6 | Воспроизводимость | 3 | Важно, но скорость важнее на текущем этапе (1 контрибьютор) |
| 7 | Кривая обучения | 2 | Обучение — 1 раз. Контрибьюторов — 1 |

### Взвешенная оценка

Максимум = Σ(5 × вес) = 130. Формула: Σ(звёзды × вес).

| Инструмент | Оценка | % от максимума | Детали |
|-----------|:------:|:-------------:|--------|
| **virt-customize** | **110** | **85%** | [F] — проверено в IWE VM. 1 пакет apt. Офлайн |
| Packer QEMU | 75 | 58% | [G] — индустриальный стандарт, но оверхед для 1 образа |
| mkosi | 52 | 40% | [G] — systemd v255 не поддерживает vsock SSH |
| NixOS | — | — | Не Ubuntu. Используется как эталон воспроизводимости |

---

## §6. Coupling Model (SOTA.011) — выбранное решение

Оценка связанности (coupling) тестового пайплайна с инфраструктурой по трём измерениям.

### virt-customize (выбранное)

| Измерение | Оценка | Обоснование |
|-----------|:------:|-------------|
| **Knowledge coupling** (сколько нужно знать о соседней системе) | ★ низкий | libguestfs-tools — 1 пакет apt. Конфигурация — 1 shell-скрипт (~50 строк). Не нужно знать HCL, VNC, cloud-init boot_command |
| **Distance coupling** (насколько далеко соседняя система) | ★ низкий | Host → qemu-img → libguestfs appliance → qcow2. Всё локально, нет сети |
| **Volatility coupling** (как часто меняется контракт) | ★ низкий | libguestfs API стабилен с 2010. apt-пакет обновляется с системой |

**Суммарно:** низкий coupling по всем измерениям.

### Packer QEMU (альтернатива для сравнения)

| Измерение | Оценка | Обоснование |
|-----------|:------:|-------------|
| **Knowledge coupling** | ★★★ средний | HCL-шаблон (~100 строк) + cloud-init autoinstall YAML + boot_command + ssh_timeout. Требуется знание 4 форматов/концепций |
| **Distance coupling** | ★★ низкий | Packer → QEMU process → VNC → SSH → provisioner → shutdown → image. 6 шагов в цепочке |
| **Volatility coupling** | ★★ низкий | Packer plugins версионируются (1.x), breaking changes редки. Но Packer отсутствует в Ubuntu 24.04 repos — нужен ручной install |

**Суммарно:** knowledge coupling выше (4 концепции vs 1 скрипт).

---

## §7. Governance reference

Решение о выборе `virt-customize` + qcow2 snapshots для IWE зафиксировано в:

→ **ADR-007:** Golden Image Build Pipeline for IWE Testing (`docs/adr/ADR-007-golden-image-testing.md`)

**Статус ADR:** Proposed (требует верификации в полном цикле VM)

---

## §8. Архитектура build-golden.sh (реализовано)

> **Реальные скрипты:** `scripts/vm/build-golden.sh`, `scripts/vm/verify-golden.sh`, `scripts/vm/test-from-golden.sh`, `scripts/vm/benchmark-golden.sh`
> **ADR:** `docs/adr/ADR-007-golden-image-testing.md`

```
build-golden.sh (однократный запуск)
│
├─ 1. wget базовый образ (кэшируется)
│     noble-server-cloudimg-amd64.img (~600 MB)
│
├─ 2. virt-customize — Слой 1: системные пакеты (без запуска VM)
│     --install git,gh,ruby,nodejs,npm,expect,jq,shellcheck,vim,mc,libguestfs-tools
│     --run-command 'add-apt-repository -y ppa:neovim-ppa/stable && apt-get install -y neovim'
│     --run-command 'useradd iwe + sudoers + .ssh'
│     --ssh-inject iwe
│     --copy-in packages-firstboot.sh
│     --firstboot packages-firstboot.sh  ← Слой 2: npm-пакеты для iwe
│     --selinux-relabel
│
├─ 3. qemu-img create (copy-on-write от базового)
│     iwe-golden.qcow2 ← noble-server-cloudimg-amd64.img
│
├─ 4. qemu-img snapshot -c "provisioned"
│     Снапшот чистого состояния для быстрого отката
│
└─ 5. sha256sum → iwe-golden.qcow2.sha256
      Контрольная сумма для проверки целостности
```

### Скрипт (референсный)

```bash
#!/usr/bin/env bash
# build-golden.sh — однократная сборка золотого образа IWE
# Запускается при изменении: user-data.yaml, setup.sh, версии репо
set -euo pipefail

REPO_VERSION="${1:-0.25.1}"
BASE_URL="https://cloud-images.ubuntu.com/noble/current"
BASE_IMAGE="noble-server-cloudimg-amd64.img"
GOLDEN_IMAGE="iwe-golden-${REPO_VERSION}.qcow2"
SSH_KEY="$HOME/.ssh/id_ed25519_iwe_test"
FIRSTBOOT_SCRIPT="$(dirname "$0")/packages-firstboot.sh"

# 1. Базовый образ (кэшируется)
if [ ! -f "$BASE_IMAGE" ]; then
  echo "Downloading base image..."
  wget -q --show-progress "$BASE_URL/$BASE_IMAGE"
fi

# 2. Офлайн-модификация — Слой 1: системные пакеты
echo "Customizing image (offline, layer 1: system)..."
virt-customize -a "$BASE_IMAGE" \
  --install git,gh,ruby,nodejs,npm,expect,jq,shellcheck,vim,mc,tmux,curl,ca-certificates,gnupg,build-essential,python3,python3-yaml,software-properties-common \
  --run-command 'add-apt-repository -y ppa:neovim-ppa/stable && apt-get update && apt-get install -y neovim' \
  --run-command 'useradd -m -s /bin/bash iwe && echo "iwe ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/iwe' \
  --run-command 'mkdir -p /home/iwe/IWE /home/iwe/.local/bin /home/iwe/.opencode && chown -R iwe:iwe /home/iwe/IWE /home/iwe/.local /home/iwe/.opencode' \
  --ssh-inject "iwe:file:$SSH_KEY.pub" \
  --copy-in "$FIRSTBOOT_SCRIPT:/home/iwe/" \
  --firstboot /home/iwe/packages-firstboot.sh \
  --selinux-relabel

# 3. qcow2 с backing file
echo "Creating golden image..."
qemu-img create -f qcow2 -b "$BASE_IMAGE" -F qcow2 "$GOLDEN_IMAGE" 20G

# 4. Снапшот
qemu-img snapshot -c "provisioned" "$GOLDEN_IMAGE"

# 5. Контрольная сумма
sha256sum "$GOLDEN_IMAGE" > "$GOLDEN_IMAGE.sha256"

echo "✓ Golden image: $GOLDEN_IMAGE ($(du -sh "$GOLDEN_IMAGE" | cut -f1))"
echo "  Snapshots: $(qemu-img snapshot -l "$GOLDEN_IMAGE" | tail -n +3 | wc -l)"
```

### test-from-golden.sh (каждый прогон тестов)

```bash
#!/usr/bin/env bash
# test-from-golden.sh — быстрый прогон тестов из золотого образа
set -euo pipefail
GOLDEN_IMAGE="iwe-golden-${1:-0.25.1}.qcow2"
TEST_IMAGE="test-ephemeral-$$.qcow2"

# Copy-on-write клон (секунды)
qemu-img create -f qcow2 -b "$GOLDEN_IMAGE" -F qcow2 "$TEST_IMAGE" 20G

# Запуск VM
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -drive file="$TEST_IMAGE",if=virtio \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net,netdev=net0 \
  -display none -daemonize

# Ждать SSH
until ssh -p 2222 -o ConnectTimeout=2 iwe@localhost "echo ready" 2>/dev/null; do
  sleep 2
done

# Прогнать тесты
ssh -p 2222 iwe@localhost "cd ~/IWE/FMT-exocortex-template && bash scripts/vm/run-full-test.sh"

# Очистка
kill $(pgrep -f "qemu-system-x86_64.*$TEST_IMAGE") 2>/dev/null || true
rm -f "$TEST_IMAGE"
```

---

## §9. CI-интеграция (GitHub Actions + self-hosted runner)

**Паттерн:** ephemeral VM = «create, use, discard» в рамках одного CI-job **[F+]**.

```yaml
# .github/workflows/test-iwe.yml
name: IWE VM Tests
on:
  push:
    branches: [0.25.1, main]
  workflow_dispatch:

jobs:
  golden-image-test:
    runs-on: self-hosted  # bare metal / VM с KVM
    timeout-minutes: 30

    steps:
      - uses: actions/checkout@v4

      - name: Create ephemeral VM
        run: |
          qemu-img create -f qcow2 \
            -b iwe-golden-${{ github.ref_name }}.qcow2 \
            -F qcow2 test-${{ github.run_id }}.qcow2

          qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
            -drive file=test-${{ github.run_id }}.qcow2,if=virtio \
            -netdev user,id=net0,hostfwd=tcp::2222-:22 \
            -device virtio-net,netdev=net0 \
            -display none -daemonize

      - name: Wait for SSH
        run: |
          for i in $(seq 1 30); do
            ssh -p 2222 -o ConnectTimeout=2 iwe@localhost "echo ready" 2>/dev/null && break
            sleep 2
          done

      - name: Run test suite
        run: |
          ssh -p 2222 iwe@localhost << 'ENDTEST'
            cd ~/IWE/FMT-exocortex-template
            bash scripts/test/run-phase0.sh
            bash scripts/test/run-e2e.sh
            bash scripts/enforce-semver.sh
            bash scripts/run-migrations.sh 0.0.0 99.99.99
          ENDTEST

      - name: Cleanup (always)
        if: always()
        run: |
          pkill -f "qemu-system-x86_64.*test-${{ github.run_id }}" 2>/dev/null || true
          rm -f test-${{ github.run_id }}.qcow2
```

**SOTA-источники:** Ephemeral environments pattern — production use в Harness, Qovery, Semaphore (2025) **[F+]**. QEMU в GitHub Actions — [Running Ubuntu Minimal Cloud Image with QEMU-KVM and SSH](https://dev.to/vast-cow/running-ubuntu-minimal-cloud-image-with-qemu-kvm-and-ssh-in-github-actions-3lnk) (2025) **[F]**.

---

## §10. Связанные документы

| Документ | Связь |
|----------|-------|
| `docs/adr/ADR-005-update-delivery-architecture.md` | manifest-lib.sh — используется в provision.sh |
| `docs/adr/ADR-007-golden-image-testing.md` | Governance-решение о выборе virt-customize |
| `scripts/vm/provision.sh` | Текущий провижининг (expect-based) |
| `scripts/vm/build-golden.sh` | Сборка золотого образа (cloud-init + SSH provision, 2 слоя) |
| `scripts/vm/test-phases.sh` | Фазы тестирования (Phase 1-4) |

---

*Последнее обновление: 2026-05-03 | F-G-R легенда: [F]=Fact [G]=Guess [R]=Rumor [F+]=Multi-source fact*
