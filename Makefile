# TurboGentoo — convenience targets
# Requires root for most targets (run with sudo make <target>)

CONFIG ?= profiles/desktop.conf
DRY_RUN ?= 0

.PHONY: install minimal desktop dev dry-run lint check-deps clean help

help:
	@echo "TurboGentoo — Makefile targets"
	@echo ""
	@echo "  make install          Full install with CONFIG (default: profiles/desktop.conf)"
	@echo "  make minimal          Install with minimal profile"
	@echo "  make desktop          Install with desktop profile"
	@echo "  make dev              Install with dev profile"
	@echo "  make dry-run          Preview desktop install without changes"
	@echo "  make lint             Shellcheck all scripts"
	@echo "  make check-deps       Verify required tools are present"
	@echo "  make clean            Remove local logs"
	@echo ""
	@echo "Override config:  sudo make install CONFIG=profiles/minimal.conf"

install: check-deps
	sudo DRY_RUN=$(DRY_RUN) bash install.sh --config $(CONFIG)

minimal: check-deps
	sudo bash install.sh --config profiles/minimal.conf

desktop: check-deps
	sudo bash install.sh --config profiles/desktop.conf

dev: check-deps
	sudo bash install.sh --config profiles/dev.conf

dry-run:
	DRY_RUN=1 bash install.sh --config $(CONFIG) --dry-run

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found — install it first"; exit 1; }
	shellcheck -S warning scripts/*.sh install.sh

check-deps:
	@bash -c ' \
		missing=(); \
		for t in bash wget sgdisk parted mkfs.fat mkfs.ext4 mkswap mount chroot; do \
			command -v $$t >/dev/null 2>&1 || missing+=($$t); \
		done; \
		if [[ $${#missing[@]} -gt 0 ]]; then \
			echo "Missing dependencies: $${missing[*]}"; exit 1; \
		fi; \
		echo "All dependencies found."; \
	'

clean:
	rm -f /var/log/turbogentoo/*.log 2>/dev/null || true
	@echo "Logs cleaned"
