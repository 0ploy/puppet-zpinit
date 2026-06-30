# Class: zpinit::reload
#
# Loads added/changed/removed service TOMLs into the running zpinit set with a
# single global `zpctl update` (config reload: starts added services, stops
# removed, restarts changed -- see zpinit cmdUpdate). Declared via `include` so
# any number of zpinit::service instances share one refreshonly exec, each
# notifying it when its TOML changes.
#
# zpinit does not watch its config dir during a run, so a TOML written by
# zpinit::service is not picked up until something runs `zpctl update`. A
# service whose running state is owned by a Puppet Service[provider => zpinit]
# reloads through that provider; zpinit::service instances that declare no
# Service of their own (manage_service => false) notify this class instead, so a
# file change is never silently ignored.
#
class zpinit::reload {
  exec { 'zpctl_update':
    command     => 'zpctl update',
    path        => ['/usr/local/sbin', '/usr/local/bin', '/usr/sbin', '/usr/bin', '/sbin', '/bin'],
    refreshonly => true,
  }
}
