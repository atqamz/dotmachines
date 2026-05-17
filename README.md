# dotmachines

Ansible-based provisioning for Atqa's machines.

Currently manages:

- **sfx14** — Acer Swift X14 72G (daily driver)
- **pavg15** — HP Pavilion Gaming 15 (Ryzen 5 4600H, GTX 1650)

## What it does (MVP)

1. Set hostname per machine
2. Tune `dnf.conf` (parallel downloads, fastest mirror, keepcache)
3. Enable RPM Fusion (free + nonfree)
4. Install base system packages: WiFi firmware, PipeWire audio, Bluetooth, printing, fonts, CLI tools
5. Install NVIDIA driver (only on hosts where `hardware.has_nvidia: true`)
6. Install multimedia codecs + hardware video acceleration (VA-API + Intel/AMD + Firefox OpenH264)
7. Install Hyprland + companions from `solopasha/hyprland` COPR (GNOME stays as fallback session)
8. Strip GNOME bloat (tour/docs, widgets, media players, libreoffice, flatpak runtime + flathub remote, abrt, malcontent, gnome-software); install lean replacements (`nano`, `snapshot`)
9. Apply firmware updates via `fwupdmgr` (LVFS)
10. Install Tailscale (manual login by default; optional automated join via SOPS-stored auth key)
11. Install Cloudflare WARP CLI (auto-registers, manual `warp-cli connect`)
12. Post-install tweaks: disable `NetworkManager-wait-online`, remove Gnome Software autostart, enable systemd-resolved DNS-over-TLS (Cloudflare 1.1.1.2)
13. Clone [atqamz/dotfiles](https://github.com/atqamz/dotfiles), run its `make stow`
14. Restore SSH keys + secondary GPG identities at correct paths and modes
15. Enable sshd (key-only) + open SSH port in firewalld

## Not in MVP (future)

- Dev toolchain (docker, go, rust, dotnet, vscode, unityhub) — install on demand for now
- WiFi auto-config (GNOME's UI handles first boot)
- RDP for Hyprland (research pending)
- Maintenance playbook (upgrades, health checks)

## Quick start

See [BOOTSTRAP.md](./BOOTSTRAP.md) for the full new-machine procedure.

## Layout

```
ansible/
  inventory/        # hosts.yaml, group_vars, host_vars
  playbooks/        # bootstrap.yaml, secrets-restore.yaml
  roles/            # hostname, dnf-tuning, rpm-fusion, base-packages,
                    # nvidia, multimedia, hyprland, firmware,
                    # tailscale, warp, system-tweaks, dotfiles,
                    # secrets-bootstrap, ssh-server
  requirements.yml  # ansible-galaxy collections

scripts/
  ansible-setup.sh
```
