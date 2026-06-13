#!/usr/bin/env bash
# Download and extract stage3 tarball into the mounted root
set -euo pipefail

LOG_DIR="/var/log/turbogentoo"
LOG_FILE="${LOG_DIR}/01-stage3-install.log"

TG_MOUNTROOT="${TG_MOUNTROOT:-/mnt/gentoo}"
TG_MIRROR="${TG_MIRROR:-https://distfiles.gentoo.org}"
TG_STAGE3_VARIANT="${TG_STAGE3_VARIANT:-openrc}"   # openrc | systemd
TG_ARCH="${TG_ARCH:-amd64}"
DRY_RUN="${DRY_RUN:-0}"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log() { echo -e "${CYAN}[$(date '+%H:%M:%S')]${RESET} $*" | tee -a "${LOG_FILE}"; }
ok()  { echo -e "${GREEN}[OK]${RESET} $*"  | tee -a "${LOG_FILE}"; }
die() { echo -e "${RED}[ERROR]${RESET} $*" | tee -a "${LOG_FILE}" >&2; exit 1; }
run() {
    if [[ "${DRY_RUN}" == "1" ]]; then echo -e "${YELLOW}[DRY-RUN]${RESET} $*"; else log "Exec: $*"; "$@"; fi
}

[[ "${EUID}" -eq 0 ]] || die "Must be run as root"

# Load partition map written by 00-prepare-disk.sh
PARTMAP="${TG_MOUNTROOT}/turbogentoo-partmap.env"
if [[ -f "${PARTMAP}" ]]; then
    # shellcheck source=/dev/null
    source "${PARTMAP}"
    log "Loaded partition map from ${PARTMAP}"
fi

mkdir -p "${LOG_DIR}"
log "Stage3 installation started"
log "  MIRROR  : ${TG_MIRROR}"
log "  VARIANT : ${TG_STAGE3_VARIANT}"
log "  ARCH    : ${TG_ARCH}"
log "  MOUNT   : ${TG_MOUNTROOT}"

# ── find latest stage3 ───────────────────────────────────────────────────────
fetch_stage3_url() {
    local latest_file releases_url
    releases_url="${TG_MIRROR}/releases/${TG_ARCH}/autobuilds"

    case "${TG_STAGE3_VARIANT}" in
        openrc)   latest_file="latest-stage3-${TG_ARCH}-openrc.txt" ;;
        systemd)  latest_file="latest-stage3-${TG_ARCH}-systemd.txt" ;;
        *)        die "Unknown stage3 variant: ${TG_STAGE3_VARIANT}" ;;
    esac

    log "Fetching stage3 index from ${releases_url}/${latest_file}..."
    local latest_info
    latest_info="$(wget -qO- "${releases_url}/${latest_file}" | grep -v '^#' | head -1)"
    local tarball_path
    tarball_path="$(echo "${latest_info}" | awk '{print $1}')"
    echo "${releases_url}/${tarball_path}"
}

# ── idempotency check ─────────────────────────────────────────────────────────
if [[ -f "${TG_MOUNTROOT}/etc/gentoo-release" ]]; then
    ok "Stage3 already extracted — skipping download"
    log "01-stage3-install.sh skipped (already done)"
    exit 0
fi

[[ -d "${TG_MOUNTROOT}" ]] || die "Mount root not found: ${TG_MOUNTROOT}. Run 00-prepare-disk.sh first."

# ── download ─────────────────────────────────────────────────────────────────
STAGE3_URL="$(fetch_stage3_url)"
STAGE3_FILE="$(basename "${STAGE3_URL}")"
STAGE3_DIGEST_URL="${STAGE3_URL}.sha256"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

log "Downloading ${STAGE3_FILE}..."
log "URL: ${STAGE3_URL}"

if [[ "${DRY_RUN}" == "1" ]]; then
    echo -e "${YELLOW}[DRY-RUN]${RESET} Would download ${STAGE3_URL}"
    echo -e "${YELLOW}[DRY-RUN]${RESET} Would extract to ${TG_MOUNTROOT}"
    exit 0
fi

wget --progress=bar:force -O "${TMP_DIR}/${STAGE3_FILE}" "${STAGE3_URL}"
wget -qO "${TMP_DIR}/${STAGE3_FILE}.sha256" "${STAGE3_DIGEST_URL}"

# ── verify digest ─────────────────────────────────────────────────────────────
log "Verifying SHA256 checksum..."
pushd "${TMP_DIR}" > /dev/null
sha256sum -c "${STAGE3_FILE}.sha256" --ignore-missing
popd > /dev/null
ok "Checksum verified"

# ── extract ───────────────────────────────────────────────────────────────────
log "Extracting stage3 to ${TG_MOUNTROOT} (this may take a few minutes)..."
tar xpf "${TMP_DIR}/${STAGE3_FILE}" \
    --xattrs-include='*.*' \
    --numeric-owner \
    -C "${TG_MOUNTROOT}"
ok "Stage3 extracted"

# ── copy DNS ──────────────────────────────────────────────────────────────────
cp -L /etc/resolv.conf "${TG_MOUNTROOT}/etc/resolv.conf"
ok "DNS config copied"

log "01-stage3-install.sh finished successfully"
echo
echo -e "${GREEN}${BOLD}Stage3 ready. Next: bash scripts/02-base-config.sh${RESET}"
