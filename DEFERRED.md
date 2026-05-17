# Deferred items

Things known-missing from the Ansible bootstrap that need decision before adding.

## Dev tooling

- `@c-development`, `@development-tools`, `@development-libs` package groups.
  Source: legacy `fedora-fresh.sh`. Useful for building native modules / kernel
  modules. Decide: add to `base-packages.groups` baseline or install on-demand.
- `lazygit` (via `dejan/lazygit` COPR). TUI git client.
- `sourcegit`. GUI git client.

## Containers

- Docker CE (`docker` + `docker-compose`, `systemctl enable docker`).
  Status: migrating off Docker to Podman — pending audit before adding either
  to the bootstrap.
