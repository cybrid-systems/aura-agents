#!/usr/bin/env bash
# Install the official Aura nightly the same way aura-runner does:
# the prebuilt archive and its .sha256 from
# https://github.com/cybrid-systems/aura/releases/download/nightly/
# Asset names match scripts/aura-path.sh in cybrid-systems/aura-runner:
#   aura-nightly-linux-x86_64.tar.gz
#   aura-nightly-linux-arm64.tar.gz
# A cached copy is reused while the release still publishes the same
# archive digest. The nightly tag rolls, so a cached binary can be
# arbitrarily old; the digest beside the archive is the cheap check that
# tells us the cached copy is still the published one. The only stdout
# line is the bin directory, so a GitHub Actions step can append it to
# GITHUB_PATH.
set -euo pipefail

tag="${AURA_VERSION:-nightly}"
if [[ "$tag" == "nightly" ]]; then
  slug="nightly"
elif [[ "$tag" == v* ]]; then
  slug="${tag#v}"
else
  slug="$tag"
fi

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="x86_64" ;;
  aarch64|arm64) arch="arm64" ;;
  *)
    echo "unsupported architecture: $arch" >&2
    exit 1
    ;;
esac

name="aura-${slug}-linux-${arch}.tar.gz"
base="${AURA_DOWNLOAD_BASE:-https://github.com/cybrid-systems/aura/releases/download/${tag}}"
cache="${AURA_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/aura-agents}"
dest="${cache}/${slug}/${arch}"
stamp="${dest}/.archive-sha256"

# The digest the release publishes beside the archive. Empty when the
# release cannot be reached (offline): the caller then keeps whatever
# is cached rather than failing the install.
published_sha() {
  local tmp
  tmp="$(mktemp)" || return 0
  if curl -fsSL --retry 3 --retry-delay 1 -o "$tmp" "${base}/${name}.sha256" 2>/dev/null; then
    awk 'NF { print $1; exit }' "$tmp"
  fi
  rm -f "$tmp"
}

cached_sha=""
if [[ -f "$stamp" ]]; then
  cached_sha="$(tr -d '[:space:]' < "$stamp")"
fi

want="$(published_sha)"
# Reuse the cached copy only when the release still publishes the same
# archive. A rolled nightly then replaces the cached binary instead of
# leaving an arbitrarily old one in place.
reuse=0
if [[ -x "${dest}/bin/aura" ]]; then
  if [[ -z "$want" || "$cached_sha" == "$want" ]]; then
    reuse=1
  fi
fi

if [[ "$reuse" == 0 ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 --retry-delay 1 -o "${tmp}/${name}" "${base}/${name}"
  curl -fsSL --retry 3 --retry-delay 1 -o "${tmp}/${name}.sha256" "${base}/${name}.sha256"
  (cd "$tmp" && sha256sum -c "${name}.sha256") >&2
  tar -xzf "${tmp}/${name}" -C "$tmp"
  top=""
  for d in "$tmp"/*; do
    if [[ -d "${d}/bin" ]]; then
      top="$d"
      break
    fi
  done
  if [[ -z "$top" ]]; then
    echo "Aura archive has no bin/aura" >&2
    exit 1
  fi
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$top" "$dest"
  chmod +x "${dest}/bin/aura"
  awk 'NF { print $1; exit }' "${tmp}/${name}.sha256" > "$stamp"
fi

echo "${dest}/bin"
"${dest}/bin/aura" --version >&2
