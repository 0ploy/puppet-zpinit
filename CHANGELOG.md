## v0.5.0

### Features

- **Install and update the `zpinit` and `zpctl` binaries from GitHub releases via the new `zpinit::version` parameter.** Set `zpinit::version` to a concrete version (e.g. `'0.5.1'`, a leading `v` is accepted) or the literal `'latest'`, and the `zpinit` class pulls in `zpinit::install`, which compares each binary's `--version` (the binaries print `v<version>`) against the target and, only on mismatch or absence, downloads the release asset for the node's architecture (`*-linux-amd64`/`*-linux-arm64`, mapped from the `os.architecture` fact), verifies it against the release `checksums.txt`, and installs it atomically (download to a temp file in `bin_dir`, then `mv` into place) so a partial or tampered download never replaces the live binary. A concrete version is checked with no network access; `'latest'` is resolved on each run via the `releases/latest` redirect (a single HEAD request, no token, not the rate-limited JSON API) and auto-upgrades the node when a new release lands. Left `undef` (the default) the class declares nothing, so binaries baked into the image are untouched and existing nodes are unaffected. A `manage_package` boolean (default `true`) acts as a master switch: set it `false` to keep Puppet's hands off the binaries on a specific node even when a broader hiera layer sets `version`. `bin_dir` (default `/usr/local/bin`) and `download_base_url` (override for an internal mirror) are also exposed on the `zpinit` class. Requires `curl` and `sha256sum` on the node. Updating the on-disk `zpinit` binary takes effect on the next container start (PID 1 is not hot-swapped); `zpctl` updates take effect immediately.

## v0.4.3

### Fixed

- **Never emit empty-string scalars (e.g. `replicas = ""`) in the TOML.** `replicas`/`cwd` are derived with `pick_default()`, which returns `''` (not `undef`) when all its arguments are unset. The dedup filter only dropped `undef`, so a service without `replicas`/`numprocs` rendered `replicas = ""`, which zpinit's TOML loader rejects (`unknown string "" (only "auto" allowed)`) — and one bad file fails `zpctl update`/`reread` for the whole services directory. The filter now drops empty strings as well as `undef`.

## v0.4.2

### Fixed

- **`start` loads a freshly written service file before failing.** On first deploy a just-written `.toml` is enabled, so `enabled?` is true and the `enable`/`zpctl update` path is skipped — but zpinit has not yet loaded the file into its running set, so `zpctl start` returned `unknown service` and the run failed. `start` now detects that case (unknown service, but the file exists per `resolve`), runs a scoped `zpctl update` to load it, and retries once. Without this, every zpinit-managed service failed to come up on its first Puppet run.

## v0.4.1

### Fixed

- **Accept loose supervisord parameter forms so real `supervisord::programs` data validates.** `supervisord::program` was untyped, so hiera carries booleans both as real booleans (`true`/`yes`) and as quoted strings (`'true'`/`'false'`). `zpinit::service` now types `autostart`/`autorestart` as `Variant[Boolean, String[1]]` and coerces them with `str2bool` (autorestart still honours `'unexpected'`). `priority` widened from `Integer[0, 999]` to `Integer[0, 9999]` (real data uses `1000`), and the filename prefix is now zero-padded to 4 digits (`0050_<name>.toml`) so priorities ≥ 1000 still sort correctly by filename.

## v0.4.0

### Changed

- **`zpinit::service` no longer declares a `Service` resource by default.** The conflated `ensure_process` parameter is replaced by a boolean `manage_service` (default `false`) plus `service_ensure` (`running`/`stopped`, default `running`). By default the define now manages **only** the `services/*.toml` file; set `manage_service => true` to also declare `service { <name>: provider => zpinit }` and wire `File ~> Service`. This prevents duplicate-declaration errors when an upstream module (apache, zabbix, nginx, ...) already owns `Service[X]` — that existing service is flipped to `provider => zpinit` separately, and `zpinit::service` just supplies the TOML. Removal is expressed with `ensure => absent`. `ensure_process` is still accepted (and ignored) so existing `supervisord::programs` data routes through `zpinit::service` without error. Breaking for anyone relying on the old auto-declared service; the module was not yet rolled out, so there are no affected consumers.

## v0.3.0

### Features

- **Data in modules: layered `zpinit::services` now merges across the whole hiera hierarchy.** The module ships its own `hiera.yaml` (v5) and `data/common.yaml` declaring `lookup_options` with `merge: hash` for `zpinit::services`. This makes service definitions spread across hiera layers (per-node, role, common, ...) merge instead of the default `first` (highest layer wins, the rest silently dropped), reproducing the old `hiera_hash('supervisord::programs', {})` behavior. The module's data is consulted as the lowest-priority layer automatically, so no change to the Puppet server's `hiera.yaml` is required; operators can override the key's merge to `deep` in their own data. The old `ensure_resources('supervisord::program', hiera_hash(...))` glue in `site.pp` collapses to `include zpinit`.

## v0.2.0

### Features

- **`zpinit::service` defined type.** Writes the service's `services/NNN_<name>.toml` *and* declares the matching `service { ...: provider => zpinit }`, wiring `File ~> Service` so config edits trigger a reload. Parameters mirror `supervisord::program` (accepted and mapped onto zpinit's schema; unmappable supervisord keys are accepted-and-ignored), with zpinit-native extras (`restart`, the `backoff_*` family, `replicas`, `reload_*`, `ready`, `extra_config`). The `ensure_process` enum (`running`/`stopped`/`removed`/`unmanaged`) controls the file/service wiring.
- **`zpinit` class** holds module defaults (`services_dir`, `config_file_mode`, `purge`) and turns a `zpinit::services` hash into `zpinit::service` resources, the data-driven equivalent of supervisord's `programs`.
- **`zpinit::to_toml` and `zpinit::command_array` functions** render the TOML and shell-word-split a String `command` into argv.

## v0.1.0

### Features

- **Initial `zpinit` service provider.** Drives runtime state (`status`/`start`/`stop`/`restart`) and boot-time enablement (the `.disabled` filename convention) via the `zpctl` control client, using `zpctl status --json`, `resolve`, scoped `update NAME`, `start --wait`, and the stable exit-code taxonomy. Requires zpinit >= 0.5.0. Does not write TOML files: those are managed separately (a `file` resource or baked into the image).
