# Example: define and supervise a zpinit service with a single resource.
#
# zpinit::service writes /etc/zpinit/services/<priority>_<name>.toml AND
# declares the runtime `service { ...: provider => zpinit }`. A change to the
# rendered TOML notifies the service, so the provider reloads it (reread +
# scoped `zpctl update`, then `start --wait`).
#
# Apply inside a container where zpinit is PID 1 and zpctl is on PATH. The
# module directory must be named `zpinit`:
#   puppet apply --modulepath=<dir-containing-zpinit> examples/service.pp

# Native form: argv array, zpinit-native parameters.
zpinit::service { 'nginx':
  command       => ['/usr/sbin/nginx', '-g', 'daemon off;'],
  user          => 'www-data',
  restart       => 'always',
  reload_signal => 'HUP',                    # `zpctl reload nginx` sends HUP
  ready         => {
    'command'  => ['curl', '-sf', 'http://localhost/'],
    'interval' => '200ms',
    'timeout'  => '10s',
  },
}

# supervisord-compatible form: string command (shell-split), supervisord
# parameter names. This is what a migrated `supervisord::program` looks like.
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

# Take a service out of rotation: removes the TOML and stops the process.
zpinit::service { 'legacy':
  command        => ['/usr/bin/legacy'],
  ensure_process => 'removed',
}
