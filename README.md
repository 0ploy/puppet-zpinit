# zpinit_provider

A Puppet [service](https://puppet.com/docs/puppet/latest/types/service.html)
provider for [zpinit](https://github.com/0ploy/zpinit), the single static Go
binary that runs as PID 1 in ScaleCommerce Docker images (replacing tini,
`docker-entrypoint.sh`, supervisord, and PM2).

It lets existing Puppet code that expects a `service { ... }` resource manage
zpinit-supervised processes inside a container, the same way the
[supervisor provider](https://github.com/dskad/puppet-supervisor_provider)
does for supervisord. State names and verbs map onto `zpctl`.

The module ships two layers:

1. **`zpinit::service`** (defined type) — writes the service's
   `services/*.toml` *and* declares the matching `service` resource. Its
   parameters mirror [`supervisord::program`](https://github.com/ghoneycutt/puppet-module-supervisord),
   so a hiera `supervisord::programs` hash usually migrates by renaming the
   top-level key to `zpinit::services`. **Use this for new code and for
   migrating off supervisord.** See [Managing service definitions](#managing-service-definitions).
2. **The `zpinit` service provider** — the low-level `service { …: provider =>
   zpinit }` that drives runtime state via `zpctl`. Use it directly only when
   you manage the TOML yourself (a `file` resource, or baked into the image).

> **Module name.** Because of `zpinit::service` and the `zpinit::*` functions,
> this module must be deployed under the directory name **`zpinit`** (its
> Forge name is `zeroploy-zpinit`). The bare service provider works regardless
> of the directory name, but the manifests and functions do not.

## Requirements

- **zpinit >= 0.5.0.** The provider relies on `zpctl status --json`,
  `zpctl resolve`, scoped `zpctl update NAME`, `zpctl start --wait`, and the
  stable exit-code taxonomy, all introduced in 0.5.0.
- `zpctl` on the agent's `PATH`.
- The agent runs as zpinit's UID (root in a normal container): the control
  socket is gated by `SO_PEERCRED`.

## Managing service definitions

`zpinit::service` writes the service TOML under `$zpinit::services_dir`
(default `/etc/zpinit/services`) and declares the runtime `service` resource,
wiring a config edit to a reload automatically:

```puppet
zpinit::service { 'nginx':
  command     => ['/usr/sbin/nginx', '-g', 'daemon off;'],
  user        => 'www-data',
  autorestart => true,                       # -> restart = "always"
  environment => { 'TZ' => 'UTC' },
  ready       => {
    'command'  => ['curl', '-sf', 'http://localhost/'],
    'interval' => '200ms',
    'timeout'  => '10s',
  },
}
```

That renders `/etc/zpinit/services/050_nginx.toml` and declares
`service { 'nginx': ensure => running, provider => zpinit }`, with the file
`~>` notifying the service so edits trigger a `zpctl` reload.

### From hiera

Declare `class { 'zpinit': }` (or `include zpinit`) and feed it a hash —
the data-driven equivalent of supervisord's `programs`:

```yaml
# hiera
zpinit::services:
  nginx:
    command: '/usr/sbin/nginx -g "daemon off;"'   # string is shell-split
    user: 'www-data'
    autorestart: true
  worker:
    command: ['/usr/bin/worker', '--queue', 'default']
    numprocs: 4                                    # -> replicas = 4
    environment:
      LOG_LEVEL: 'info'
```

### Migrating from `supervisord::program`

`zpinit::service` accepts `supervisord::program`'s parameter names and maps
them onto zpinit's schema. In most cases migration is renaming the hiera key
`supervisord::programs` → `zpinit::services` (and dropping the `supervisord`
class). Mapping:

| `supervisord::program` | zpinit TOML | notes |
| --- | --- | --- |
| `command` (String) | `command` (argv array) | shell-word-split; wrap shell pipelines as `['sh','-c','…']` |
| `ensure` | file `ensure` | `absent` removes the TOML |
| `ensure_process` | service state | `running`/`stopped`; `removed` deletes the TOML; `unmanaged` writes TOML only |
| `autorestart` | `restart` | `true`→`always`, `false`→`never`, `'unexpected'`→`on-failure` |
| `autostart` | service `enable` | `false` parks the service `.disabled` |
| `numprocs` | `replicas` | |
| `priority` | filename prefix | `050_<name>.toml`; lower starts earlier |
| `stopsignal` | `stop_signal` | `SIG` prefix optional |
| `stopwaitsecs` | `stop_timeout` | `→ "<n>s"` |
| `user` | `user` | |
| `directory` | `cwd` | |
| `environment` / `program_environment` / `env_var` | `[env]` | values stringified |
| `redirect_stderr` | `[log].stderr` | sends stderr to the stdout destination |
| `stdout_logfile` / `stderr_logfile` | `[log].stdout` / `[log].stderr` | `AUTO`/`NONE`/`syslog` → `inherit` |

**Accepted but ignored** (no zpinit equivalent, kept so existing data needn't
be stripped): `numprocs_start`, `process_name`, `startsecs`, `startretries`,
`exitcodes`, `stopasgroup`, `killasgroup`, `umask`, `serverurl`, `cfgreload`,
and the `stdout_*`/`stderr_*` log rotation/capture/events knobs (zpinit logs
inherit the container's stdout/stderr by default and are not rotated by
zpinit).

**zpinit-native extras** (beyond supervisord): `restart`, `backoff_initial` /
`backoff_max` / `backoff_reset_after`, `replicas` (`Integer` or `'auto'`) /
`replicas_min` / `replicas_max`, `reload_signal` / `reload_command` /
`reload_on_change`, `reloadable`, `group`, `cwd`, `ready`, `log`, and an
`extra_config` hash merged verbatim into the TOML for anything unmodelled.

## Using the bare provider

The provider on its own drives **runtime state** (`status` / `start` / `stop`
/ `restart`) and **boot-time enablement** (the `.disabled` convention) but does
**not** write TOML. Manage the file yourself and `notify` the service:

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
- **No shell in `command`.** zpinit execs argv directly. A string `command`
  is shell-word-split (quotes honoured), but pipes / `&&` / redirects / `$VAR`
  need an explicit `['sh', '-c', '…']`; `zpinit::service` warns when it spots
  shell metacharacters in a string command.
- **Changing `priority` orphans the old file.** The priority is encoded in the
  filename (`050_<name>.toml`); changing it writes a new file and leaves the
  old one behind. Set `zpinit::purge => true` (Puppet owns the whole
  `services/` dir) or remove the stale file out of band. **`purge` deletes any
  TOML not declared in Puppet — do not enable it on images that bake in
  service files (ssh, cron, …) unless those are declared too.**
- **Globals (`zpinit.toml`) are out of scope.** This module manages
  `services/*.toml`. Manage `zpinit.toml` with a `file` resource if you need to.

## Development

```sh
# The module dir must be named `zpinit` on the modulepath.
puppet apply --modulepath=<dir-containing-the-zpinit-module> examples/service.pp
```

Run the Ruby functions' logic check (no Puppet required):

```sh
ruby -c lib/puppet/functions/zpinit/to_toml.rb
```

rspec unit tests are not included in this initial release.

## License

MIT.
