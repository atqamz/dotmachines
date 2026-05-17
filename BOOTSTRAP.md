# Bootstrap a fresh machine

These steps take a freshly-installed Fedora 44 Workstation (or compatible) to a fully provisioned state matching the inventory entry for that hostname.

This repo is **public** and contains no secrets. The encrypted keys live in the private companion repo [`atqamz/secrets`](https://github.com/atqamz/secrets).

## 0. Prerequisites on the new machine

- Fedora 44 Workstation installed, user `atqa` created with sudo
- Network connected (Wi-Fi or Ethernet)
- The bootstrap GPG passphrase (you set it when wrapping `gpg/personal.asc.gpg`)
- Access to the `secrets` private repo (GitHub PAT or `gh auth login`)

## 1. Install bootstrap tooling

```bash
sudo dnf install -y git ansible gnupg2 gh
```

## 2. Authenticate to GitHub (to clone the private secrets repo)

```bash
gh auth login   # choose HTTPS + browser flow
```

## 3. Clone both repos

```bash
mkdir -p ~/repo
gh repo clone atqamz/secrets       ~/repo/secrets
gh repo clone atqamz/dotmachines   ~/repo/dotmachines
```

## 4. Import the primary GPG key (SOPS root of trust)

```bash
cd ~/repo/secrets
gpg --decrypt gpg/personal.asc.gpg | gpg --import
```

You will be prompted **twice**:

1. Symmetric-encryption passphrase (the outer AES256 wrapper added at export time)
2. The key's own passphrase (when GPG imports the secret material)

Then mark it as ultimately trusted:

```bash
echo 'F1F60517602888C8D5E486EB8AD7D4A302EE6771:6:' | gpg --import-ownertrust
gpg --list-secret-keys F1F60517602888C8D5E486EB8AD7D4A302EE6771
```

## 5. Install SOPS

```bash
curl https://mise.run | sh
~/.local/bin/mise install   # picks up dotmachines/.mise.toml
sops --version
```

## 6. Install Ansible collections

```bash
cd ~/repo/dotmachines
bash scripts/ansible-setup.sh
```

## 7. Run the bootstrap

The inventory uses `ansible_connection: local`. Limit to the right hostname and pass the secrets path.

```bash
# On sfx14:
ansible-playbook ansible/playbooks/bootstrap.yaml \
    --limit sfx14 \
    -e secrets_path=$HOME/repo/secrets \
    --ask-become-pass

# On pavg15:
ansible-playbook ansible/playbooks/bootstrap.yaml \
    --limit pavg15 \
    -e secrets_path=$HOME/repo/secrets \
    --ask-become-pass
```

(The default value of `secrets_path` is already `$HOME/repo/secrets`, so `-e` is optional unless you cloned the secrets repo elsewhere.)

To run just one role:

```bash
ansible-playbook ansible/playbooks/bootstrap.yaml --limit pavg15 \
    --tags hostname,dnf,packages --ask-become-pass
```

To dry-run first (recommended on sfx14):

```bash
ansible-playbook ansible/playbooks/bootstrap.yaml --limit sfx14 \
    --check --diff --ask-become-pass
```

## 8. Reboot

NVIDIA `akmod` builds the kernel module asynchronously. After the playbook finishes:

```bash
sudo reboot
```

On boot, log in via either GNOME (default) or Hyprland (select from session menu). Verify:

```bash
nvidia-smi          # pavg15 only
hostnamectl
gpg --list-secret-keys   # should list 5 keys
ssh -T git@github.com
```

## 9. Subsequent re-runs

The playbook is idempotent. Running it again should report zero `changed` tasks.

Secrets-only re-run:

```bash
ansible-playbook ansible/playbooks/secrets-restore.yaml --limit pavg15
```

## Editing secrets

All secret editing happens in `~/repo/secrets`, not here.

```bash
cd ~/repo/secrets
bash scripts/decrypt.sh                    # *.sops.* → *.dec.* (gitignored)
$EDITOR ssh/config.dec.txt
bash scripts/encrypt.sh                    # re-encrypts, cleans up .dec.*
git commit -am "update ssh config"
git push
```

After pushing changes to `secrets`, re-run on the affected machine:

```bash
cd ~/repo/dotmachines
ansible-playbook ansible/playbooks/secrets-restore.yaml --limit <host>
```
