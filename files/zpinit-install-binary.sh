#!/bin/sh
# Download, checksum-verify, and atomically install a single zpinit release
# binary. Managed by the zpinit Puppet module (zpinit::install); not meant to be
# run by hand. The calling exec's `unless` already gates on the installed
# version, so install mode unconditionally (re)downloads when invoked.
#
# Two modes:
#   zpinit-install-binary.sh --resolve <version> <base_url>
#       Print the version string the binaries report (`v<semver>`). `latest` is
#       resolved via the GitHub `releases/latest` redirect (one HEAD request, no
#       API token, not the rate-limited API); a concrete version prints as-is
#       with no network access. Used by the exec's `unless` check.
#
#   zpinit-install-binary.sh <name> <version> <arch> <bin_dir> <base_url>
#       Resolve <version>, then download/verify/install <name> for <arch>.
#   name      zpinit | zpctl
#   version   bare semver (e.g. 0.5.1, leading v ok) or the literal `latest`
#   arch      release arch token: amd64 | arm64
#   bin_dir   install directory, e.g. /usr/local/bin
#   base_url  release download base (no trailing slash), .../releases/download
set -eu

# resolve_version <version-or-latest> <base_url> -> prints bare semver (no `v`).
# Only `latest` touches the network.
resolve_version() {
  _v="$1"
  _base="$2"
  case "$_v" in
    latest)
      # .../releases/download -> .../releases/latest, which 302-redirects to
      # .../releases/tag/v<semver>. Read the redirect target, no body fetched.
      _lurl="$(printf '%s' "$_base" | sed -E 's#/download/?$#/latest#')"
      _redir="$(curl -fsS -o /dev/null -w '%{redirect_url}' -I "$_lurl")"
      _tag="$(printf '%s' "$_redir" | sed -n -E 's#.*/tag/(v?[0-9][^/]*)$#\1#p')"
      [ -n "$_tag" ] || {
        echo "zpinit-install: could not resolve 'latest' from ${_lurl} (redirect: ${_redir:-none})" >&2
        return 1
      }
      printf '%s' "${_tag#v}"
      ;;
    *)
      printf '%s' "${_v#v}"
      ;;
  esac
}

if [ "${1:-}" = "--resolve" ]; then
  printf 'v%s\n' "$(resolve_version "$2" "$3")"
  exit 0
fi

name="$1"
version="$2"
arch="$3"
bin_dir="$4"
base_url="$5"

ver="$(resolve_version "$version" "$base_url")"
asset="${name}-linux-${arch}"
url="${base_url}/v${ver}/${asset}"
sums_url="${base_url}/v${ver}/checksums.txt"

# mktemp inside bin_dir so the final `mv` is an atomic same-filesystem rename
# (a half-written download never appears as the live binary).
tmp="$(mktemp "${bin_dir}/.${name}.XXXXXX")"
sums="$(mktemp)"
cleanup() { rm -f "$tmp" "$sums"; }
trap cleanup EXIT INT TERM

curl -fsSL -o "$tmp" "$url"
curl -fsSL -o "$sums" "$sums_url"

expected="$(awk -v a="$asset" '$2 == a { print $1 }' "$sums")"
[ -n "$expected" ] || { echo "zpinit-install: no checksum for ${asset} in ${sums_url}" >&2; exit 1; }

actual="$(sha256sum "$tmp" | awk '{ print $1 }')"
[ "$expected" = "$actual" ] || {
  echo "zpinit-install: checksum mismatch for ${asset}: expected ${expected}, got ${actual}" >&2
  exit 1
}

chmod 0755 "$tmp"
mv -f "$tmp" "${bin_dir}/${name}"
trap - EXIT INT TERM
rm -f "$sums"
echo "zpinit-install: installed ${name} v${ver} to ${bin_dir}/${name}"
