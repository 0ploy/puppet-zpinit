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
class zpinit (
  Stdlib::Absolutepath           $services_dir     = '/etc/zpinit/services',
  Stdlib::Filemode               $config_file_mode = '0644',
  Boolean                        $purge            = false,
  Hash[String[1], Hash]          $services         = {},
) {
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
