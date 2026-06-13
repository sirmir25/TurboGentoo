#!/usr/bin/env bash
# TurboGentoo — main orchestrator
# Runs all installation steps in order with a chosen profile.
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

# ── defaults ─────────────────────────────────────────────────────────────────
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
  --config FILE     Profile config file (default: interactive selection)
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
  # Full install with desktop profile
  sudo bash install.sh --config profiles/desktop.conf

  # Resume from bootloader step
  sudo bash install.sh --config profiles/desktop.conf --from 4

  # Preview all steps without touching anything
  sudo bash install.sh --config profiles/minimal.conf --dry-run
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

# ── interactive profile selection ─────────────────────────────────────────────
select_profile() {
    echo
    echo -e "${BOLD}Select installation profile:${RESET}"
    echo "  1) minimal  — system + WM + terminal only"
    echo "  2) desktop  — + browser, file manager, audio  (recommended)"
    echo "  3) dev      — desktop + git, neovim, build tools"
    echo
    read -rp "Choice [1-3]: " _choice
    case "${_choice}" in
        1) CONFIG_FILE="${SCRIPT_DIR}/profiles/minimal.conf" ;;
        2) CONFIG_FILE="${SCRIPT_DIR}/profiles/desktop.conf" ;;
        3) CONFIG_FILE="${SCRIPT_DIR}/profiles/dev.conf" ;;
        *) die "Invalid choice: ${_choice}" ;;
    esac
}

# ── load config ────────────────────────────────────────────────────────────────
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

    [[ -z "${CONFIG_FILE}" ]] && select_profile
    load_config

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
    echo -e "${GREEN}${BOLD}  TurboGentoo installation finished in $(elapsed "${t_start})!${RESET}"
    echo
    echo -e "  Unmount and reboot:"
    echo -e "  ${CYAN}cd / && umount -R ${TG_MOUNTROOT:-/mnt/gentoo} && reboot${RESET}"
    echo
    log "install.sh finished (elapsed: $(elapsed "${t_start}"))"
}

main "$@"
