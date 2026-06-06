# Example: manage a zpinit-supervised service with Puppet.
#
# The provider drives runtime + enablement state via zpctl. It does NOT write
# the service's TOML: manage that with a file resource and notify the service so
# config edits trigger a reload (restart -> scoped `zpctl update`).
#
# Apply inside a container where zpinit is PID 1 and zpctl is on the PATH:
#   puppet apply --modulepath=/etc/puppet/modules examples/init.pp

file { '/etc/zpinit/services/20_nginx.toml':
  ensure  => file,
  mode    => '0644',
  content => @("TOML"),
    command = ["/usr/sbin/nginx", "-g", "daemon off;"]
    restart = "always"

    [ready]
    command  = ["sh", "-c", "test -S /run/nginx.sock || curl -sf http://localhost/ >/dev/null"]
    interval = "200ms"
    timeout  = "10s"
    | TOML
  notify  => Service['nginx'],
}

service { 'nginx':
  ensure   => running,
  enable   => true,
  provider => zpinit,
  require  => File['/etc/zpinit/services/20_nginx.toml'],
}

# Take a service out of rotation: the provider renames the file to
# `<file>.toml.disabled` and applies a scoped `zpctl update worker`.
service { 'worker':
  ensure   => stopped,
  enable   => false,
  provider => zpinit,
}
