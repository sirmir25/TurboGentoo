#!/usr/bin/env bash
# Kernel installation: dist-kernel (fast) or genkernel (custom)
set -euo pipefail

LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/03-kernel-setup.log"

TG_MOUNTROOT="${TG_MOUNTROOT:-/mnt/gentoo}"
TG_KERNEL_METHOD="${TG_KERNEL_METHOD:-dist-kernel}"  # dist-kernel | genkernel
DRY_RUN="${DRY_RUN:-0}"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; RED='\033[0;31m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || die "Must be run as root"
mkdir -p "${LOG_DIR}"
log "Kernel setup started (method: ${TG_KERNEL_METHOD})"

PARTMAP="${TG_MOUNTROOT}/turbogentoo-partmap.env"
[[ -f "${PARTMAP}" ]] && source "${PARTMAP}"

[[ -f "${TG_MOUNTROOT}/etc/gentoo-release" ]] || die "Stage3 not found at ${TG_MOUNTROOT}"

# ── idempotency ───────────────────────────────────────────────────────────────
if ls "${TG_MOUNTROOT}/boot/vmlinuz-"* &>/dev/null; then
    ok "Kernel already installed — skipping"
    log "03-kernel-setup.sh skipped (already done)"
    exit 0
fi

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
    echo -e "${YELLOW}[DRY-RUN]${RESET} Would install kernel via ${TG_KERNEL_METHOD}"
    exit 0
fi

mount_pseudo

case "${TG_KERNEL_METHOD}" in
    dist-kernel)
        log "Installing sys-kernel/gentoo-kernel-bin (dist-kernel)..."
        chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
set -euo pipefail
source /etc/profile

# dist-kernel-bin: pre-built, fastest option
emerge --ask=n sys-kernel/gentoo-kernel-bin sys-kernel/linux-firmware

# Build initramfs
kernel_ver="$(ls /usr/src/ | grep linux | sort -V | tail -1 | sed 's/linux-//')"
if [[ -n "${kernel_ver}" ]]; then
    dracut --force --kver "${kernel_ver}" /boot/initramfs-${kernel_ver}.img 2>/dev/null \
        || genkernel --install initramfs 2>/dev/null \
        || true
fi
echo "dist-kernel installed"
CHROOT_EOF
        ;;

    genkernel)
        log "Installing and running genkernel (compiles kernel — slower)..."
        chroot "${TG_MOUNTROOT}" /bin/bash -l <<'CHROOT_EOF'
set -euo pipefail
source /etc/profile

emerge --ask=n sys-kernel/gentoo-sources sys-kernel/genkernel sys-kernel/linux-firmware

# Use default config + enable common options
genkernel \
    --makeopts="$(grep MAKEOPTS /etc/portage/make.conf | cut -d'"' -f2 || echo '-j4')" \
    --no-clean \
    --no-menuconfig \
    --save-config \
    all

echo "genkernel done"
CHROOT_EOF
        ;;

    *)
        die "Unknown kernel method: ${TG_KERNEL_METHOD}. Use 'dist-kernel' or 'genkernel'"
        ;;
esac

ok "Kernel installation complete"
log "03-kernel-setup.sh finished successfully"
echo
echo -e "${GREEN}${BOLD}Kernel ready. Next: bash scripts/04-bootloader.sh${RESET}"
