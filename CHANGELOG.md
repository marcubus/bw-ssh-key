# Changelog

All notable changes to `bw-ssh-key` are recorded here.

Versions use CalVer in the form `YYYY.MM.MICRO`. `MICRO` starts at `0` each
month and increments per release; tags are prefixed with `v`.

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
- Dependency preflight with exit code `2` and per-tool install hints, including
  minimum versions for `jq` (1.6) and `bw` (2024.12.0).
- CI for shellcheck, shfmt, smoke tests, and tag/version matching.
- `mise.lock` for reproducible tool installs, and Dependabot for GitHub Actions.

### Changed

- Key installs target `~/.ssh/id_ed25519` and back up any existing key with a
  timestamp.
- Generated keys are staged in a `700` directory under `~/.ssh` and removed
  immediately; nothing is written to `/tmp`.
- Key material is piped to `bw` over stdin, never passed as an argument.
- Master password is passed with `--passwordenv`, not as a positional argument.

### Fixed

- `bw unlock` and `bw login` now read the password through `--passwordenv`,
  which the current CLI requires for non-interactive use.
- Creating an item now hints at the Vaultwarden `ssh-key-vault-item` feature flag
  when the server rejects the item type.
