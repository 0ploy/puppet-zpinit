# Example: define (and optionally supervise) a zpinit service.
#
# zpinit::service always writes /etc/zpinit/services/<priority>_<name>.toml. By
# default it manages ONLY that file. With `manage_service => true` it also
# declares the runtime `service { ...: provider => zpinit }`; a change to the
# rendered TOML then notifies the service, so the provider reloads it (reread +
# scoped `zpctl update`, then `start --wait`).
#
# Apply inside a container where zpinit is PID 1 and zpctl is on PATH. The
# module directory must be named `zpinit`:
#   puppet apply --modulepath=<dir-containing-zpinit> examples/service.pp

# Native, fully-managed form: argv array, zpinit-native parameters,
# manage_service => true so this one resource both defines and supervises it.
zpinit::service { 'nginx':
  command        => ['/usr/sbin/nginx', '-g', 'daemon off;'],
  user           => 'www-data',
  restart        => 'always',
  reload_signal  => 'HUP',                   # `zpctl reload nginx` sends HUP
  manage_service => true,
  ready          => {
    'command'  => ['curl', '-sf', 'http://localhost/'],
    'interval' => '200ms',
    'timeout'  => '10s',
  },
}

# supervisord-compatible form: string command (shell-split), supervisord
# parameter names. This is what a migrated `supervisord::program` looks like.
# No manage_service here: the TOML is written and the running state is owned
# elsewhere (zpinit autostart, or an upstream Service flipped to provider zpinit).
zpinit::service { 'worker':
  command      => '/usr/bin/worker --queue default',
  user         => 'app',
  directory    => '/srv/app',
  autorestart  => true,                      # -> restart = "always"
  numprocs     => 4,                         # -> replicas = 4
  stopsignal   => 'TERM',
  stopwaitsecs => 20,                        # -> stop_timeout = "20s"
  environment  => {
    'LOG_LEVEL' => 'info',
  },
}

# Take a service out of rotation: removes the TOML (and, with manage_service,
# stops the process first).
zpinit::service { 'legacy':
  command => ['/usr/bin/legacy'],
  ensure  => 'absent',
}
