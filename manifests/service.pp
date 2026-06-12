# @summary Manage a zpinit service: write its `services/*.toml` and drive its runtime state.
#
# This define is the counterpart of `supervisord::program`. It writes the
# TOML definition under `$zpinit::services_dir` AND declares a matching
# `service { <name>: provider => zpinit }` resource, so a single declaration
# both defines and supervises the process.
#
# Migration from supervisord: the supervisord-era parameters
# (`command`, `ensure_process`, `autorestart`, `numprocs`, `priority`,
# `stopsignal`, `stopwaitsecs`, `user`, `directory`, `environment`,
# `redirect_stderr`, `stdout_logfile`/`stderr_logfile`) are accepted under
# their original names and mapped onto zpinit's schema, so a hiera
# `supervisord::programs` hash usually migrates by renaming the top-level key
# to `zpinit::services`. Parameters with no zpinit equivalent
# (`startsecs`, `startretries`, `exitcodes`, `numprocs_start`, `process_name`,
# `stopasgroup`, `killasgroup`, `umask`, `serverurl`, the log
# rotation/capture/events knobs) are accepted-and-ignored so existing data
# does not have to be stripped first; they are listed at the bottom.
#
# zpinit-native parameters (`restart`, the `backoff_*` family, `replicas`/
# `replicas_min`/`replicas_max`, `reload_signal`/`reload_command`/
# `reload_on_change`, `reloadable`, `group`, `cwd`, `ready`, `log`) are also
# exposed for definitions written natively. The `extra_config` escape hatch
# merges arbitrary keys/tables into the TOML for anything not modelled here.
#
# @param command
#   The argv to run. Native zpinit form is an Array[String] (no shell). A
#   String is shell-word-split for supervisord compatibility; if it relies on
#   shell features (pipes, `&&`, redirects, `$VAR`, globs) wrap it yourself as
#   `['sh', '-c', '...']` -- zpinit execs argv directly with no shell.
# @param ensure
#   `present` writes the TOML; `absent` removes it (and stops the service).
# @param ensure_process
#   Runtime intent, mapped onto the service resource:
#   `running` (default) / `stopped` keep the file and set the service state;
#   `removed` deletes the TOML and stops the service; `unmanaged` writes the
#   TOML but declares no service resource (zpinit/operator owns runtime).
# @param service_name
#   zpinit service name (the `name =` TOML key and the service resource
#   title). Defaults to the resource title. Must match `^[a-zA-Z0-9_-]+$`.
# @param priority
#   Lower starts earlier. Rendered as a zero-padded numeric filename prefix
#   (`050_<name>.toml`); zpinit starts services in filename order and strips
#   the prefix to derive the name.
# @param autorestart
#   supervisord restart policy. `true` -> `always`, `false` -> `never`,
#   `'unexpected'` -> `on-failure`. Ignored if `restart` is set directly.
# @param restart
#   zpinit-native restart policy; wins over `autorestart` when both are given.
# @param autostart
#   `false` parks the service disabled (`enable => false`); default enabled.
# @param numprocs
#   supervisord process count -> zpinit `replicas`. Ignored if `replicas` set.
# @param replicas
#   zpinit replica count: a positive Integer or the string `'auto'`.
# @param stopsignal
#   Graceful-stop signal; `SIG` prefix optional (`TERM` or `SIGTERM`).
# @param stopwaitsecs
#   Seconds before SIGKILL escalation -> zpinit `stop_timeout = "<n>s"`.
# @param directory
#   Working directory (supervisord name). `cwd` is the native alias.
# @param environment
#   Per-service env hash -> `[env]`. Values are stringified (zpinit env is
#   string->string). `program_environment` is accepted as an alias.
# @param redirect_stderr
#   When true, stderr is sent to the same destination as stdout.
# @param stdout_logfile
# @param stderr_logfile
#   Log destinations -> `[log]`. supervisord's `AUTO`/`NONE`/`syslog` sentinels
#   map to zpinit's `inherit` (container stdout/stderr); any other value is
#   treated as a path. `{index}` in a path expands per replica.
# @param ready
#   zpinit `[ready]` probe, e.g.
#   `{ 'command' => ['redis-cli','ping'], 'interval' => '500ms', 'timeout' => '30s' }`.
# @param extra_config
#   Arbitrary extra TOML keys/tables merged last (escape hatch for keys not
#   modelled by a named parameter).
define zpinit::service (
  Variant[String[1], Array[String[1], 1]]              $command,
  Enum['present', 'absent']                            $ensure          = 'present',
  Enum['running', 'stopped', 'removed', 'unmanaged']   $ensure_process  = 'running',

  String[1]                                            $service_name    = $title,
  Integer[0, 999]                                      $priority        = 50,

  # --- supervisord-compatible knobs (mapped onto zpinit) ---
  Optional[Variant[Boolean, Enum['unexpected']]]       $autorestart     = undef,
  Optional[Boolean]                                    $autostart       = undef,
  Optional[Integer[1]]                                 $numprocs        = undef,
  Optional[String[1]]                                  $stopsignal      = undef,
  Optional[Integer[0]]                                 $stopwaitsecs    = undef,
  Optional[String[1]]                                  $user            = undef,
  Optional[Stdlib::Absolutepath]                       $directory       = undef,
  Optional[Hash[String[1], NotUndef]]                  $environment     = undef,
  Optional[Hash[String[1], NotUndef]]                  $program_environment = undef,
  Optional[String[1]]                                  $env_var         = undef,
  Optional[Boolean]                                    $redirect_stderr = undef,
  Optional[String[1]]                                  $stdout_logfile  = undef,
  Optional[String[1]]                                  $stderr_logfile  = undef,

  # --- zpinit-native knobs ---
  Optional[String[1]]                                  $group           = undef,
  Optional[Stdlib::Absolutepath]                       $cwd             = undef,
  Optional[Enum['always', 'on-failure', 'never']]      $restart         = undef,
  Optional[String[1]]                                  $backoff_initial     = undef,
  Optional[String[1]]                                  $backoff_max         = undef,
  Optional[String[1]]                                  $backoff_reset_after = undef,
  Optional[Variant[Integer[1], Enum['auto']]]          $replicas        = undef,
  Optional[Integer[1]]                                 $replicas_min    = undef,
  Optional[Integer[1]]                                 $replicas_max    = undef,
  Optional[Boolean]                                    $reloadable      = undef,
  Optional[String[1]]                                  $reload_signal   = undef,
  Optional[Array[String[1], 1]]                        $reload_command  = undef,
  Optional[Array[Enum['cpu', 'memory'], 1]]            $reload_on_change = undef,
  Optional[Hash[String[1], NotUndef]]                  $ready           = undef,
  Optional[Hash[String[1], NotUndef]]                  $log             = undef,

  Hash[String[1], Data]                                $extra_config    = {},

  Optional[Stdlib::Absolutepath]                       $services_dir    = undef,
  Optional[Stdlib::Filemode]                           $config_file_mode = undef,

  # --- accepted-and-ignored (no zpinit equivalent; kept so supervisord
  #     hiera does not need stripping before migration) ---
  Optional[Variant[Integer, String]]                  $numprocs_start          = undef,
  Optional[String]                                    $process_name            = undef,
  Optional[Variant[Integer, String]]                  $startsecs               = undef,
  Optional[Variant[Integer, String]]                  $startretries            = undef,
  Optional[String]                                    $exitcodes               = undef,
  Optional[Boolean]                                   $stopasgroup             = undef,
  Optional[Boolean]                                   $killasgroup             = undef,
  Optional[String]                                    $umask                   = undef,
  Optional[String]                                    $serverurl               = undef,
  Optional[Data]                                      $stdout_logfile_maxbytes = undef,
  Optional[Data]                                      $stdout_logfile_backups  = undef,
  Optional[Data]                                      $stdout_capture_maxbytes = undef,
  Optional[Data]                                      $stdout_events_enabled   = undef,
  Optional[Data]                                      $stderr_logfile_maxbytes = undef,
  Optional[Data]                                      $stderr_logfile_backups  = undef,
  Optional[Data]                                      $stderr_capture_maxbytes = undef,
  Optional[Data]                                      $stderr_events_enabled   = undef,
  Optional[Boolean]                                   $cfgreload               = undef,
) {
  include zpinit

  $dir       = pick($services_dir, $zpinit::services_dir)
  $file_mode = pick($config_file_mode, $zpinit::config_file_mode)

  # supervisord allows a single shell string; zpinit runs argv with no shell.
  if $command =~ String and $command =~ /[|&;<>$`*?]/ {
    warning("zpinit::service[${service_name}]: command '${command}' looks like it relies on a shell, but zpinit runs argv directly with no shell. Wrap it as ['sh', '-c', '...'] if you need shell features.")
  }
  $command_argv = zpinit::command_array($command)

  # restart policy: explicit native $restart wins, else derive from supervisord autorestart.
  $restart_policy = $restart ? {
    undef   => $autorestart ? {
      undef        => undef,
      true         => 'always',
      false        => 'never',
      'unexpected' => 'on-failure',
    },
    default => $restart,
  }

  $replica_count = pick_default($replicas, $numprocs)
  $work_dir      = pick_default($cwd, $directory)
  $stop_sig      = $stopsignal ? {
    undef   => undef,
    default => regsubst(upcase($stopsignal), '^SIG', ''),
  }
  $stop_to       = $stopwaitsecs ? {
    undef   => undef,
    default => "${stopwaitsecs}s",
  }

  # Per-service env. Mirrors supervisord precedence: $env_var (a hiera key
  # name, looked up as a hash) wins, then $program_environment, then
  # $environment. Values are coerced to strings (zpinit env is string->string).
  $env_in = $env_var ? {
    undef   => pick_default($program_environment, $environment, undef),
    default => lookup($env_var, Hash, 'hash', {}),
  }
  $env_map = $env_in ? {
    undef   => undef,
    default => $env_in.reduce({}) |$memo, $kv| { $memo + { $kv[0] => String($kv[1]) } },
  }

  # Log destinations. supervisord AUTO/NONE/syslog -> zpinit 'inherit'.
  $stdout_dest = $stdout_logfile ? {
    undef             => undef,
    /^(AUTO|NONE|syslog)$/ => 'inherit',
    default           => $stdout_logfile,
  }
  $stderr_dest = $redirect_stderr ? {
    true    => $stdout_dest,
    default => $stderr_logfile ? {
      undef                  => undef,
      /^(AUTO|NONE|syslog)$/ => 'inherit',
      default                => $stderr_logfile,
    },
  }
  # Native $log hash overrides the derived stdout/stderr destinations.
  $log_table = $log ? {
    undef   => { 'stdout' => $stdout_dest, 'stderr' => $stderr_dest }.filter |$k, $v| { $v =~ NotUndef },
    default => $log,
  }

  $scalar_config = {
    'name'                => $service_name,
    'command'             => $command_argv,
    'cwd'                 => $work_dir,
    'user'                => $user,
    'group'               => $group,
    'restart'             => $restart_policy,
    'backoff_initial'     => $backoff_initial,
    'backoff_max'         => $backoff_max,
    'backoff_reset_after' => $backoff_reset_after,
    'stop_signal'         => $stop_sig,
    'stop_timeout'        => $stop_to,
    'reloadable'          => $reloadable,
    'replicas'            => $replica_count,
    'replicas_min'        => $replicas_min,
    'replicas_max'        => $replicas_max,
    'reload_signal'       => $reload_signal,
    'reload_command'      => $reload_command,
    'reload_on_change'    => $reload_on_change,
  }.filter |$k, $v| { $v =~ NotUndef }

  $table_config = {
    'env'   => $env_map,
    'log'   => $log_table,
    'ready' => $ready,
  }.filter |$k, $v| { $v =~ NotUndef and $v != {} }

  $config = $scalar_config + $table_config + $extra_config

  $header = @("HEADER")
    # Managed by Puppet -- zpinit::service { '${service_name}': }
    # Local changes will be overwritten on the next puppet run.

    | HEADER

  $conf = sprintf('%s/%03d_%s.toml', $dir, $priority, $service_name)

  # $ensure => absent is treated like ensure_process => removed.
  $effective = $ensure ? {
    'absent' => 'removed',
    default  => $ensure_process,
  }
  $file_ensure = $effective ? {
    'removed' => 'absent',
    default   => 'file',
  }

  file { $conf:
    ensure  => $file_ensure,
    owner   => 'root',
    group   => 'root',
    mode    => $file_mode,
    content => $file_ensure ? {
      'absent' => undef,
      default  => "${header}${zpinit::to_toml($config)}",
    },
  }

  case $effective {
    'running': {
      service { $service_name:
        ensure   => running,
        enable   => pick($autostart, true),
        provider => 'zpinit',
      }
      # Config edits trigger a reload (provider: reread + scoped update / restart).
      File[$conf] ~> Service[$service_name]
    }
    'stopped': {
      service { $service_name:
        ensure   => stopped,
        enable   => pick($autostart, true),
        provider => 'zpinit',
      }
      File[$conf] -> Service[$service_name]
    }
    'removed': {
      # Stop the running process, then remove its definition file.
      service { $service_name:
        ensure   => stopped,
        provider => 'zpinit',
      }
      Service[$service_name] -> File[$conf]
    }
    'unmanaged': {
      # Write the TOML only; zpinit (or an operator) owns runtime state.
    }
    default: {}
  }
}
