#!/usr/bin/env bash
# Renovate postUpgradeTask: after Renovate bumps `version` in a nixos/pkgs file, the
# fixed-output hash next to it is stale. Recompute it in place.
#
#   scripts/renovate/update-nix-hashes.sh nixos/pkgs/<pkg>.nix
#
# Runs from the repo root (Renovate's checkout, or yours — it works by hand too).
# The package file must have exactly one `sha256 = "…"` / `hash = "…"` (on `src`):
# it is blanked, the src built against this flake's nixpkgs, and the hash Nix
# reports written back. Copied from izzy-nix-config, minus its polytoken case.
set -euo pipefail

file=${1:?usage: $0 nixos/pkgs/<pkg>.nix}
[ -f "$file" ] || { echo "no such file: $file" >&2; exit 1; }

generic() {
  local count nixpkgs got
  count=$(grep -cE '^\s*(sha256|hash) = "' "$file" || true)
  if [ "$count" != 1 ]; then
    echo "$file: expected exactly one sha256/hash line, found $count" >&2
    exit 1
  fi

  # An empty hash makes the fetch fail with the real one in the error.
  sed -i -E 's/^(\s*(sha256|hash)) = "[^"]*"/\1 = ""/' "$file"

  nixpkgs=$(nix eval --raw --inputs-from . nixpkgs#path)
  got=$(nix build --no-link --impure --expr \
    "let pkgs = import $nixpkgs { config.allowUnfree = true; }; in (pkgs.callPackage ./$file { }).src" \
    2>&1 | sed -nE 's/^\s*got:\s*(sha256-\S+).*/\1/p' | head -1 || true)

  if [ -z "$got" ]; then
    echo "$file: could not determine the new hash (did the download URL change?)" >&2
    exit 1
  fi
  sed -i -E "s#^(\s*(sha256|hash)) = \"\"#\1 = \"$got\"#" "$file"
}

generic
echo "$file: hashes updated"
