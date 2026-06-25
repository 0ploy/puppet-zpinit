# zpinit_provider

Puppet module: a `service` provider for [zpinit](https://github.com/0ploy/zpinit)
(the Go PID 1 / process supervisor in ScaleCommerce Docker images) plus the
`zpinit::service` defined type and `zpinit` class for managing service TOML from
data. The provider drives runtime state via `zpctl`; it does not write TOML.

**About this file:** agent guidance only - decisions, conventions, and gotchas
that can't be inferred from the code. Don't add file listings or anything an
agent discovers by grepping.

## CHANGELOG

Every user-facing change gets a CHANGELOG.md entry (format borrowed from zdev):

- Add changes under a `## vX.Y.Z` section at the **top** of `CHANGELOG.md`
  (newest first).
- Group bullets under `### Features`, `### Bug Fixes`, or `### Tests`.
- Each bullet leads with a **bold one-line summary**, then prose explaining the
  what and why.
- Keep the section's version in sync with `version` in `metadata.json`.
- No em-dashes anywhere - use regular hyphens (-).

## Style

- **Never use em-dashes** (—). Use regular hyphens (-) in code, comments, and docs.
- Never add "Co-Authored-By" lines to commit messages.

## Gotchas

- **The module dir must be named `zpinit`** on the modulepath (the
  `zpinit::service` define and `zpinit::*` functions depend on it); the Forge
  name is `zeroploy-zpinit`. The bare provider works under any dir name.
- **`zpinit::services` merge** is `hash` (set in `data/common.yaml` via
  `lookup_options`), not Puppet's default `first` - layered hiera merges.
