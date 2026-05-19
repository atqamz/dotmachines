# Design: Swap Flatpak/Podman Desktop for podman-tui + gitui via Ansible

**Date:** 2026-05-18
**Repo:** `~/repo/dotmachines` (primary), `~/dotfiles` (cross-repo cleanup)
**Branch:** `podman-desktop-ansible-design` (force-pushed; replaces in-flight PR #2)
**Supersedes:** `docs/superpowers/specs/2026-05-18-podman-desktop-ansible-design.md`

## Motivation

The earlier design installed Podman Desktop (flatpak) and plumbed it for remote rootless Podman engines over SSH. After implementation, Podman Desktop v1.27.1 on Linux flatpak failed to surface CLI-defined remote connections in its Resources panel — a known upstream bug ([podman-desktop/podman-desktop#15532](https://github.com/podman-desktop/podman-desktop/issues/15532), still open as of 2026-05). The flatpak sandbox itself worked correctly (ssh-agent socket reachable, `~/.ssh` visible, connections.json symlinked) — the limitation is in Podman Desktop's own remote-engine discovery code, not infrastructure.

Switching to `podman-tui` (the containers-org official TUI, available in Fedora's default repo) sidesteps the bug entirely: it reads `~/.config/containers/podman-connections.json` directly with no sandbox indirection. Since the workstation no longer needs flatpak for the Podman GUI, the whole flatpak stack (runtime, remote, app loader) is removed. `gitui` is added alongside `podman-tui` under a generic `tui-tools` role so future terminal UIs land in the same place.

## Goals

- Remove flatpak entirely from the workstation provisioning surface.
- Install `podman-tui` and `gitui` via a single `tui-tools` Ansible role.
- Move the systemd `ssh-agent.socket` enabling into its own `ssh-agent` role (was previously bundled into the `podman` role).
- Update PR #2 by force-pushing a clean commit sequence on the existing branch.
- Drop the `scripts/sshadd` helper from `atqamz/dotfiles` (now obsolete with systemd-managed ssh-agent socket).

## Non-goals

- Building a custom workstation TUI menu or launcher.
- Managing Podman Desktop via any non-flatpak install path (rpm, tar.gz, AppImage). The decision is "no Podman Desktop on this workstation."
- Touching `.bashrc`'s ssh-agent fallback in `atqamz/dotfiles` — it remains as a defensive fallback for bare shells launched outside the graphical session.
- Adding any TUI other than `podman-tui` and `gitui` in this change.

## Architecture

Three role changes in `dotmachines`, plus one file removal in `atqamz/dotfiles`.

### Roles to delete

- `ansible/roles/flatpak/` — system flatpak runtime + flathub system remote
- `ansible/roles/flatpak-apps/` — user-scope flatpak apps + user remotes
- `ansible/roles/podman-desktop/` — flatpak overrides for ssh-agent socket exposure and `podman-connections.json` symlink

### Roles to add

- `ansible/roles/ssh-agent/` — single task enabling `ssh-agent.socket` user systemd unit
- `ansible/roles/tui-tools/` — dnf-installs a list of TUI packages, variable-driven

### Role to modify

- `ansible/roles/podman/` — drop the `Enable ssh-agent user socket` task (moved to `ssh-agent` role). Keep the dnf install task as-is.

### Files to modify

- `ansible/playbooks/bootstrap.yaml` — replace the flatpak/flatpak-apps/podman/podman-desktop block with `podman` → `ssh-agent` → `tui-tools`.
- `ansible/inventory/group_vars/workstations.yaml` — drop the `flatpak_apps` block.

### Cross-repo (`atqamz/dotfiles`)

- Delete `scripts/.local/bin/scripts/sshadd`.
- Direct push to `master` (no PR), single commit.

## Role contracts

### `roles/ssh-agent/tasks/main.yaml`

```yaml
---
- name: Enable ssh-agent user socket
  ansible.builtin.systemd_service:
    name: ssh-agent.socket
    scope: user
    enabled: true
    state: started
```

No defaults file. Idempotent (systemd_service no-ops when already enabled+active).

### `roles/tui-tools/defaults/main.yaml`

```yaml
---
tui_tools_packages:
  - podman-tui
  - gitui
```

### `roles/tui-tools/tasks/main.yaml`

```yaml
---
- name: Install TUI tools
  become: true
  ansible.builtin.dnf:
    name: "{{ tui_tools_packages }}"
    state: present
```

Variable-driven so future additions append to `tui_tools_packages` either in defaults or in group_vars.

### `roles/podman/tasks/main.yaml` (after edit)

```yaml
---
- name: Install podman and tooling
  become: true
  ansible.builtin.dnf:
    name:
      - podman
      - podman-compose
      - skopeo
      - buildah
      - slirp4netns
      - fuse-overlayfs
    state: present
```

Single task. ssh-agent task removed.

## Bootstrap ordering

Replace the existing flatpak/podman block in `ansible/playbooks/bootstrap.yaml`:

```yaml
    - role: podman
      tags: [packages, podman]
    - role: ssh-agent
      tags: [ssh-agent, systemd]
    - role: tui-tools
      tags: [packages, tui-tools]
```

Position in the file: where `flatpak` currently sits (after `gnome-minimize`, before `firmware`). Order between the three is not load-bearing; chosen for readability (install podman, then enable agent, then install TUI tools that consume both).

## Group vars

`ansible/inventory/group_vars/workstations.yaml` — drop the `flatpak_apps` block entirely:

```yaml
flatpak_apps:
  - id: io.podman_desktop.PodmanDesktop
```

No replacement entry is added. `tui_tools_packages` lives in role defaults; group_var override only needed if a host wants a different package list (none planned).

## Branch rewrite + PR update

The current branch `podman-desktop-ansible-design` carries six commits ahead of `master` implementing the previous spec. Force-push a clean replacement history.

```bash
cd ~/repo/dotmachines
git fetch origin master
git checkout podman-desktop-ansible-design
git reset --hard origin/master
# apply the six commits below
git push --force-with-lease origin podman-desktop-ansible-design
```

### Commit sequence

1. `delete flatpak, flatpak-apps, podman-desktop roles`
2. `add ssh-agent role for systemd ssh-agent.socket`
3. `add tui-tools role with podman-tui and gitui`
4. `move ssh-agent task out of podman role`
5. `wire podman, ssh-agent, tui-tools into bootstrap`
6. `drop flatpak_apps from workstations group vars`

### PR #2 update

```bash
gh pr edit 2 --title "swap flatpak/podman-desktop for podman-tui + gitui (tui-tools role)" \
  --body "..."
```

PR body summarizes: motivation (PD bug #15532), scope of removals, scope of additions, test plan, manual cleanup steps for sfx14.

## Cross-repo cleanup (`atqamz/dotfiles`)

```bash
cd ~/dotfiles
git checkout master
git pull
git rm scripts/.local/bin/scripts/sshadd
git commit -m "drop sshadd helper - superseded by systemd ssh-agent.socket"
git push origin master
```

Single commit, direct push to `master`. Authorized by user.

## Live migration on sfx14

The new Ansible roles do not "uninstall" anything. Workstation-side cleanup of state left over from the previous PR-#2 apply is a one-time human step:

```bash
flatpak uninstall -y --delete-data io.podman_desktop.PodmanDesktop
flatpak uninstall -y --user --all
flatpak remote-delete --user flathub 2>/dev/null || true
rm -rf ~/.local/share/flatpak ~/.var/app/io.podman_desktop.PodmanDesktop
sudo dnf remove -y flatpak flatpak-selinux

# Verify
command -v flatpak 2>&1   # expected: not found
```

After this, a fresh `ansible-playbook bootstrap.yaml` run is a no-op on sfx14.

## Idempotency

- `dnf state: present` is idempotent.
- `systemd_service enabled: true, state: started` is idempotent (systemd no-ops if already in that state).
- Roles never delete anything from the host — workstation state cleanup is a one-time human step (above).

Re-running `ansible-playbook bootstrap.yaml --limit sfx14 --tags podman,ssh-agent,tui-tools --diff` after a successful first apply: expect `changed=0`.

## Verification

### Package checks

```bash
rpm -q podman podman-compose skopeo buildah slirp4netns fuse-overlayfs
rpm -q podman-tui gitui
```

All expected `installed`.

### systemd

```bash
systemctl --user is-enabled ssh-agent.socket   # expected: enabled
systemctl --user is-active  ssh-agent.socket   # expected: active
```

### End-to-end smoke

```bash
# Local podman socket
podman ps -a

# Remote engine through ssh-agent
ssh-add ~/.ssh/id_ed25519
podman --connection bakso-deploy ps -a    # expected: bakso's containers

# TUIs launch
podman-tui     # connection picker shows bakso-deploy + local
gitui ~/repo/dotmachines
```

## Trade-offs and accepted constraints

- **No GUI Podman manager.** Workstation user picks between `podman-tui` (TUI) and the `podman` CLI directly. If a future contributor wants a GUI, candidates documented elsewhere: Cockpit on the server, Pods (Flathub GTK4 app), Portainer. Each is a separate brainstorm.
- **No re-introduction of flatpak.** Even for unrelated future apps. If the user later wants Steam, GIMP, etc., that re-introduces the `flatpak` role — out of scope here.
- **`ssh-agent` role assumes systemd-user `ssh-agent.socket` (Fedora ships the unit).** Same caveat as the previous design: workstations using a different agent (gnome-keyring exclusively, gpg-agent ssh emulation) would not benefit. Not in scope until a workstation actually has that configuration.
- **`gitui` as a TUI choice.** Not the only terminal git UI (`lazygit`, `tig`, `magit`-in-emacs all valid). User picked `gitui`; not a debate.
- **One-time live cleanup is manual.** Ansible does not enforce removal of state from prior runs — only the desired end state for fresh workstations. Documented above.

## Future work (out of scope here)

- `lazygit` or other TUIs: append to `tui_tools_packages` in `roles/tui-tools/defaults/main.yaml`.
- Switching the workstation ssh agent provider (gpg-agent, gnome-keyring) — would require parametrising the `ssh-agent` role (or replacing it).
- A new GUI Podman manager — separate brainstorm + spec.
- Cleaning up `.bashrc` ssh-agent spawn — defensive fallback retained for now; revisit if it ever causes a leak again.

## Sources

- [podman-desktop/podman-desktop#15532](https://github.com/podman-desktop/podman-desktop/issues/15532) — known unresolved bug: CLI-defined remote ssh connections do not appear in PD Resources panel.
- [Fedora package podman-tui 1.11.1-1.fc43](https://packages.fedoraproject.org/pkgs/podman-tui/) — Fedora 43 default repo.
- [Fedora package gitui 0.28.0-4.fc43](https://packages.fedoraproject.org/pkgs/rust-gitui/) — Fedora 43 default repo.
