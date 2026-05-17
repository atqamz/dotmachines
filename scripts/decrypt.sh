#!/usr/bin/env bash
set -euo pipefail

# Decrypt all *.sops.* files to *.dec.* equivalents for local editing.
# Decrypted files are gitignored (*.dec.*).

cd "$(git rev-parse --show-toplevel)"

sops_flags() {
  case "$1" in
    *.env)                       echo "--input-type dotenv --output-type dotenv" ;;
    *.key|*.pub|*.pem|*.txt|*.htpasswd) echo "--input-type binary --output-type binary" ;;
    *)                           echo "" ;;
  esac
}

find . -name '*.sops.*' -not -name '.sops.yaml' -not -path './.git/*' | sort | while read -r f; do
  dec=$(echo "$f" | sed 's/\.sops\./\.dec\./')
  if [ -f "$dec" ]; then
    echo "skip $dec (already exists)"
  else
    flags=$(sops_flags "$f")
    echo "$f -> $dec"
    eval sops decrypt $flags "$f" > "$dec" || { rm -f "$dec"; echo "FAILED $f"; }
  fi
done

echo "Done. Edit .dec. files, then run scripts/encrypt.sh to re-encrypt."
