#!/usr/bin/env bash
set -uo pipefail

REPO=/home/atqa/repo/dotmachines
HOST=$(hostname --short)
USER=atqa
UID_NUM=1000

log() { logger -t dotmachines-reconcile -- "$*"; printf '%s\n' "$*"; }

notify_failure() {
  sudo -u "$USER" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${UID_NUM}/bus" \
    notify-send -u critical "dotmachines reconcile failed" "$1"
}

log "start host=$HOST"

if ! sudo -u "$USER" -H git -C "$REPO" fetch --quiet origin; then
  log "git fetch failed, skipping reconcile"
  exit 0
fi

LOCAL=$(sudo -u "$USER" -H git -C "$REPO" rev-parse HEAD)
REMOTE=$(sudo -u "$USER" -H git -C "$REPO" rev-parse origin/master)

if [ "$LOCAL" = "$REMOTE" ]; then
  log "no changes, nothing to do"
  exit 0
fi

log "changes detected: $LOCAL -> $REMOTE"

if ! sudo -u "$USER" -H git -C "$REPO" merge --ff-only --quiet '@{u}'; then
  log "git ff-only failed (dirty tree or non-FF), skipping reconcile"
  notify_failure "git merge --ff-only failed. Manual intervention needed."
  exit 1
fi

log "running bootstrap.yaml"
if ansible-playbook \
  -i "$REPO/ansible/inventory/hosts.yaml" \
  "$REPO/ansible/playbooks/bootstrap.yaml" \
  --limit "$HOST" --connection=local \
  --skip-tags dotfiles; then
  log "bootstrap completed successfully"
else
  log "bootstrap failed"
  notify_failure "ansible-playbook bootstrap.yaml failed. Check: journalctl -t dotmachines-reconcile"
  exit 1
fi
