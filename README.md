# zpinit_provider

A Puppet [service](https://puppet.com/docs/puppet/latest/types/service.html)
provider for [zpinit](https://github.com/0ploy/zpinit), the single static Go
binary that runs as PID 1 in ScaleCommerce Docker images (replacing tini,
`docker-entrypoint.sh`, supervisord, and PM2).

It lets existing Puppet code that expects a `service { ... }` resource manage
zpinit-supervised processes inside a container, the same way the
[supervisor provider](https://github.com/dskad/puppet-supervisor_provider)
does for supervisord. State names and verbs map onto `zpctl`.

## Requirements

- **zpinit >= 0.5.0.** The provider relies on `zpctl status --json`,
  `zpctl resolve`, scoped `zpctl update NAME`, `zpctl start --wait`, and the
  stable exit-code taxonomy, all introduced in 0.5.0.
- `zpctl` on the agent's `PATH`.
- The agent runs as zpinit's UID (root in a normal container): the control
  socket is gated by `SO_PEERCRED`.

## What it manages, and what it does not

The provider drives **runtime state** (`status` / `start` / `stop` / `restart`)
and **boot-time enablement** (the `.disabled` filename convention). It does
**not** write service TOML files. Manage those with `file` resources (or bake
them into the image) and `notify` the service, so a config edit triggers a
reload:

```puppet
file { '/etc/zpinit/services/20_nginx.toml':
  ensure  => file,
  content => template('profile/nginx.toml.erb'),
  notify  => Service['nginx'],
}

service { 'nginx':
  ensure   => running,
  enable   => true,
  provider => zpinit,
  require  => File['/etc/zpinit/services/20_nginx.toml'],
}
```

## Behavior mapping

| Puppet | zpctl |
| --- | --- |
| `status` | `zpctl status --json NAME` -> `RUNNING` is `running`, anything else (or unknown service) is `stopped` |
| `ensure => running` (`start`) | enable first if disabled, then `zpctl start --wait NAME` (blocks until ready; FATAL fails) |
| `ensure => stopped` (`stop`) | `zpctl stop NAME` |
| `restart` / refresh | config changed (per `zpctl reread`) -> `zpctl update NAME` + `start --wait`; else `zpctl restart --wait NAME` |
| `enable => true` | `zpctl resolve NAME`, rename `*.toml.disabled` -> `*.toml`, `zpctl update NAME` |
| `enable => false` | `zpctl resolve NAME`, rename `*.toml` -> `*.toml.disabled`, `zpctl update NAME` |

The provider locates a service's source file with `zpctl resolve`, so it never
reimplements zpinit's name resolution (numeric prefix stripping, `name=`
override, `.disabled` skipping).

### Readiness verification

`start` and `restart` use `zpctl ... --wait`, which returns only once the
service is `RUNNING` and its `[ready]` probe has passed, or exits non-zero when
the service reaches a terminal/FATAL state. A service that crash-loops is
reported to Puppet as a failure rather than being mistaken for converged.

## Control socket

The provider shells out to `zpctl` and is socket-agnostic. `zpctl` resolves the
socket as `--socket PATH`, then `$ZPINIT_SOCKET`, then `/run/zpinit.sock`. For a
non-default socket, set `ZPINIT_SOCKET` in the agent's environment.

## Limitations

- **Disabled services are invisible to `status`.** zpinit's loader skips
  `*.disabled` files, so they never appear in `zpctl status`. Enablement is
  resolved per-resource via `zpctl resolve`, which scans the directory fresh.
- **Replicas collapse to one logical service.** A service with `replicas > 1`
  reports `running` if any replica is `RUNNING`. The provider cannot target an
  individual `NAME/N` replica.
- **`enable => false` with `ensure => running` is contradictory.** A `.disabled`
  file is not in zpinit's running set, so it cannot be started. Avoid combining
  them.
- **`update` scoping.** Toggling one service applies a scoped
  `zpctl update NAME`, so it cannot incidentally start or stop unrelated
  services. Global `[env]` changes in `zpinit.toml` are deferred by scoped
  updates; apply those out of band with a bare `zpctl update`.

## Development

```sh
puppet apply --modulepath=$(dirname "$PWD") examples/init.pp
```

rspec unit tests are not included in this initial release.

## License

MIT.
