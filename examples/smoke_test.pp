# Smoke test for the zpinit service provider.
#
# Targets services whose TOMLs are already baked into the image (ssh, cron) so
# it does NOT depend on any role module writing /etc/zpinit/services/*.toml.
# This is deliberately decoupled from site.pp: it proves the provider wires up
# to zpctl end-to-end before any roles are converted off supervisord.
#
# The resource TITLE must equal the zpinit service name (what `zpctl status
# --json` reports), NOT the TOML filename. Numeric prefixes (e.g. 10_ssh.toml)
# are stripped by zpinit; confirm the names first:
#
#   zpctl status --json
#
# Apply inside the container (zpinit is PID 1, zpctl on PATH):
#
#   puppet apply --modulepath=<dir-holding-this-module> \
#     --detailed-exitcodes examples/smoke_test.pp
#
# Run it twice: the second run must report no changes (exit 0), proving
# idempotence.

service { 'ssh':
  ensure   => running,
  enable   => true,
  provider => zpinit,
}

service { 'cron':
  ensure   => running,
  enable   => true,
  provider => zpinit,
}
