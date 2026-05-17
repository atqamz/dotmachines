# dotmachines

Idempotent Fedora Workstation provisioning for personal laptops.

## Constraints

- **Idempotent first.** Every role must converge to the same state on N-th run.
- **No k8s, no containers, no clusters.** This is workstation provisioning, not infra.
- **Public repo, no secrets here.** All encrypted material lives in the private companion repo `atqamz/secrets`, cloned at `~/repo/secrets` (override via `-e secrets_path=...`).
- **SOPS root of trust: GPG fingerprint `F1F60517602888C8D5E486EB8AD7D4A302EE6771`.** The `.sops.yaml` is kept in this repo as defense-in-depth in case future Ansible `host_vars` need encryption.
- **GNOME stays as fallback session.** Hyprland is the daily driver but Fedora's GNOME must remain installable side-by-side.
- **Hybrid connection.** `inventory_hostname` matches tailscale MagicDNS name. Target == current host → `local`. Other host → `ssh` over tailscale. No SSH-into-self loop, but cross-host playbook runs work from either machine.

## Layout

```
ansible/
  inventory/{hosts.yaml,group_vars/,host_vars/}
  playbooks/{bootstrap.yaml,secrets-restore.yaml}
  roles/{hostname,dnf-tuning,rpm-fusion,base-packages,nvidia,hyprland,dotfiles,secrets-bootstrap}
scripts/ansible-setup.sh
```

## Conventions

- YAML extension: always `.yaml`, never `.yml`
- Roles: one task per `dnf install` grouping (audio, bluetooth, etc.), no monolithic shell scripts
- Vars: `group_vars/workstations.yaml` holds shared package lists; `host_vars/<host>.yaml` holds hardware flags
- New machine: see `BOOTSTRAP.md`

## When adding a package

1. Edit `ansible/inventory/group_vars/workstations.yaml` if it's universal
2. Edit `ansible/inventory/host_vars/<host>.yaml` if host-specific
3. Add a task in the matching role under `ansible/roles/<role>/tasks/main.yaml`
4. Test: `ansible-playbook ... --check --diff --tags <role>`

## When adding a new secret

Secrets are added in the companion `secrets` repo, NOT here.

1. `cd ~/repo/secrets`
2. Stage cleartext as `<dir>/<name>.dec.<ext>`
3. Run `bash scripts/encrypt.sh` → produces `<dir>/<name>.sops.<ext>`
4. Commit only the `.sops.*` file
5. Reference in `dotmachines/ansible/roles/secrets-bootstrap/defaults/main.yaml` if the new file should be auto-placed on every machine
