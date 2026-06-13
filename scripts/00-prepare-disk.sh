#!/usr/bin/env bash
# Disk partitioning, formatting, and mounting for TurboGentoo
# Supports UEFI+GPT (default) and BIOS+MBR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/00-prepare-disk.log"

# ── defaults (override via environment or config file) ──────────────────────
TG_DISK="${TG_DISK:-/dev/sda}"
TG_BOOT_MODE="${TG_BOOT_MODE:-uefi}"   # uefi | bios
TG_EFI_SIZE="${TG_EFI_SIZE:-512M}"
TG_SWAP_SIZE="${TG_SWAP_SIZE:-4G}"     # 0 = no swap
TG_MOUNTROOT="${TG_MOUNTROOT:-/mnt/gentoo}"
TG_FS_ROOT="${TG_FS_ROOT:-ext4}"       # ext4 | btrfs | xfs
DRY_RUN="${DRY_RUN:-0}"

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── helpers ──────────────────────────────────────────────────────────────────
log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
warn(){ echo -e "${YELLOW}[WARN]${RESET} $*" | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

run() {
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo -e "${YELLOW}[DRY-RUN]${RESET} $*"
    else
        log "Executing: $*"
        "$@"
    fi
}

init_log() {
    if [[ "${DRY_RUN}" != "1" ]]; then
        mkdir -p "${LOG_DIR}"
        touch "${LOG_FILE}"
    fi
    log "TurboGentoo — disk preparation started"
    log "  DISK      : ${TG_DISK}"
    log "  BOOT MODE : ${TG_BOOT_MODE}"
    log "  FS ROOT   : ${TG_FS_ROOT}"
    log "  EFI SIZE  : ${TG_EFI_SIZE}  (ignored in bios mode)"
    log "  SWAP SIZE : ${TG_SWAP_SIZE}  (0 = disabled)"
    log "  MOUNT ROOT: ${TG_MOUNTROOT}"
}

# ── validation ───────────────────────────────────────────────────────────────
check_root() {
    [[ "${EUID}" -eq 0 ]] || die "Must be run as root"
}

check_disk() {
    [[ -b "${TG_DISK}" ]] || die "Block device not found: ${TG_DISK}"
}

check_uefi() {
    if [[ "${TG_BOOT_MODE}" == "uefi" ]] && [[ ! -d /sys/firmware/efi ]]; then
        warn "EFI variables not found at /sys/firmware/efi."
        warn "The system may be booted in BIOS mode."
        warn "If you intended BIOS mode, set TG_BOOT_MODE=bios and re-run."
        echo
        read -rp "Continue with UEFI partitioning anyway? [y/N] " _ans
        [[ "${_ans}" =~ ^[Yy]$ ]] || die "Aborted by user."
    fi
}

check_tools() {
    local missing=()
    local needed=(parted mkfs.fat mkfs.ext4 mkswap mount)
    [[ "${TG_BOOT_MODE}" == "uefi" ]] && needed+=(sgdisk)
    [[ "${TG_BOOT_MODE}" == "bios" ]] && needed+=(fdisk)
    [[ "${TG_FS_ROOT}" == "btrfs" ]] && needed+=(mkfs.btrfs)
    [[ "${TG_FS_ROOT}" == "xfs"   ]] && needed+=(mkfs.xfs)

    for t in "${needed[@]}"; do
        command -v "${t}" &>/dev/null || missing+=("${t}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing tools: ${missing[*]}\nInstall them and re-run."
    fi
}

# ── confirmation prompt ───────────────────────────────────────────────────────
confirm_destructive() {
    echo
    echo -e "${RED}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}${BOLD}║  WARNING: ALL DATA ON ${TG_DISK} WILL BE DESTROYED!  ║${RESET}"
    echo -e "${RED}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  Disk   : ${BOLD}${TG_DISK}${RESET}"
    echo -e "  Mode   : ${BOLD}${TG_BOOT_MODE^^}${RESET}"

    # Show current disk info if possible
    if command -v lsblk &>/dev/null; then
        echo
        echo -e "${CYAN}Current disk layout:${RESET}"
        lsblk "${TG_DISK}" 2>/dev/null || true
    fi

    echo
    echo -e "Type ${BOLD}YES${RESET} (in uppercase) to confirm you want to erase ${TG_DISK}:"
    read -rp "> " _confirmation
    if [[ "${_confirmation}" != "YES" ]]; then
        die "Aborted — disk was not modified."
    fi
    echo
}

# ── partition number helper ───────────────────────────────────────────────────
part() {
    # /dev/sda  → /dev/sda1
    # /dev/nvme0n1 → /dev/nvme0n1p1
    if [[ "${TG_DISK}" =~ nvme|mmcblk ]]; then
        echo "${TG_DISK}p${1}"
    else
        echo "${TG_DISK}${1}"
    fi
}

# ── UEFI + GPT partitioning ──────────────────────────────────────────────────
partition_uefi() {
    log "Partitioning ${TG_DISK} for UEFI/GPT..."

    run sgdisk --zap-all "${TG_DISK}"
    run sgdisk --clear "${TG_DISK}"

    # Partition 1 — EFI System Partition
    run sgdisk --new=1:0:+"${TG_EFI_SIZE}" \
               --typecode=1:ef00 \
               --change-name=1:"EFI" \
               "${TG_DISK}"

    if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
        # Partition 2 — swap
        run sgdisk --new=2:0:+"${TG_SWAP_SIZE}" \
                   --typecode=2:8200 \
                   --change-name=2:"swap" \
                   "${TG_DISK}"
        # Partition 3 — root (rest of disk)
        run sgdisk --new=3:0:0 \
                   --typecode=3:8304 \
                   --change-name=3:"root" \
                   "${TG_DISK}"
    else
        # Partition 2 — root (rest of disk)
        run sgdisk --new=2:0:0 \
                   --typecode=2:8304 \
                   --change-name=2:"root" \
                   "${TG_DISK}"
    fi

    run sgdisk --print "${TG_DISK}"
    ok "GPT partitioning done"
}

# ── BIOS + MBR partitioning ──────────────────────────────────────────────────
partition_bios() {
    log "Partitioning ${TG_DISK} for BIOS/MBR..."

    if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
        run parted -s "${TG_DISK}" \
            mklabel msdos \
            mkpart primary linux-swap 1MiB "${TG_SWAP_SIZE}" \
            mkpart primary "${TG_FS_ROOT}" "${TG_SWAP_SIZE}" 100% \
            set 2 boot on
    else
        run parted -s "${TG_DISK}" \
            mklabel msdos \
            mkpart primary "${TG_FS_ROOT}" 1MiB 100% \
            set 1 boot on
    fi

    ok "MBR partitioning done"
}

# ── wait for kernel to re-read partition table ───────────────────────────────
settle_partitions() {
    if [[ "${DRY_RUN}" != "1" ]]; then
        run partprobe "${TG_DISK}" 2>/dev/null || true
        run udevadm settle 2>/dev/null || true
        sleep 1
    fi
}

# ── formatting ───────────────────────────────────────────────────────────────
format_uefi() {
    log "Formatting partitions (UEFI)..."
    local efi_part swap_part root_part

    efi_part="$(part 1)"
    if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
        swap_part="$(part 2)"
        root_part="$(part 3)"
    else
        root_part="$(part 2)"
    fi

    run mkfs.fat -F32 -n "EFI" "${efi_part}"
    ok "EFI formatted: ${efi_part}"

    if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
        run mkswap -L "swap" "${swap_part}"
        ok "Swap formatted: ${swap_part}"
    fi

    format_root "${root_part}"
}

format_bios() {
    log "Formatting partitions (BIOS)..."
    local swap_part root_part

    if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
        swap_part="$(part 1)"
        root_part="$(part 2)"
        run mkswap -L "swap" "${swap_part}"
        ok "Swap formatted: ${swap_part}"
    else
        root_part="$(part 1)"
    fi

    format_root "${root_part}"
}

format_root() {
    local dev="$1"
    case "${TG_FS_ROOT}" in
        ext4)
            run mkfs.ext4 -L "gentoo" -O dir_index,filetype,extent,flex_bg,sparse_super \
                -m 0 "${dev}"
            ;;
        btrfs)
            run mkfs.btrfs -L "gentoo" -f "${dev}"
            ;;
        xfs)
            run mkfs.xfs -L "gentoo" -f "${dev}"
            ;;
        *)
            die "Unsupported filesystem: ${TG_FS_ROOT}"
            ;;
    esac
    ok "Root formatted (${TG_FS_ROOT}): ${dev}"
}

# ── mounting ─────────────────────────────────────────────────────────────────
mount_partitions() {
    log "Mounting partitions to ${TG_MOUNTROOT}..."

    local root_part
    if [[ "${TG_BOOT_MODE}" == "uefi" ]]; then
        if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
            root_part="$(part 3)"
        else
            root_part="$(part 2)"
        fi
    else
        if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
            root_part="$(part 2)"
        else
            root_part="$(part 1)"
        fi
    fi

    run mkdir -p "${TG_MOUNTROOT}"
    run mount "${root_part}" "${TG_MOUNTROOT}"
    ok "Root mounted: ${root_part} → ${TG_MOUNTROOT}"

    if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
        local swap_part
        if [[ "${TG_BOOT_MODE}" == "uefi" ]]; then
            swap_part="$(part 2)"
        else
            swap_part="$(part 1)"
        fi
        run swapon "${swap_part}"
        ok "Swap activated: ${swap_part}"
    fi

    if [[ "${TG_BOOT_MODE}" == "uefi" ]]; then
        local efi_part
        efi_part="$(part 1)"
        run mkdir -p "${TG_MOUNTROOT}/boot/efi"
        run mount "${efi_part}" "${TG_MOUNTROOT}/boot/efi"
        ok "EFI mounted: ${efi_part} → ${TG_MOUNTROOT}/boot/efi"
    else
        run mkdir -p "${TG_MOUNTROOT}/boot"
    fi
}

# ── export partition map for downstream scripts ───────────────────────────────
export_partition_map() {
    local map_file="${TG_MOUNTROOT}/turbogentoo-partmap.env"

    if [[ "${DRY_RUN}" == "1" ]]; then
        log "[DRY-RUN] Would write partition map to ${map_file}"
        return
    fi

    {
        echo "# Generated by TurboGentoo 00-prepare-disk.sh"
        echo "TG_DISK='${TG_DISK}'"
        echo "TG_BOOT_MODE='${TG_BOOT_MODE}'"
        echo "TG_FS_ROOT='${TG_FS_ROOT}'"
        echo "TG_MOUNTROOT='${TG_MOUNTROOT}'"
        if [[ "${TG_BOOT_MODE}" == "uefi" ]]; then
            echo "TG_PART_EFI='$(part 1)'"
            if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
                echo "TG_PART_SWAP='$(part 2)'"
                echo "TG_PART_ROOT='$(part 3)'"
            else
                echo "TG_PART_SWAP=''"
                echo "TG_PART_ROOT='$(part 2)'"
            fi
        else
            echo "TG_PART_EFI=''"
            if [[ "${TG_SWAP_SIZE}" != "0" ]]; then
                echo "TG_PART_SWAP='$(part 1)'"
                echo "TG_PART_ROOT='$(part 2)'"
            else
                echo "TG_PART_SWAP=''"
                echo "TG_PART_ROOT='$(part 1)'"
            fi
        fi
    } > "${map_file}"

    ok "Partition map written to ${map_file}"
}

# ── summary ──────────────────────────────────────────────────────────────────
print_summary() {
    echo
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}  Disk preparation complete!${RESET}"
    echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════${RESET}"
    if [[ "${DRY_RUN}" != "1" ]]; then
        echo
        lsblk "${TG_DISK}"
        echo
        echo -e "  Next step: ${BOLD}bash scripts/01-stage3-install.sh${RESET}"
    fi
    echo
}

# ── usage ────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: ${0} [OPTIONS]

Options:
  --disk DEVICE       Target disk (default: /dev/sda)
  --boot-mode MODE    uefi | bios  (default: uefi)
  --efi-size SIZE     EFI partition size (default: 512M)
  --swap-size SIZE    Swap size, 0 to disable (default: 4G)
  --fs-root FS        Root filesystem: ext4 | btrfs | xfs (default: ext4)
  --mountroot PATH    Where to mount root (default: /mnt/gentoo)
  --dry-run           Show what would be done without making changes
  -h, --help          Show this help

Environment variables mirror option names (TG_DISK, TG_BOOT_MODE, etc.)

Examples:
  # Interactive defaults (UEFI, ext4, /dev/sda)
  sudo bash 00-prepare-disk.sh

  # NVMe disk, btrfs, no swap
  sudo TG_DISK=/dev/nvme0n1 TG_FS_ROOT=btrfs TG_SWAP_SIZE=0 bash 00-prepare-disk.sh

  # Preview what would happen without touching the disk
  sudo bash 00-prepare-disk.sh --disk /dev/sdb --dry-run
EOF
}

# ── argument parsing ──────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --disk)        TG_DISK="$2";        shift 2 ;;
            --boot-mode)   TG_BOOT_MODE="$2";   shift 2 ;;
            --efi-size)    TG_EFI_SIZE="$2";    shift 2 ;;
            --swap-size)   TG_SWAP_SIZE="$2";   shift 2 ;;
            --fs-root)     TG_FS_ROOT="$2";     shift 2 ;;
            --mountroot)   TG_MOUNTROOT="$2";   shift 2 ;;
            --dry-run)     DRY_RUN=1;           shift ;;
            -h|--help)     usage; exit 0 ;;
            *) die "Unknown option: $1\nRun with --help for usage." ;;
        esac
    done
}

# ── main ─────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"
    init_log
    check_root
    check_disk
    check_uefi
    check_tools

    if [[ "${DRY_RUN}" == "1" ]]; then
        warn "DRY-RUN mode — no changes will be made"
    else
        confirm_destructive
    fi

    # Partitioning
    case "${TG_BOOT_MODE}" in
        uefi) partition_uefi ;;
        bios) partition_bios ;;
        *)    die "Unknown boot mode: ${TG_BOOT_MODE}" ;;
    esac

    settle_partitions

    # Formatting
    case "${TG_BOOT_MODE}" in
        uefi) format_uefi ;;
        bios) format_bios ;;
    esac

    # Mounting
    if [[ "${DRY_RUN}" != "1" ]]; then
        mount_partitions
        export_partition_map
    fi

    print_summary
    log "00-prepare-disk.sh finished successfully"
}

main "$@"
