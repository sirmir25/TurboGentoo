#!/usr/bin/env bash
# Install X11/Wayland + window manager + status bar + terminal
set -euo pipefail

LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/05-wm-install.log"

TG_MOUNTROOT="${TG_MOUNTROOT:-/mnt/gentoo}"
TG_WM="${TG_WM:-i3}"           # i3 | sway | openbox
TG_PROFILE="${TG_PROFILE:-desktop}"
DRY_RUN="${DRY_RUN:-0}"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Must be run as root"
mkdir -p "${LOG_DIR}"
log "WM installation started (WM: ${TG_WM}, profile: ${TG_PROFILE})"

PARTMAP="${TG_MOUNTROOT}/turbogentoo-partmap.env"
[[ -f "${PARTMAP}" ]] && source "${PARTMAP}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mount_pseudo() {
    for fs in proc sys dev; do
        mountpoint -q "${TG_MOUNTROOT}/${fs}" 2>/dev/null && continue
        case "${fs}" in
            proc) mount -t proc proc "${TG_MOUNTROOT}/proc" ;;
            sys)  mount --rbind /sys "${TG_MOUNTROOT}/sys" && mount --make-rslave "${TG_MOUNTROOT}/sys" ;;
            dev)  mount --rbind /dev "${TG_MOUNTROOT}/dev" && mount --make-rslave "${TG_MOUNTROOT}/dev" ;;
        esac
    done
}

# ── package lists by WM ───────────────────────────────────────────────────────
pkgs_common="app-shells/bash app-editors/vim sys-apps/dbus"

pkgs_i3="
    x11-base/xorg-server
    x11-apps/xrandr
    x11-misc/i3
    x11-misc/i3status
    x11-misc/i3lock
    x11-misc/dmenu
    x11-terms/alacritty
    x11-misc/dunst
    x11-misc/picom
    media-gfx/feh
"

pkgs_sway="
    gui-wm/sway
    gui-apps/waybar
    gui-apps/swaylock
    gui-apps/swayidle
    gui-apps/wofi
    x11-terms/alacritty
    gui-apps/mako
    gui-apps/grim
    gui-apps/slurp
"

pkgs_openbox="
    x11-base/xorg-server
    x11-apps/xrandr
    x11-wm/openbox
    x11-misc/tint2
    x11-misc/obconf
    x11-misc/obmenu
    x11-misc/dmenu
    x11-terms/alacritty
    x11-misc/dunst
    x11-misc/picom
    media-gfx/feh
"

pkgs_desktop_extra="
    www-client/firefox-bin
    app-misc/thunar
    media-sound/pipewire
    media-video/pipewire
    media-libs/pavucontrol-qt
    media-gfx/imv
    app-text/zathura
    app-text/zathura-pdf-poppler
"

pkgs_dev_extra="
    dev-vcs/git
    app-editors/neovim
    sys-devel/gcc
    sys-devel/make
    dev-util/cmake
    dev-util/meson
    app-shells/zsh
    app-misc/tmux
    dev-util/strace
    net-misc/curl
    app-arch/unzip
"

# ── install ───────────────────────────────────────────────────────────────────
build_pkg_list() {
    local pkgs="${pkgs_common}"
    case "${TG_WM}" in
        i3)      pkgs="${pkgs} ${pkgs_i3}" ;;
        sway)    pkgs="${pkgs} ${pkgs_sway}" ;;
        openbox) pkgs="${pkgs} ${pkgs_openbox}" ;;
        *)       die "Unknown WM: ${TG_WM}" ;;
    esac
    case "${TG_PROFILE}" in
        desktop) pkgs="${pkgs} ${pkgs_desktop_extra}" ;;
        dev)     pkgs="${pkgs} ${pkgs_desktop_extra} ${pkgs_dev_extra}" ;;
    esac
    echo "${pkgs}"
}

if [[ "${DRY_RUN}" == "1" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} Would install packages for WM=${TG_WM}, profile=${TG_PROFILE}:"
    build_pkg_list
    exit 0
fi

mount_pseudo

PKG_LIST="$(build_pkg_list)"
log "Installing packages..."

chroot "${TG_MOUNTROOT}" /bin/bash -l <<CHROOT_EOF
set -euo pipefail
source /etc/profile
# shellcheck disable=SC2086
emerge --ask=n --noreplace ${PKG_LIST}
CHROOT_EOF

ok "Packages installed"

# ── copy WM configs ───────────────────────────────────────────────────────────
install_wm_configs() {
    local cfg_src="${SCRIPT_DIR}/configs/wm/${TG_WM}"
    local cfg_dst="${TG_MOUNTROOT}/etc/skel/.config/${TG_WM}"

    if [[ -d "${cfg_src}" ]]; then
        mkdir -p "${cfg_dst}"
        cp -r "${cfg_src}/." "${cfg_dst}/"
        ok "WM configs copied from ${cfg_src}"
    else
        log "No WM config directory found at ${cfg_src}, skipping"
    fi
}

install_wm_configs

# ── xinit / display manager setup ─────────────────────────────────────────────
setup_xinit() {
    local xinitrc="${TG_MOUNTROOT}/etc/skel/.xinitrc"
    case "${TG_WM}" in
        i3)
            cat > "${xinitrc}" <<'EOF'
#!/bin/sh
exec i3
EOF
            ;;
        openbox)
            cat > "${xinitrc}" <<'EOF'
#!/bin/sh
exec openbox-session
EOF
            ;;
        sway)
            # sway is started directly from TTY, not via xinit
            local sway_env="${TG_MOUNTROOT}/etc/skel/.profile"
            grep -q "sway" "${sway_env}" 2>/dev/null || cat >> "${sway_env}" <<'EOF'

# Auto-start sway on TTY1 login
if [[ -z "${WAYLAND_DISPLAY}" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    exec sway
fi
EOF
            ;;
    esac
    chmod +x "${xinitrc}" 2>/dev/null || true
    ok "Login setup done for ${TG_WM}"
}

setup_xinit

# ── enable services ───────────────────────────────────────────────────────────
chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
set -euo pipefail
source /etc/profile

rc-update add dbus default 2>/dev/null || true

if command -v pipewire &>/dev/null; then
    rc-update add pipewire default 2>/dev/null || true
fi

if command -v NetworkManager &>/dev/null; then
    rc-update add NetworkManager default
elif command -v dhcpcd &>/dev/null; then
    rc-update add dhcpcd default
fi
CHROOT_EOF

ok "Services enabled"
log "05-wm-install.sh finished successfully"
echo
echo -e "${GREEN}${BOLD}WM installed. Next: bash scripts/06-post-install.sh${RESET}"
