#!/usr/bin/env bash
# TurboGentoo — main orchestrator
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/install.log"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }
sep() { echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# ── defaults ──────────────────────────────────────────────────────────────────
CONFIG_FILE=""
START_STEP=0
END_STEP=6
DRY_RUN="${DRY_RUN:-0}"

# ── usage ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
TurboGentoo — automated Gentoo installer

Usage: sudo bash install.sh [OPTIONS]

Options:
  --config FILE     Profile config file (skips interactive setup)
  --from STEP       Start from step N (0-6, default: 0)
  --to   STEP       Stop after step N  (0-6, default: 6)
  --dry-run         Show what would be done without making changes
  -h, --help        Show this help

Steps:
  0 — prepare-disk    (partition, format, mount)
  1 — stage3-install  (download and extract stage3)
  2 — base-config     (make.conf, fstab, locale, timezone)
  3 — kernel-setup    (install kernel)
  4 — bootloader      (install GRUB)
  5 — wm-install      (X11/Wayland + window manager)
  6 — post-install    (user, passwords, services)

Examples:
  # Interactive setup (recommended)
  sudo bash install.sh

  # Use a pre-made profile
  sudo bash install.sh --config profiles/desktop.conf

  # Resume from bootloader step
  sudo bash install.sh --config profiles/desktop.conf --from 4

  # Preview without touching anything
  sudo bash install.sh --dry-run
EOF
}

# ── argument parsing ──────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)   CONFIG_FILE="$2"; shift 2 ;;
            --from)     START_STEP="$2";  shift 2 ;;
            --to)       END_STEP="$2";    shift 2 ;;
            --dry-run)  DRY_RUN=1;        shift ;;
            -h|--help)  usage; exit 0 ;;
            *) die "Unknown option: $1\nRun with --help for usage." ;;
        esac
    done
}

# ── interactive setup (one screen, no more questions after this) ───────────────
interactive_setup() {
    echo
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║              TurboGentoo — setup wizard                  ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  Answer the questions below. After that the installer runs${BOLD} without interruptions${RESET}."
    echo

    # ── disk ──────────────────────────────────────────────────────────────────
    echo -e "${CYAN}Available disks:${RESET}"
    lsblk -dno NAME,SIZE,MODEL 2>/dev/null | awk '{printf "  /dev/%-10s %s  %s\n", $1, $2, $3}' || true
    echo

    local default_disk
    default_disk="$(lsblk -dno NAME,TYPE,RM 2>/dev/null \
        | awk '$2=="disk" && $3=="0" {print "/dev/"$1; exit}')"
    default_disk="${default_disk:-/dev/sda}"

    read -rp "  Target disk [${default_disk}]: " TG_DISK
    TG_DISK="${TG_DISK:-${default_disk}}"
    [[ -b "${TG_DISK}" ]] || die "Not a block device: ${TG_DISK}"

    # ── boot mode ─────────────────────────────────────────────────────────────
    if [[ -d /sys/firmware/efi ]]; then
        TG_BOOT_MODE="uefi"
        echo -e "  Boot mode: ${BOLD}UEFI${RESET} (auto-detected)"
    else
        TG_BOOT_MODE="bios"
        echo -e "  Boot mode: ${BOLD}BIOS/MBR${RESET} (auto-detected)"
    fi

    # ── profile ───────────────────────────────────────────────────────────────
    echo
    echo -e "  Profile:"
    echo -e "    ${BOLD}1)${RESET} minimal  — WM + terminal only"
    echo -e "    ${BOLD}2)${RESET} desktop  — + browser, file manager, audio  ${CYAN}(recommended)${RESET}"
    echo -e "    ${BOLD}3)${RESET} dev      — desktop + git, neovim, build tools"
    read -rp "  Choice [2]: " _p
    case "${_p:-2}" in
        1) TG_PROFILE="minimal" ;;
        3) TG_PROFILE="dev" ;;
        *) TG_PROFILE="desktop" ;;
    esac

    # ── window manager ────────────────────────────────────────────────────────
    echo
    echo -e "  Window manager:"
    echo -e "    ${BOLD}1)${RESET} i3       — X11 tiling  ${CYAN}(recommended)${RESET}"
    echo -e "    ${BOLD}2)${RESET} sway     — Wayland tiling"
    echo -e "    ${BOLD}3)${RESET} openbox  — X11 floating"
    read -rp "  Choice [1]: " _w
    case "${_w:-1}" in
        2) TG_WM="sway" ;;
        3) TG_WM="openbox" ;;
        *) TG_WM="i3" ;;
    esac

    # ── username ──────────────────────────────────────────────────────────────
    echo
    read -rp "  Username [user]: " TG_USERNAME
    TG_USERNAME="${TG_USERNAME:-user}"

    # ── hostname ──────────────────────────────────────────────────────────────
    read -rp "  Hostname [gentoo]: " TG_HOSTNAME
    TG_HOSTNAME="${TG_HOSTNAME:-gentoo}"

    # ── root password ─────────────────────────────────────────────────────────
    echo
    while true; do
        read -rsp "  Root password: " TG_ROOT_PASS; echo
        read -rsp "  Root password (again): " _rp2; echo
        [[ "${TG_ROOT_PASS}" == "${_rp2}" ]] && break
        echo -e "  ${RED}Passwords don't match, try again.${RESET}"
    done

    # ── user password ─────────────────────────────────────────────────────────
    while true; do
        read -rsp "  Password for ${TG_USERNAME}: " TG_USER_PASS; echo
        read -rsp "  Password for ${TG_USERNAME} (again): " _up2; echo
        [[ "${TG_USER_PASS}" == "${_up2}" ]] && break
        echo -e "  ${RED}Passwords don't match, try again.${RESET}"
    done

    # ── confirmation ──────────────────────────────────────────────────────────
    echo
    sep
    echo
    echo -e "  ${RED}${BOLD}ALL DATA ON ${TG_DISK} WILL BE ERASED.${RESET}"
    echo
    echo -e "  Disk     : ${BOLD}${TG_DISK}${RESET}"
    echo -e "  Profile  : ${BOLD}${TG_PROFILE}${RESET}"
    echo -e "  WM       : ${BOLD}${TG_WM}${RESET}"
    echo -e "  Hostname : ${BOLD}${TG_HOSTNAME}${RESET}"
    echo -e "  Username : ${BOLD}${TG_USERNAME}${RESET}"
    echo -e "  Boot     : ${BOLD}${TG_BOOT_MODE^^}${RESET}"
    echo
    read -rp "  Type YES to start: " _confirm
    [[ "${_confirm}" == "YES" ]] || die "Aborted."
    echo

    # ── fill in remaining defaults ────────────────────────────────────────────
    TG_EFI_SIZE="${TG_EFI_SIZE:-512M}"
    TG_SWAP_SIZE="${TG_SWAP_SIZE:-4G}"
    TG_FS_ROOT="${TG_FS_ROOT:-ext4}"
    TG_TIMEZONE="${TG_TIMEZONE:-Europe/Moscow}"
    TG_LOCALE="${TG_LOCALE:-en_US.UTF-8}"
    TG_MIRROR="${TG_MIRROR:-https://distfiles.gentoo.org}"
    TG_STAGE3_VARIANT="${TG_STAGE3_VARIANT:-openrc}"
    TG_USE_BINPKG="${TG_USE_BINPKG:-1}"
    TG_CFLAGS="${TG_CFLAGS:--O2 -pipe -march=native}"
    TG_KERNEL_METHOD="${TG_KERNEL_METHOD:-dist-kernel}"
    TG_AUTO=1

    export TG_DISK TG_BOOT_MODE TG_EFI_SIZE TG_SWAP_SIZE TG_FS_ROOT
    export TG_HOSTNAME TG_TIMEZONE TG_LOCALE TG_USERNAME
    export TG_MIRROR TG_STAGE3_VARIANT TG_USE_BINPKG TG_CFLAGS
    export TG_KERNEL_METHOD TG_WM TG_PROFILE TG_AUTO
    export TG_ROOT_PASS TG_USER_PASS DRY_RUN
}

# ── load config file ──────────────────────────────────────────────────────────
load_config() {
    [[ -f "${CONFIG_FILE}" ]] || die "Config file not found: ${CONFIG_FILE}"
    log "Loading config: ${CONFIG_FILE}"
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    export TG_DISK TG_BOOT_MODE TG_EFI_SIZE TG_SWAP_SIZE TG_FS_ROOT
    export TG_HOSTNAME TG_TIMEZONE TG_LOCALE TG_USERNAME
    export TG_MIRROR TG_STAGE3_VARIANT TG_USE_BINPKG TG_CFLAGS
    export TG_KERNEL_METHOD TG_WM TG_PROFILE
    export DRY_RUN
    # When using a config file, still ask for passwords interactively
    # unless they were pre-set in the environment
    if [[ -z "${TG_ROOT_PASS:-}" ]]; then
        echo
        while true; do
            read -rsp "Root password for new system: " TG_ROOT_PASS; echo
            read -rsp "Root password (again): " _rp2; echo
            [[ "${TG_ROOT_PASS}" == "${_rp2}" ]] && break
            echo -e "${RED}Passwords don't match, try again.${RESET}"
        done
        export TG_ROOT_PASS
    fi
    if [[ -z "${TG_USER_PASS:-}" ]]; then
        while true; do
            read -rsp "Password for ${TG_USERNAME:-user}: " TG_USER_PASS; echo
            read -rsp "Password (again): " _up2; echo
            [[ "${TG_USER_PASS}" == "${_up2}" ]] && break
            echo -e "${RED}Passwords don't match, try again.${RESET}"
        done
        export TG_USER_PASS
    fi
}

# ── step runner ───────────────────────────────────────────────────────────────
run_step() {
    local step_num="$1"
    local step_name="$2"
    local script="${SCRIPT_DIR}/scripts/${step_name}.sh"

    [[ ${step_num} -lt ${START_STEP} ]] && return
    [[ ${step_num} -gt ${END_STEP}   ]] && return

    sep
    log "Step ${step_num}/6: ${step_name}"
    sep

    [[ -f "${script}" ]] || die "Script not found: ${script}"
    bash "${script}"
    ok "Step ${step_num} complete: ${step_name}"
    echo
}

# ── time tracker ──────────────────────────────────────────────────────────────
elapsed() {
    local start="$1"
    local end
    end="$(date +%s)"
    local diff=$(( end - start ))
    printf "%dm%ds" $(( diff / 60 )) $(( diff % 60 ))
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    [[ "${EUID}" -eq 0 ]] || die "Must be run as root"
    mkdir -p "${LOG_DIR}"

    if [[ -z "${CONFIG_FILE}" ]]; then
        interactive_setup
    else
        load_config
    fi

    echo
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║              TurboGentoo — starting install              ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  Profile  : ${BOLD}${TG_PROFILE}${RESET}"
    echo -e "  WM       : ${BOLD}${TG_WM}${RESET}"
    echo -e "  Disk     : ${BOLD}${TG_DISK}${RESET}"
    echo -e "  Hostname : ${BOLD}${TG_HOSTNAME}${RESET}"
    echo -e "  Kernel   : ${BOLD}${TG_KERNEL_METHOD}${RESET}"
    echo -e "  binpkg   : ${BOLD}${TG_USE_BINPKG}${RESET}"
    [[ "${DRY_RUN}" == "1" ]] && echo -e "  ${YELLOW}${BOLD}DRY-RUN MODE — no changes will be made${RESET}"
    echo
    log "Install log: ${LOG_FILE}"

    local t_start
    t_start="$(date +%s)"

    run_step 0 "00-prepare-disk"
    run_step 1 "01-stage3-install"
    run_step 2 "02-base-config"
    run_step 3 "03-kernel-setup"
    run_step 4 "04-bootloader"
    run_step 5 "05-wm-install"
    run_step 6 "06-post-install"

    sep
    echo
    echo -e "${GREEN}${BOLD}  TurboGentoo installation finished in $(elapsed "${t_start}")!${RESET}"
    echo
    echo -e "  Unmount and reboot:"
    echo -e "  ${CYAN}cd / && umount -R ${TG_MOUNTROOT:-/mnt/gentoo} && reboot${RESET}"
    echo
    log "install.sh finished (elapsed: $(elapsed "${t_start}"))"
}

main "$@"
