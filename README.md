# TurboGentoo

Автоматизированная установка Gentoo Linux с лёгким оконным менеджером.  
Превращает процесс, который обычно занимает день, в 1–3 часа (с binpkg — ещё быстрее).

---

## Для кого

- Хочешь Gentoo, но устал от ручной установки по вики
- Нужен минималистичный рабочий стол без лишнего (i3 / sway / openbox)
- Любишь полный контроль, но не хочешь каждый раз делать одно и то же вручную

---

## Требования

- **Загрузочный образ**: [Gentoo minimal install CD](https://www.gentoo.org/downloads/) (amd64)
- **Интернет**: обязателен на протяжении всей установки
- **Диск**: ≥ 20 ГБ (рекомендуется ≥ 40 ГБ для desktop/dev профиля)
- **RAM**: ≥ 2 ГБ (≥ 4 ГБ для комфортной компиляции)
- **Архитектура**: x86_64 (amd64)
- **Прошивка**: UEFI (GPT) — основной путь; BIOS/MBR поддерживается флагом

---

## Быстрый старт — одна команда с любого дистрибутива

Работает из **Debian, Ubuntu, Arch, Fedora, openSUSE, Alpine** и с Gentoo live CD.  
Скрипт сам определит дистрибутив, установит зависимости и запустит установку.

```bash
# Запуск с параметрами по умолчанию (диск определяется автоматически)
sudo bash <(curl -fsSL https://raw.githubusercontent.com/sirmir25/TurboGentoo/main/bootstrap.sh)

# Указать диск, WM и профиль явно
sudo bash <(curl -fsSL https://raw.githubusercontent.com/sirmir25/TurboGentoo/main/bootstrap.sh) \
    --disk /dev/sda --wm i3 --profile desktop

# Предпросмотр без изменений
sudo bash <(curl -fsSL https://raw.githubusercontent.com/sirmir25/TurboGentoo/main/bootstrap.sh) \
    --dry-run
```

Либо клонируй репо и запускай локально:

```bash
git clone https://github.com/sirmir25/TurboGentoo.git && cd TurboGentoo
sudo bash bootstrap.sh --disk /dev/sda --wm i3 --profile desktop
```

### Поддерживаемые дистрибутивы для запуска

| Дистрибутив | Пакетный менеджер | Статус |
|---|---|---|
| Debian / Ubuntu / Mint | apt | ✅ |
| Arch / Manjaro / EndeavourOS | pacman | ✅ |
| Fedora | dnf | ✅ |
| CentOS / RHEL / AlmaLinux / Rocky | dnf | ✅ |
| openSUSE | zypper | ✅ |
| Alpine | apk | ✅ |
| Gentoo live CD | portage/built-in | ✅ |

> Устанавливается **Gentoo** на целевой диск, независимо от того, с какого дистрибутива запущен скрипт.

---

## Запуск по шагам (с Gentoo live CD)

```bash
# 1. Загрузись с Gentoo minimal install CD

# 2. Настрой сеть (если не поднялась автоматически)
net-setup eth0   # или: dhcpcd eth0

# 3. Скачай TurboGentoo
wget https://github.com/sirmir25/TurboGentoo/archive/refs/heads/main.tar.gz
tar xzf main.tar.gz && cd TurboGentoo-main

# 4. Запусти bootstrap (определит диск и настройки автоматически)
sudo bash bootstrap.sh

# 5. После перезагрузки — логин в WM
```

Либо запускай скрипты по одному вручную для полного контроля (см. ниже).

---

## Ручной запуск по шагам

```bash
# Шаг 0: разметка диска
bash scripts/00-prepare-disk.sh

# Шаг 1: установка stage3
bash scripts/01-stage3-install.sh

# Шаг 2: базовая конфигурация (make.conf, fstab, локаль, timezone)
bash scripts/02-base-config.sh

# Шаг 3: ядро
bash scripts/03-kernel-setup.sh

# Шаг 4: загрузчик
bash scripts/04-bootloader.sh

# Шаг 5: оконный менеджер
bash scripts/05-wm-install.sh

# Шаг 6: пост-установка (пользователь, dotfiles, приложения)
bash scripts/06-post-install.sh
```

Каждый скрипт **идемпотентен** — при повторном запуске не ломает систему.

---

## Переменные конфигурации

| Переменная | По умолчанию | Описание |
|---|---|---|
| `TG_DISK` | `/dev/sda` | Целевой диск для установки |
| `TG_HOSTNAME` | `gentoo` | Имя хоста |
| `TG_TIMEZONE` | `Europe/Moscow` | Временная зона |
| `TG_LOCALE` | `en_US.UTF-8` | Основная локаль |
| `TG_USERNAME` | `user` | Имя первого пользователя |
| `TG_WM` | `i3` | Оконный менеджер: `i3` / `sway` / `openbox` |
| `TG_PROFILE` | `desktop` | Профиль: `minimal` / `desktop` / `dev` |
| `TG_USE_BINPKG` | `1` | Использовать бинарные пакеты Gentoo (ускоряет установку) |
| `TG_BOOT_MODE` | `uefi` | Режим загрузки: `uefi` / `bios` |
| `TG_EFI_SIZE` | `512M` | Размер EFI-раздела |
| `TG_SWAP_SIZE` | `4G` | Размер swap-раздела (`0` — отключить) |
| `TG_CFLAGS` | `-O2 -pipe -march=native` | Флаги компилятора |
| `TG_MIRROR` | `https://distfiles.gentoo.org` | Зеркало Gentoo |
| `TG_STAGE3_VARIANT` | `openrc` | Вариант stage3: `openrc` / `systemd` |
| `TG_KERNEL_METHOD` | `dist-kernel` | Метод ядра: `dist-kernel` / `genkernel` |

---

## Профили

### `minimal.conf`
Только система + выбранный WM + терминал.  
~1–1.5 часа с binpkg, ~3–4 часа без.

### `desktop.conf`
Minimal + браузер (firefox-bin), файловый менеджер (thunar), аудио (pipewire), уведомления (dunst).  
~1.5–2.5 часа с binpkg, ~5–8 часов без.

### `dev.conf`
Desktop + git, neovim, базовые build-инструменты, опциональные языковые тулчейны.  
~2–3 часа с binpkg, ~8–12 часов без.

---

## Поддерживаемые оконные менеджеры

| WM | Протокол | Статусбар | Терминал | Характеристика |
|---|---|---|---|---|
| **i3** | X11 | i3status | alacritty | Классический tiling, огромная экосистема |
| **sway** | Wayland | waybar | alacritty | Современный, HiDPI из коробки |
| **openbox** | X11 | tint2 | alacritty | Floating, минимальное потребление RAM |

---

## Оценка времени установки

| Профиль | С binpkg | Без binpkg (компиляция) |
|---|---|---|
| minimal | ~60–90 мин | ~3–5 часов |
| desktop | ~90–150 мин | ~6–10 часов |
| dev | ~120–180 мин | ~10–16 часов |

> Время зависит от скорости интернета, количества ядер и скорости диска.  
> binpkg доступен через `FEATURES="getbinpkg"` и зеркало `https://binpkgs.gentoo.org`.

---

## Troubleshooting

### Диск не размечается / gdisk не видит диск
```bash
ls /dev/sd* /dev/nvme*   # найди правильное имя диска
lsblk                     # проверь структуру
```
Убедись, что передаёшь правильное значение `TG_DISK`.

### GRUB не устанавливается (UEFI)
```bash
# Проверь, смонтирован ли EFI раздел
mount | grep /boot/efi
# Убедись, что модуль efivars загружен
ls /sys/firmware/efi/efivars
```
Если папка пустая — система загружена в BIOS-режиме, используй `TG_BOOT_MODE=bios`.

### Нет сети после установки
```bash
# Включи нужный интерфейс
rc-update add dhcpcd default   # OpenRC
# или для NetworkManager
rc-update add NetworkManager default
```

### Ошибка "no space left" при компиляции
Убедись, что на разделе `/` достаточно места. Emerge использует `/var/tmp/portage` — при нехватке места выдаст именно эту ошибку.  
```bash
df -h /var/tmp/portage
```

### Видеодрайверы: чёрный экран после запуска X/Wayland
- **NVIDIA**: добавь `VIDEO_CARDS="nvidia"` в `make.conf`, установи `x11-drivers/nvidia-drivers`
- **AMD**: `VIDEO_CARDS="amdgpu radeonsi"`, ядро должно поддерживать `CONFIG_DRM_AMDGPU`
- **Intel**: `VIDEO_CARDS="intel i965"`, нужен `xf86-video-intel` или `modesetting`

### emerge зависает или конфликт пакетов
```bash
emerge --ask --update --deep --newuse @world
# Если конфликт USE-флагов:
emerge --ask --deselect <package>
```

### sway не запускается (Wayland / нет KMS)
Sway требует KMS и поддержку DRM в ядре. С `dist-kernel` это обычно уже есть.  
Запускай sway из TTY, не из X-сессии.

---

## Структура проекта

```
turbogentoo/
├── install.sh                    # оркестратор всех шагов
├── README.md
├── .gitignore
├── scripts/
│   ├── 00-prepare-disk.sh        # разметка, форматирование, монтирование
│   ├── 01-stage3-install.sh      # скачивание и распаковка stage3
│   ├── 02-base-config.sh         # make.conf, fstab, локаль, timezone
│   ├── 03-kernel-setup.sh        # ядро (dist-kernel / genkernel)
│   ├── 04-bootloader.sh          # GRUB / systemd-boot
│   ├── 05-wm-install.sh          # X11/Wayland + WM + конфиги
│   └── 06-post-install.sh        # пользователь, dotfiles, приложения
├── configs/
│   ├── make.conf.template        # оптимизированный шаблон make.conf
│   ├── package.use/              # USE-флаги по пакетам
│   ├── package.accept_keywords/  # ~amd64 для нестабильных пакетов
│   └── wm/
│       ├── i3/                   # конфиги i3 + i3status
│       ├── sway/                 # конфиги sway + waybar
│       └── openbox/              # конфиги openbox + tint2
└── profiles/
    ├── minimal.conf
    ├── desktop.conf
    └── dev.conf
```

---

## Лицензия

MIT © 2024 TurboGentoo contributors
