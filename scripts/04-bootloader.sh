#!/usr/bin/env bash
# Install and configure GRUB bootloader (UEFI or BIOS)
set -euo pipefail

LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/04-bootloader.log"

TG_MOUNTROOT="${TG_MOUNTROOT:-/mnt/gentoo}"
TG_BOOT_MODE="${TG_BOOT_MODE:-uefi}"
TG_HOSTNAME="${TG_HOSTNAME:-gentoo}"
DRY_RUN="${DRY_RUN:-0}"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Must be run as root"
mkdir -p "${LOG_DIR}"
log "Bootloader setup started (mode: ${TG_BOOT_MODE})"

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
    # efivars needed for UEFI grub-install
    if [[ "${TG_BOOT_MODE}" == "uefi" ]] && ! mountpoint -q "${TG_MOUNTROOT}/sys/firmware/efi/efivars" 2>/dev/null; then
        mount --bind /sys/firmware/efi/efivars "${TG_MOUNTROOT}/sys/firmware/efi/efivars" 2>/dev/null || true
    fi
}

if [[ "${DRY_RUN}" == "1" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} Would install GRUB (${TG_BOOT_MODE}) on ${TG_DISK:-/dev/sda}"
    exit 0
fi

mount_pseudo

DISK="${TG_DISK:-/dev/sda}"
BOOT_MODE="${TG_BOOT_MODE}"

chroot "${TG_MOUNTROOT}" /bin/bash -l <<CHROOT_EOF
set -euo pipefail
source /etc/profile

# Install GRUB package
emerge --ask=n sys-boot/grub sys-boot/os-prober

if [[ "${BOOT_MODE}" == "uefi" ]]; then
    grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id=Gentoo \
        --recheck \
        "${DISK}"
else
    grub-install \
        --target=i386-pc \
        --recheck \
        "${DISK}"
fi

# Write GRUB config
cat > /etc/default/grub <<'GRUBCFG'
GRUB_DISTRIBUTOR="TurboGentoo"
GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"
GRUB_CMDLINE_LINUX=""
GRUB_TIMEOUT=3
GRUB_DEFAULT=0
GRUBCFG

grub-mkconfig -o /boot/grub/grub.cfg

echo "GRUB installed and configured"
CHROOT_EOF

ok "Bootloader installed"
log "04-bootloader.sh finished successfully"
echo
echo -e "${GREEN}${BOLD}Bootloader ready. Next: bash scripts/05-wm-install.sh${RESET}"
