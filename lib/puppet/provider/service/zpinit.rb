require 'json'

Puppet::Type.type(:service).provide(:zpinit, :parent => :base) do
  desc <<-EOT
    Manages services supervised by `zpinit` (the PID 1 / process supervisor used
    in ScaleCommerce Docker images) through the `zpctl` control client.

    Service definitions live as TOML files under `/etc/zpinit/services/`. This
    provider does NOT write those files: manage them with `file` resources (or
    bake them into the image) and `notify` the service so config edits trigger a
    reload. The provider drives runtime state (start/stop/restart/status) and
    boot-time enablement (the `.disabled` filename convention) via `zpctl`.

    `enable`/`disable` toggle the `.disabled` suffix on the resolved service file
    and apply a scoped `zpctl update <name>`; the file is located with
    `zpctl resolve`, so the provider never reimplements zpinit's name resolution.

    Requires zpinit >= 0.5.0 (depends on `zpctl status --json`, `resolve`,
    scoped `update NAME`, `start --wait`, and the stable exit-code taxonomy).
    `zpctl` must be on the PATH; the control socket is taken from
    `$ZPINIT_SOCKET` (default `/run/zpinit.sock`).
  EOT

  commands :zpctl => 'zpctl'

  # zpctl exit-code taxonomy (zpinit >= 0.5.0):
  #   0 ok, 1 operation failed, 2 daemon unreachable, 3 unknown service.
  CODE_OK              = 0
  CODE_FAILED          = 1
  CODE_UNREACHABLE     = 2
  CODE_UNKNOWN_SERVICE = 3

  # Run zpctl without raising on non-zero exit so we can branch on the code
  # ourselves (Puppet's generated command method raises on any failure and
  # hides the exit status). Returns the Puppet::Util::Execution::ProcessOutput
  # (a String carrying #exitstatus).
  def self.run_zpctl(*args)
    Puppet::Util::Execution.execute(
      [command(:zpctl)] + args,
      :failonfail => false,
      :combine    => true,
    )
  end

  def run_zpctl(*args)
    self.class.run_zpctl(*args)
  end

  # Parse NDJSON status output into per-line records.
  def self.parse_status(output)
    records = []
    output.to_s.each_line do |line|
      line = line.strip
      next if line.empty?
      begin
        records << JSON.parse(line)
      rescue JSON::ParserError
        next
      end
    end
    records
  end

  # Prefetch: one `zpctl status --json` call lists every loaded service.
  # Replicas (distinct `service` + `replica_index`) collapse to one logical
  # service; a service counts as running if any replica is RUNNING. Services
  # parked as `.disabled` are not loaded and so do not appear here; they are
  # handled per-resource via `resolve`.
  def self.instances
    out = run_zpctl('status', '--json')
    return [] if out.exitstatus == CODE_UNREACHABLE

    states = {}
    parse_status(out).each do |rec|
      name = rec['service']
      next if name.nil?
      states[name] = :running if rec['state'] == 'RUNNING'
      states[name] ||= :stopped
    end
    states.map { |name, state| new(:name => name, :status => state) }
  rescue Puppet::ExecutionFailure
    []
  end

  def status
    out = run_zpctl('status', '--json', resource[:name])
    case out.exitstatus
    when CODE_OK
      running = self.class.parse_status(out).any? { |rec| rec['state'] == 'RUNNING' }
      running ? :running : :stopped
    when CODE_UNKNOWN_SERVICE
      # Not loaded (absent or disabled) == not running, from Puppet's view.
      :stopped
    else
      raise Puppet::Error, "Could not get status of #{resource[:name]}: #{out}"
    end
  end

  # Resolve a service name to its source file. Returns a hash
  # {"name", "path", "enabled"} or nil when no file matches.
  def resolve
    out = run_zpctl('resolve', resource[:name])
    case out.exitstatus
    when CODE_OK
      line = out.to_s.each_line.map(&:strip).reject(&:empty?).last
      JSON.parse(line)
    when CODE_UNKNOWN_SERVICE
      nil
    else
      raise Puppet::Error, "Could not resolve #{resource[:name]}: #{out}"
    end
  rescue JSON::ParserError => e
    raise Puppet::Error, "Could not parse resolve output for #{resource[:name]}: #{e}"
  end

  def enabled?
    info = resolve
    return :false if info.nil?
    info['enabled'] ? :true : :false
  end

  def enable
    info = resolve
    if info.nil?
      raise Puppet::Error, "Cannot enable #{resource[:name]}: no zpinit service file found. " \
        "Manage the TOML under /etc/zpinit/services/ with a file resource first."
    end
    unless info['enabled']
      disabled = info['path']
      enabled  = disabled.sub(/\.disabled\z/, '')
      if disabled == enabled
        raise Puppet::Error, "Cannot enable #{resource[:name]}: resolved path #{disabled} " \
          "is not a .disabled file but the service reports disabled."
      end
      File.rename(disabled, enabled)
    end
    out = run_zpctl('update', resource[:name])
    raise Puppet::Error, "Could not enable #{resource[:name]}: #{out}" unless out.exitstatus == CODE_OK
  end

  def disable
    info = resolve
    if info.nil?
      raise Puppet::Error, "Cannot disable #{resource[:name]}: no zpinit service file found."
    end
    if info['enabled']
      path = info['path']
      File.rename(path, "#{path}.disabled")
    end
    # Scoped update sees the file gone from the loaded set and removes (stops) it.
    out = run_zpctl('update', resource[:name])
    raise Puppet::Error, "Could not disable #{resource[:name]}: #{out}" unless out.exitstatus == CODE_OK
  end

  def start
    enable if enabled? == :false
    # --wait blocks until RUNNING + ready, or exits non-zero on FATAL, so a
    # crash-looping service is reported as a failure rather than converged.
    out = run_zpctl('start', '--wait', resource[:name])

    # First-deploy race: a freshly written .toml is enabled (so `enabled?` is
    # true and `enable`/`update` was skipped above), but zpinit has not loaded
    # it into its running set yet, so `start` reports an unknown service. The
    # file does exist on disk (resolve found it), so load it with a scoped
    # `update` and retry once.
    if out.exitstatus == CODE_UNKNOWN_SERVICE && !resolve.nil?
      upd = run_zpctl('update', resource[:name])
      raise Puppet::Error, "Could not start #{resource[:name]}: update failed: #{upd}" unless upd.exitstatus == CODE_OK
      out = run_zpctl('start', '--wait', resource[:name])
    end

    raise Puppet::Error, "Could not start #{resource[:name]}: #{out}" unless out.exitstatus == CODE_OK
  end

  def stop
    out = run_zpctl('stop', resource[:name])
    # CODE_UNKNOWN_SERVICE: already gone / not loaded == already stopped.
    unless [CODE_OK, CODE_UNKNOWN_SERVICE].include?(out.exitstatus)
      raise Puppet::Error, "Could not stop #{resource[:name]}: #{out}"
    end
  end

  # Restart distinguishes a process bounce from a config pickup. If the on-disk
  # TOML differs from the running config (a notifying file resource changed it),
  # `zpctl reread` lists this service as changed/added; we apply it with a scoped
  # `update` and verify readiness with `start --wait`. Otherwise we do a plain
  # `restart --wait` (config unchanged, just bounce the process).
  def restart
    reread = run_zpctl('reread')
    unless reread.exitstatus == CODE_OK
      raise Puppet::Error, "Could not restart #{resource[:name]}: reread failed: #{reread}"
    end

    name_re = /^[~+]\s+#{Regexp.escape(resource[:name])}\b/
    changed = reread.to_s.each_line.any? { |line| line =~ name_re }

    if changed
      out = run_zpctl('update', resource[:name])
      raise Puppet::Error, "Could not restart #{resource[:name]}: update failed: #{out}" unless out.exitstatus == CODE_OK
      # update has no --wait; verify the reloaded service actually comes up.
      out = run_zpctl('start', '--wait', resource[:name])
    else
      out = run_zpctl('restart', '--wait', resource[:name])
    end
    raise Puppet::Error, "Could not restart #{resource[:name]}: #{out}" unless out.exitstatus == CODE_OK
  end
end
