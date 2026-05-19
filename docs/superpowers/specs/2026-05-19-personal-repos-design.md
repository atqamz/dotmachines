# Personal Repos Integration (raw + password-store)

**Status:** Approved
**Target:** sfx14 only (initial scope)

## Problem

Two private companion repos are already required by shipped functionality but are not provisioned by dotmachines:

- `git@github.com:atqamz/raw.git` → `~/raw/` — knowledge corpus consumed by `graphify-sync.timer` (rebuilds graphs daily, pushes per-file Gemini-generated commit messages).
- `git@github.com:atqamz/password-store` → `~/.password-store/` — `pass` backend used by `podman-tui` wrapper (`pass show dotfiles/ssh/passphrase`), `graphify-sync.sh` (`pass show dotfiles/api-key/gemini`), and ad-hoc credential lookups.

Without these cloned and unlocked, both pieces fail on a fresh machine.

A naming inconsistency in the existing role set is also addressed: `secrets-bootstrap` is the only role using a `-bootstrap` suffix. Every other role uses noun/concept naming (`dotfiles`, `hyprland`, `tailscale`, `podman`, `tui-tools`).

## Goals

1. Idempotent clone + update of `~/raw/` and `~/.password-store/` on sfx14.
2. Soft-fail with a warn diagnostic when SSH auth is not yet available — bootstrap continues.
3. Independent host gating: each repo can be enabled/disabled per host.
4. Rename `secrets-bootstrap` role to `secrets` for naming consistency.
5. No global opt-in for personal repos; pavg15 must remain unaffected.

## Non-goals

- Automating `ssh-add` (passphrase entry stays interactive — pinentry).
- `pass init` (repo already ships `.gpg-id`; clone is sufficient).
- GPG key import for password-store (already handled by `secrets` role via `gpg_secondary_keys`).
- Enabling these roles on pavg15. Future work.

## Design

### Change 1: Rename `secrets-bootstrap` → `secrets`

Pure mechanical refactor, no behavior change.

**Files touched:**
- `ansible/roles/secrets-bootstrap/` → `ansible/roles/secrets/` (directory rename via `git mv`)
- `ansible/playbooks/bootstrap.yaml`: role list entry
- `ansible/playbooks/secrets-restore.yaml`: role list entry
- `CLAUDE.md`: `roles/{...,secrets-bootstrap}` layout block + "When adding a new secret" section
- `README.md`: bootstrap role enumeration on line 49

### Change 2: New role `password-store`

Installs `pass` (CLI used elsewhere in the system) and clones the password-store repo. Host-gated.

`ansible/roles/password-store/defaults/main.yaml`:
```yaml
---
password_store_repo: "git@github.com:atqamz/password-store"
password_store_path: "{{ ansible_facts['env']['HOME'] }}/.password-store"
password_store_branch: master
```

`ansible/roles/password-store/tasks/main.yaml`:
```yaml
---
- name: Install pass
  become: true
  ansible.builtin.dnf:
    name: pass
    state: present

- name: Clone or update password-store
  ansible.builtin.git:
    repo: "{{ password_store_repo }}"
    dest: "{{ password_store_path }}"
    version: "{{ password_store_branch }}"
    update: true
    accept_hostkey: false
  register: password_store_clone
  failed_when: false

- name: Warn if password-store clone/update failed
  ansible.builtin.debug:
    msg: >-
      WARN: password-store clone/update failed.
      Likely SSH auth (key not loaded in agent).
      Run `ssh-add ~/.ssh/id_ed25519` then re-run:
        ansible-playbook ... --tags password-store
      Detail: {{ password_store_clone.msg | default('(no message)') }}
  when:
    - password_store_clone.failed is defined
    - password_store_clone.failed
```

### Change 3: New role `raw`

Clones knowledge corpus. No package install, no encryption coupling.

`ansible/roles/raw/defaults/main.yaml`:
```yaml
---
raw_repo: "git@github.com:atqamz/raw.git"
raw_path: "{{ ansible_facts['env']['HOME'] }}/raw"
raw_branch: main
```

`ansible/roles/raw/tasks/main.yaml`:
```yaml
---
- name: Clone or update raw corpus
  ansible.builtin.git:
    repo: "{{ raw_repo }}"
    dest: "{{ raw_path }}"
    version: "{{ raw_branch }}"
    update: true
    accept_hostkey: false
  register: raw_clone
  failed_when: false

- name: Warn if raw clone/update failed
  ansible.builtin.debug:
    msg: >-
      WARN: raw clone/update failed.
      Likely SSH auth (key not loaded in agent).
      Run `ssh-add ~/.ssh/id_ed25519` then re-run:
        ansible-playbook ... --tags raw
      Detail: {{ raw_clone.msg | default('(no message)') }}
  when:
    - raw_clone.failed is defined
    - raw_clone.failed
```

### Change 4: Wiring in `bootstrap.yaml`

Insert after `secrets` (renamed), before `ssh-server`:

```yaml
    - role: secrets
      tags: [secrets]
    - role: password-store
      tags: [password-store, secrets]
      when: enable_password_store | default(false)
    - role: raw
      tags: [raw, corpus]
      when: enable_raw | default(false)
    - role: ssh-server
      tags: [ssh, network]
```

Default of `false` on both gates means pavg15 is unaffected.

### Change 5: Host gating on sfx14

`ansible/inventory/host_vars/sfx14.yaml` — append:
```yaml
enable_password_store: true
enable_raw: true
```

`host_vars/pavg15.yaml` untouched.

## Ordering rationale

Both new roles run after `secrets` because they depend on:
- `~/.ssh/id_ed25519` decrypted and placed (for `git@github.com:` auth)
- `~/.ssh/known_hosts` placed (avoids `accept_hostkey: true` weakening)
- `password-store` GPG secondary key imported (so `pass show` works post-clone)

`ssh-agent.socket` is enabled earlier by `ssh-agent` role; the socket is up but no key is loaded. Loading the key requires the passphrase, which is interactive. That is acceptable — first bootstrap run will warn-and-continue; second run after `ssh-add` succeeds.

## Failure semantics

| Scenario | Behavior |
| --- | --- |
| SSH key not loaded in agent | Clone fails → warn debug printed → bootstrap continues. User runs `ssh-add ~/.ssh/id_ed25519`, then `ansible-playbook ... --tags password-store,raw`. |
| Network down | Same path: warn + continue. |
| Repo already cloned, no upstream changes | `ansible.builtin.git` reports `changed=false`. Idempotent. |
| Repo already cloned, local commits diverged | `update: true` will attempt fast-forward; if blocked, soft-fail warns. Manual reconcile required (out of scope to auto-resolve). |
| Host without `enable_*` flag set | Role skipped entirely. |

## Testing

Per role:
```bash
ansible-playbook ansible/playbooks/bootstrap.yaml \
  --limit sfx14 --check --diff --tags password-store
ansible-playbook ansible/playbooks/bootstrap.yaml \
  --limit sfx14 --check --diff --tags raw
```

Live (sfx14, after `ssh-add`):
```bash
ansible-playbook ansible/playbooks/bootstrap.yaml \
  --limit sfx14 --tags password-store,raw
```

Verify:
- `pass show dotfiles/ssh/passphrase` succeeds (password-store usable)
- `ls ~/raw/.git` exists (corpus cloned)
- `git -C ~/raw status` and `git -C ~/.password-store status` clean

Skip verification on pavg15:
```bash
ansible-playbook ansible/playbooks/bootstrap.yaml \
  --limit pavg15 --check --diff
```
Expect: `password-store` and `raw` roles skipped (`when` evaluates false).

## File summary

```
ansible/roles/secrets/                          # renamed from secrets-bootstrap/
ansible/roles/password-store/
  defaults/main.yaml
  tasks/main.yaml
ansible/roles/raw/
  defaults/main.yaml
  tasks/main.yaml
ansible/playbooks/bootstrap.yaml                # role list updated
ansible/playbooks/secrets-restore.yaml          # role rename
ansible/inventory/host_vars/sfx14.yaml          # +2 gate flags
CLAUDE.md                                       # role name updates
README.md                                       # role name update
```
