#!/usr/bin/env bash
# Install Ansible collections needed by dotmachines playbooks.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

echo "Installing collections..."
ansible-galaxy collection install -r ansible/requirements.yml --force

echo "Done."
