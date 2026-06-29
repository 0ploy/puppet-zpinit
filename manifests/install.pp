# @summary Install or update the `zpinit` and `zpctl` binaries from GitHub releases.
#
# Private class, declared by the `zpinit` class only when `$zpinit::version` is
# set. For each binary it compares the installed `--version` (the binaries print
# `v<version>`) against the target and, on mismatch or absence, downloads the
# pinned release asset for the node's architecture, verifies it against the
# release `checksums.txt`, and installs it atomically. With `$zpinit::version`
# unset this class is never declared, so a binary baked into the image is left
# untouched.
#
# Requires `curl` and `sha256sum` on the node (present on the supported base
# images). Updating the on-disk `zpinit` binary does not restart PID 1; it takes
# effect when the container next starts. `zpctl` is a client and updates take
# effect immediately.
#
# @api private
#
# @param version
#   Target version, e.g. `'0.5.1'` (a leading `v` is accepted), or the literal
#   `'latest'` to track the newest GitHub release. A concrete version is checked
#   with no network access; `'latest'` is resolved on each run via the
#   `releases/latest` redirect (one HEAD request, not the rate-limited API) and
#   auto-upgrades when a new release lands.
# @param bin_dir
#   Directory the binaries are installed into. Must be writable and on `PATH`.
# @param download_base_url
#   Release-download base URL without the tag. Override for an internal mirror;
#   the asset and `checksums.txt` are fetched from `<base>/v<version>/`.
class zpinit::install (
  String[1]            $version,
  Stdlib::Absolutepath $bin_dir           = '/usr/local/bin',
  String[1]            $download_base_url = 'https://github.com/0ploy/zpinit/releases/download',
) {
  assert_private()

  # Release assets are named *-linux-<goarch>. Map the node's architecture fact
  # (Debian/Ubuntu: amd64/arm64; RedHat: x86_64/aarch64) onto Go's arch names.
  $_arch = $facts['os']['architecture'] ? {
    'x86_64'  => 'amd64',
    'amd64'   => 'amd64',
    'aarch64' => 'arm64',
    'arm64'   => 'arm64',
    default   => fail("zpinit::install: unsupported architecture '${facts['os']['architecture']}'"),
  }

  # Helper does download + checksum-verify + atomic install; idempotency is the
  # exec's `unless` version check, so the helper itself always (re)downloads.
  $_helper = "${bin_dir}/.zpinit-install-binary"
  file { $_helper:
    ensure => file,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/zpinit/zpinit-install-binary.sh',
  }

  ['zpinit', 'zpctl'].each |String $bin| {
    $_path = "${bin_dir}/${bin}"
    # The helper resolves `$version` (a concrete version with no network, or
    # `latest` via one redirect HEAD) to the `v<semver>` the binary reports, so
    # the check stays exact and `latest` auto-upgrades when a new release lands.
    exec { "zpinit-install-${bin}":
      command  => "${_helper} ${bin} '${version}' ${_arch} ${bin_dir} ${download_base_url}",
      unless   => "${_path} --version 2>/dev/null | grep -Fxq \"\$(${_helper} --resolve '${version}' ${download_base_url})\"",
      path     => ['/usr/local/sbin', '/usr/local/bin', '/usr/sbin', '/usr/bin', '/sbin', '/bin'],
      provider => shell,
      require  => File[$_helper],
    }
  }
}
