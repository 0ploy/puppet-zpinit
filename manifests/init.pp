# @summary Configure defaults and declare zpinit services from data (hiera).
#
# This class holds the module-wide defaults consumed by `zpinit::service`
# (`services_dir`, `config_file_mode`) and turns a hash of service
# definitions into `zpinit::service` resources -- the data-driven equivalent
# of supervisord's `programs` hash.
#
# Migrating a supervisord hiera layout is usually a key rename:
#
#   # before
#   supervisord::programs:
#     myapp:
#       command: '/usr/bin/myapp --serve'
#       autorestart: true
#       user: 'app'
#       directory: '/srv/app'
#       environment:
#         LOG_LEVEL: 'info'
#
#   # after
#   zpinit::services:
#     myapp:
#       command: '/usr/bin/myapp --serve'
#       autorestart: true
#       user: 'app'
#       directory: '/srv/app'
#       environment:
#         LOG_LEVEL: 'info'
#
# The inner parameter names are shared with `supervisord::program`; keys with
# no zpinit equivalent are accepted and ignored (see `zpinit::service`).
#
# @param services_dir
#   Directory zpinit loads service TOMLs from. Matches zpinit's default.
# @param config_file_mode
#   Mode for the generated TOML files.
# @param purge
#   When true, unmanaged files in `services_dir` are removed. DANGEROUS in
#   images that bake in service TOMLs (ssh, cron, ...): those would be deleted
#   unless also declared here. Leave false unless Puppet owns the whole dir.
# @param services
#   Hash of `zpinit::service` definitions, keyed by service name. Typically
#   supplied from hiera (`zpinit::services:`).
# @param manage_package
#   Master switch for managing the `zpinit`/`zpctl` binaries. When true (the
#   default) and `version` is set, the `zpinit::install` class is declared to
#   install/update them. Set false to keep Puppet's hands off the binaries
#   (e.g. a node whose image bakes them in) even when a broader hiera layer sets
#   `version`. With `version` unset, nothing is installed regardless.
# @param version
#   When set (e.g. `'0.5.1'`, or `'latest'` to track the newest release) and
#   `manage_package` is true, install/update the `zpinit` and `zpctl` binaries
#   from GitHub releases: each binary's `--version` is checked and, on mismatch
#   or absence, the checksum-verified release asset is downloaded for the node's
#   architecture. A concrete version checks with no network access; `'latest'`
#   costs one redirect HEAD per run (not the rate-limited API). Leave `undef`
#   (default) to leave the binaries baked into the image untouched. See
#   `zpinit::install`.
# @param bin_dir
#   Directory the binaries are installed into when `version` is set.
# @param download_base_url
#   Release-download base URL (no tag) for `version` installs. Override for an
#   internal mirror.
class zpinit (
  Stdlib::Absolutepath           $services_dir      = '/etc/zpinit/services',
  Stdlib::Filemode               $config_file_mode  = '0644',
  Boolean                        $purge             = false,
  Hash[String[1], Hash]          $services          = {},
  Boolean                        $manage_package    = true,
  Optional[String[1]]            $version           = undef,
  Stdlib::Absolutepath           $bin_dir           = '/usr/local/bin',
  String[1]                      $download_base_url = 'https://github.com/0ploy/zpinit/releases/download',
) {
  if $manage_package and $version {
    class { 'zpinit::install':
      version           => $version,
      bin_dir           => $bin_dir,
      download_base_url => $download_base_url,
    }
  }

  if $purge {
    file { $services_dir:
      ensure  => directory,
      recurse => true,
      purge   => true,
      force   => true,
    }
  }

  $services.each |$name, $params| {
    zpinit::service { $name:
      * => $params,
    }
  }
}
