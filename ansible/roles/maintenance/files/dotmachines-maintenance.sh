#!/usr/bin/env bash
set -uo pipefail

REPO=/home/atqa/repo/dotmachines
HOST=$(hostname --short)

log() { logger -t dotmachines-maintenance -- "$*"; printf '%s\n' "$*"; }

log "start host=$HOST"

if ! sudo -u atqa -H git -C "$REPO" fetch --quiet origin; then
  log "git fetch failed, continuing with on-disk checkout"
fi

if ! sudo -u atqa -H git -C "$REPO" merge --ff-only --quiet '@{u}'; then
  log "git ff-only failed (dirty tree or non-FF), continuing with on-disk checkout"
fi

exec ansible-playbook \
  -i "$REPO/ansible/inventory/hosts.yaml" \
  "$REPO/ansible/playbooks/maintenance.yaml" \
  --limit "$HOST" --connection=local
