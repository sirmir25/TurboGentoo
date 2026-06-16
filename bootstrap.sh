#!/usr/bin/env bash
# TurboGentoo universal bootstrap
# Works on: Debian/Ubuntu, Arch, Fedora/RHEL/CentOS, openSUSE, Alpine, Gentoo live CD
# Usage: curl -fsSL https://raw.githubusercontent.com/sirmir25/TurboGentoo/main/bootstrap.sh | bash
#   or:  sudo bash bootstrap.sh [--config profiles/desktop.conf] [--wm i3] [--disk /dev/sda]

set -euo pipefail

TG_REPO="https://github.com/sirmir25/TurboGentoo/archive/refs/heads/main.tar.gz"
TG_DIR="/tmp/turbogentoo"
TG_BRANCH_DIR="${TG_DIR}/TurboGentoo-main"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*"; }
ok()   { echo -e "${GREEN}[OK]${RESET} $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*"; }
die()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
sep()  { echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

# ── argument parsing ──────────────────────────────────────────────────────────
CONFIG_ARG=""
TG_DISK="${TG_DISK:-}"
TG_WM="${TG_WM:-i3}"
TG_PROFILE="${TG_PROFILE:-desktop}"
DRY_RUN="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)  CONFIG_ARG="$2";  shift 2 ;;
        --disk)    TG_DISK="$2";     shift 2 ;;
        --wm)      TG_WM="$2";       shift 2 ;;
        --profile) TG_PROFILE="$2";  shift 2 ;;
        --dry-run) DRY_RUN=1;        shift ;;
        -h|--help)
            echo "Usage: sudo bash bootstrap.sh [OPTIONS]"
            echo "  --config FILE    Profile config (default: interactive)"
            echo "  --disk DEVICE    Target disk (e.g. /dev/sda, /dev/nvme0n1)"
            echo "  --wm WM          Window manager: i3 | sway | openbox"
            echo "  --profile NAME   minimal | desktop | dev"
            echo "  --dry-run        Preview without changes"
            exit 0 ;;
        *) die "Unknown option: $1 (run with --help)" ;;
    esac
done

# ── checks ────────────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash bootstrap.sh"

[[ "$(uname -m)" == "x86_64" ]] || \
    warn "Architecture is $(uname -m) — only x86_64 (amd64) is tested"

# ── distro detection ──────────────────────────────────────────────────────────
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "${ID:-unknown}"
    elif [[ -f /etc/gentoo-release ]]; then
        echo "gentoo"
    elif [[ -f /etc/arch-release ]]; then
        echo "arch"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

DISTRO="$(detect_distro)"
log "Detected distro: ${DISTRO}"

# ── required tools ────────────────────────────────────────────────────────────
REQUIRED_TOOLS=(
    bash curl tar gzip
    parted sgdisk
    mkfs.fat mkfs.ext4 mkswap
    mount chroot
    sha256sum
)

missing_tools() {
    local missing=()
    for t in "${REQUIRED_TOOLS[@]}"; do
        command -v "${t}" &>/dev/null || missing+=("${t}")
    done
    echo "${missing[@]:-}"
}

# ── package installation per distro ──────────────────────────────────────────
install_deps() {
    local missing
    missing="$(missing_tools)"
    if [[ -z "${missing}" ]]; then
        ok "All dependencies already present"
        return
    fi
    log "Installing missing dependencies: ${missing}"

    case "${DISTRO}" in
        debian|ubuntu|linuxmint|pop|elementary|kali)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y --no-install-recommends \
                gdisk parted dosfstools e2fsprogs util-linux \
                curl wget ca-certificates tar gzip xz-utils \
                arch-install-scripts btrfs-progs xfsprogs \
                2>/dev/null || true
            # arch-install-scripts may not exist on all Ubuntu — fallback
            command -v arch-chroot &>/dev/null || true
            ;;

        arch|manjaro|endeavouros|garuda)
            pacman -Sy --noconfirm --needed \
                gptfdisk parted dosfstools e2fsprogs util-linux \
                curl wget ca-certificates tar gzip xz \
                arch-install-scripts btrfs-progs xfsprogs \
                2>/dev/null || true
            ;;

        fedora)
            dnf install -y \
                gdisk parted dosfstools e2fsprogs util-linux \
                curl wget ca-certificates tar gzip xz \
                btrfs-progs xfsprogs \
                2>/dev/null || true
            ;;

        centos|rhel|almalinux|rocky)
            dnf install -y epel-release 2>/dev/null || true
            dnf install -y \
                gdisk parted dosfstools e2fsprogs util-linux \
                curl wget ca-certificates tar gzip xz \
                btrfs-progs xfsprogs \
                2>/dev/null || true
            ;;

        opensuse*|suse|sles)
            zypper install -y --no-recommends \
                gptfdisk parted dosfstools e2fsprogs util-linux \
                curl wget ca-certificates tar gzip xz \
                btrfs-progs xfsprogs \
                2>/dev/null || true
            ;;

        alpine)
            apk add --no-cache \
                sgdisk parted dosfstools e2fsprogs util-linux \
                curl wget ca-certificates tar gzip xz \
                btrfs-progs xfsprogs \
                2>/dev/null || true
            ;;

        gentoo)
            # Already on a Gentoo live CD — tools should be present
            ok "Running on Gentoo — assuming tools available"
            ;;

        *)
            warn "Unknown distro '${DISTRO}' — trying to proceed without installing packages"
            warn "Install manually if needed: gdisk parted dosfstools e2fsprogs curl tar"
            ;;
    esac

    # Final check
    local still_missing
    still_missing="$(missing_tools)"
    # mkfs.fat might be called mkfs.vfat on some systems
    if echo "${still_missing}" | grep -q "mkfs.fat"; then
        command -v mkfs.vfat &>/dev/null && still_missing="${still_missing/mkfs.fat/}" || true
    fi
    still_missing="$(echo "${still_missing}" | xargs)"  # trim whitespace

    if [[ -n "${still_missing}" ]]; then
        warn "Still missing: ${still_missing}"
        warn "Proceeding anyway — install will fail if these are truly absent"
    else
        ok "All dependencies installed"
    fi
}

# ── mkfs.fat compat shim ──────────────────────────────────────────────────────
compat_shims() {
    # Some distros ship mkfs.vfat but not mkfs.fat
    if ! command -v mkfs.fat &>/dev/null && command -v mkfs.vfat &>/dev/null; then
        ln -sf "$(command -v mkfs.vfat)" /usr/local/bin/mkfs.fat 2>/dev/null || true
        ok "Created mkfs.fat → mkfs.vfat symlink"
    fi

    # Some distros ship wget but not curl, or vice versa
    if ! command -v curl &>/dev/null && command -v wget &>/dev/null; then
        cat > /usr/local/bin/curl <<'CURLWRAP'
#!/bin/sh
# curl shim using wget — translates the flags TurboGentoo actually uses
_url=""
_out="-O-"
_flags="-q"
while [ $# -gt 0 ]; do
    case "$1" in
        -fsSL|-fsL|-sL|-fL|-s|-f) shift ;;
        -o) _out="-O$2"; shift 2 ;;
        -O) _out="-O$2"; shift 2 ;;
        --output) _out="-O$2"; shift 2 ;;
        http*|ftp*) _url="$1"; shift ;;
        *) shift ;;
    esac
done
exec wget ${_flags} ${_out} "${_url}"
CURLWRAP
        chmod +x /usr/local/bin/curl
        ok "Created curl → wget shim"
    fi
}

# ── download TurboGentoo ──────────────────────────────────────────────────────
download_turbogentoo() {
    # If we're already inside the repo, use it directly
    if [[ -f "${BASH_SOURCE[0]%/*}/install.sh" ]]; then
        TG_BRANCH_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
        ok "Using local TurboGentoo at ${TG_BRANCH_DIR}"
        return
    fi

    log "Downloading TurboGentoo from GitHub..."
    mkdir -p "${TG_DIR}"
    curl -fsSL "${TG_REPO}" -o "${TG_DIR}/main.tar.gz"
    tar xzf "${TG_DIR}/main.tar.gz" -C "${TG_DIR}"
    ok "TurboGentoo downloaded to ${TG_BRANCH_DIR}"
}

# ── build config ──────────────────────────────────────────────────────────────
build_config() {
    # If disk not specified, auto-detect first non-removable disk
    if [[ -z "${TG_DISK}" ]]; then
        TG_DISK="$(lsblk -dno NAME,TYPE,RM 2>/dev/null \
            | awk '$2=="disk" && $3=="0" {print "/dev/"$1; exit}')"
        [[ -n "${TG_DISK}" ]] || TG_DISK="/dev/sda"
        warn "Auto-detected disk: ${TG_DISK} (override with --disk)"
    fi

    # Detect UEFI vs BIOS
    if [[ -d /sys/firmware/efi ]]; then
        TG_BOOT_MODE="uefi"
    else
        TG_BOOT_MODE="bios"
        warn "No EFI detected — using BIOS/MBR mode"
    fi

    # If config file provided, use it; otherwise build one from args
    if [[ -n "${CONFIG_ARG}" ]]; then
        [[ -f "${CONFIG_ARG}" ]] || die "Config not found: ${CONFIG_ARG}"
        # Overlay disk/wm/profile from CLI args on top of config
        export TG_DISK TG_WM TG_PROFILE TG_BOOT_MODE DRY_RUN
        return
    fi

    # Generate ephemeral config
    GENERATED_CONFIG="$(mktemp /tmp/turbogentoo-XXXXXX.conf)"
    cat > "${GENERATED_CONFIG}" <<EOF
# Auto-generated by TurboGentoo bootstrap.sh on $(date)
TG_PROFILE="${TG_PROFILE}"
TG_DISK="${TG_DISK}"
TG_BOOT_MODE="${TG_BOOT_MODE}"
TG_EFI_SIZE="512M"
TG_SWAP_SIZE="4G"
TG_FS_ROOT="ext4"
TG_HOSTNAME="turbogentoo"
TG_TIMEZONE="Europe/Moscow"
TG_LOCALE="en_US.UTF-8"
TG_USERNAME="user"
TG_MIRROR="https://distfiles.gentoo.org"
TG_STAGE3_VARIANT="openrc"
TG_USE_BINPKG="1"
TG_CFLAGS="-O2 -pipe -march=native"
TG_KERNEL_METHOD="dist-kernel"
TG_WM="${TG_WM}"
EOF
    CONFIG_ARG="${GENERATED_CONFIG}"
    ok "Generated config: ${GENERATED_CONFIG}"
}

# ── summary before launch ─────────────────────────────────────────────────────
print_summary() {
    sep
    echo
    echo -e "${GREEN}${BOLD}  TurboGentoo bootstrap ready${RESET}"
    echo
    echo -e "  Host distro : ${BOLD}${DISTRO}${RESET}"
    echo -e "  Target disk : ${BOLD}${TG_DISK}${RESET}"
    echo -e "  Boot mode   : ${BOLD}${TG_BOOT_MODE}${RESET}"
    echo -e "  WM          : ${BOLD}${TG_WM}${RESET}"
    echo -e "  Profile     : ${BOLD}${TG_PROFILE}${RESET}"
    [[ "${DRY_RUN}" == "1" ]] && \
        echo -e "  ${YELLOW}${BOLD}DRY-RUN — no changes will be made${RESET}"
    echo
    sep
    echo
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║        TurboGentoo — Universal Bootstrap                 ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo

    install_deps
    compat_shims
    download_turbogentoo
    build_config
    print_summary

    cd "${TG_BRANCH_DIR}"

    local install_args=("--config" "${CONFIG_ARG}")
    [[ "${DRY_RUN}" == "1" ]] && install_args+=("--dry-run")

    exec bash install.sh "${install_args[@]}"
}

main "$@"
