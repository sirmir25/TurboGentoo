#!/usr/bin/env bash
# Post-install: create user, set passwords, copy dotfiles, final cleanup
set -euo pipefail

LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/06-post-install.log"

TG_MOUNTROOT="${TG_MOUNTROOT:-/mnt/gentoo}"
TG_USERNAME="${TG_USERNAME:-user}"
TG_WM="${TG_WM:-i3}"
TG_PROFILE="${TG_PROFILE:-desktop}"
DRY_RUN="${DRY_RUN:-0}"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Must be run as root"
mkdir -p "${LOG_DIR}"
log "Post-install started (user: ${TG_USERNAME})"

PARTMAP="${TG_MOUNTROOT}/turbogentoo-partmap.env"
[[ -f "${PARTMAP}" ]] && source "${PARTMAP}"

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

if [[ "${DRY_RUN}" == "1" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} Would create user '${TG_USERNAME}', set passwords, copy dotfiles"
    exit 0
fi

mount_pseudo

# ── set root password ─────────────────────────────────────────────────────────
log "Set root password for the new system:"
chroot "${TG_MOUNTROOT}" /bin/bash -c "passwd root"

# ── create user ───────────────────────────────────────────────────────────────
log "Creating user '${TG_USERNAME}'..."
chroot "${TG_MOUNTROOT}" /bin/bash -l <<CHROOT_EOF
set -euo pipefail
source /etc/profile

if id "${TG_USERNAME}" &>/dev/null; then
    echo "User ${TG_USERNAME} already exists — skipping creation"
else
    useradd -m -G wheel,audio,video,usb,cdrom,portage -s /bin/bash "${TG_USERNAME}"
    echo "User ${TG_USERNAME} created"
fi
CHROOT_EOF

log "Set password for user '${TG_USERNAME}':"
chroot "${TG_MOUNTROOT}" /bin/bash -c "passwd ${TG_USERNAME}"

# ── sudo setup ────────────────────────────────────────────────────────────────
chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
set -euo pipefail
source /etc/profile

emerge --ask=n app-admin/sudo 2>/dev/null || true
# Uncomment wheel group in sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
CHROOT_EOF
ok "sudo configured for wheel group"

# ── essential services ────────────────────────────────────────────────────────
chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
source /etc/profile

rc-update add syslog-ng default 2>/dev/null \
    || rc-update add metalog default 2>/dev/null \
    || true

rc-update add cronie default 2>/dev/null || rc-update add dcron default 2>/dev/null || true
rc-update add sshd default 2>/dev/null || true
CHROOT_EOF
ok "Essential services enabled"

# ── copy alacritty config ─────────────────────────────────────────────────────
mkdir -p "${TG_MOUNTROOT}/etc/skel/.config/alacritty"
cat > "${TG_MOUNTROOT}/etc/skel/.config/alacritty/alacritty.toml" <<'EOF'
[font]
size = 11.0

[font.normal]
family = "monospace"
style = "Regular"

[window]
padding = { x = 8, y = 8 }
decorations = "none"

[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"

[colors.normal]
black   = "#45475a"
red     = "#f38ba8"
green   = "#a6e3a1"
yellow  = "#f9e2af"
blue    = "#89b4fa"
magenta = "#f5c2e7"
cyan    = "#94e2d5"
white   = "#bac2de"
EOF
ok "Alacritty config installed"

# ── shell profile for user ────────────────────────────────────────────────────
cat >> "${TG_MOUNTROOT}/etc/skel/.bashrc" <<'EOF'

# TurboGentoo defaults
export EDITOR=vim
export TERMINAL=alacritty
alias ls='ls --color=auto'
alias ll='ls -lah'
alias grep='grep --color=auto'

# XDG
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"
EOF
ok ".bashrc defaults added"

# ── copy skel to new user ─────────────────────────────────────────────────────
chroot "${TG_MOUNTROOT}" /bin/bash -c "cp -rn /etc/skel/. /home/${TG_USERNAME}/ 2>/dev/null || true"
chroot "${TG_MOUNTROOT}" /bin/bash -c "chown -R ${TG_USERNAME}:${TG_USERNAME} /home/${TG_USERNAME}"
ok "Skeleton files copied to /home/${TG_USERNAME}"

# ── final world update ────────────────────────────────────────────────────────
log "Running final @world update (may take a while)..."
chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
source /etc/profile
emerge --ask=n --update --deep --newuse @world 2>/dev/null || true
CHROOT_EOF

# ── cleanup ───────────────────────────────────────────────────────────────────
chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
source /etc/profile
emerge --ask=n --depclean 2>/dev/null || true
eclean-dist --deep 2>/dev/null || true
CHROOT_EOF

log "06-post-install.sh finished successfully"

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${GREEN}${BOLD}║         TurboGentoo installation complete!               ║${RESET}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "  User     : ${BOLD}${TG_USERNAME}${RESET}"
echo -e "  WM       : ${BOLD}${TG_WM}${RESET}"
echo -e "  Profile  : ${BOLD}${TG_PROFILE}${RESET}"
echo
echo -e "  To unmount and reboot:"
echo -e "  ${CYAN}cd / && umount -R ${TG_MOUNTROOT} && reboot${RESET}"
echo
