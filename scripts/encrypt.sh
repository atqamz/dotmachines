#!/usr/bin/env bash
set -euo pipefail

# Re-encrypt all *.dec.* files back to their *.sops.* equivalents,
# then remove the decrypted files.

cd "$(git rev-parse --show-toplevel)"

sops_flags() {
  case "$1" in
    *.env)                       echo "--input-type dotenv --output-type dotenv" ;;
    *.key|*.pub|*.pem|*.txt|*.htpasswd) echo "--input-type binary --output-type binary" ;;
    *)                           echo "" ;;
  esac
}

find . -name '*.dec.*' -not -path './.git/*' | sort | while read -r f; do
  enc=$(echo "$f" | sed 's/\.dec\./\.sops\./')
  flags=$(sops_flags "$f")
  echo "$f -> $enc"
  tmp=$(mktemp)
  if eval sops encrypt $flags "$f" > "$tmp"; then
    mv "$tmp" "$enc"
    rm "$f"
    echo "  cleaned $f"
  else
    rm -f "$tmp"
    echo "FAILED $f"
  fi
done

echo "Done."
