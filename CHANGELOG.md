# Changelog

All notable changes to `bw-ssh-key` are recorded here.

Versions use CalVer in the form `YYYY.MM.MICRO`. `MICRO` starts at `0` each
month and increments per release; tags are prefixed with `v`.

## [2026.11.2] - 2026-11-11

### Fixed

- A stale CLI login (account present, access token missing) now triggers a
  fresh `bw logout`/`bw login`/`bw unlock` instead of failing later with
  `You are not logged in.`
- JSON is base64-encoded before it is piped to `bw create`/`bw edit`, avoiding
  the Node `EPIPE` stack trace when the vault command exits early.

## [2026.11.1] - 2026-11-11

### Fixed

- SSH fingerprints are now computed with a fallback to the private key, and the
  script fails early with a clear message if no fingerprint can be derived.
  Previously an empty fingerprint produced the misleading Bitwarden CLI error
  `SSH key fingerprint is required.`

## [2026.11.0] - 2026-11-10

### Added

- One-command installer for a per-host SSH key stored in Bitwarden or
  Vaultwarden.
- Vault item name derived from the machine: `<hostname>-ssh-key`.
- Endpoint prompt for `bitwarden.com` or a self-hosted Vaultwarden URL.
- Automatic key creation: when the item is missing, an ed25519 key is generated,
  stored as a type-5 SSH key item, and installed. `--no-create` keeps the old
  picker behaviour.
- `--list`, `--host`, `--item`, `--path`, `--server`, `--force`, `--no-lock`,
  `--dry-run`, `--check`, and `--install-deps`.
- `BW_2FA_CODE` and `BW_2FA_METHOD` for unattended two-step login.
- Local/vault key reconciliation for OpenSSH default identities: pull, push, or
  skip on mismatch, with `--on-mismatch` and `--no-reconcile`.
- Dependency preflight with exit code `2` and per-tool install hints, including
  minimum versions for `jq` (1.6) and `bw` (2024.12.0).
- CI for shellcheck, shfmt, smoke tests, and tag/version matching.
- `mise.lock` for reproducible tool installs, and Dependabot for GitHub Actions.
- Pull request, release, bug report, and feature request templates, plus
  categorized GitHub release notes.
- Main and release-tag rulesets, with a direct-push exemption for the
  maintainer.
- SHA-pinned GitHub Actions and Dependabot security updates.
- Bats tests for CLI flags, dependency checks, item resolution, key
  reconciliation, dry runs, locking, and 2FA arguments.

### Changed

- Key installs target the first existing OpenSSH default identity
  (`id_rsa`, `id_ecdsa`, `id_ecdsa_sk`, `id_ed25519`, `id_ed25519_sk`,
  `id_dsa`), falling back to `~/.ssh/id_ed25519`, and back up any existing key
  with a timestamp.
- Generated keys are staged in a `700` directory under `~/.ssh` and removed
  immediately; nothing is written to `/tmp`.
- Key material is piped to `bw` over stdin, never passed as an argument.
- Master password is passed with `--passwordenv`, not as a positional argument.
- `main` now requires pull requests, the `check` CI job, and linear history;
  squash and rebase merges are allowed.
- GitHub Actions are pinned to commit SHAs and kept current by Dependabot.

### Fixed

- `--check` now reports missing tools with exit code `2` instead of exiting
  silently with code `1`.
- `--install-deps` now continues after installing dependencies instead of
  exiting with code `1`.
- Missing-value errors for `--host`, `--item`, `--path`, `--server`, and
  `--on-mismatch` now use clean messages.
- `--dry-run` no longer uploads an existing local key when the vault item is
  missing.
- `--server` now strips a trailing slash before configuring the endpoint.
- SSH key items now send `keyFingerprint`, which Vaultwarden requires, instead
  of the unsupported `fingerprint` field.
- `bw unlock` and `bw login` now read the password through `--passwordenv`,
  which the current CLI requires for non-interactive use.
- Creating an item now hints at the Vaultwarden `ssh-key-vault-item` feature flag
  when the server rejects the item type.
