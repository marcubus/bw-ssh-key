# bw-ssh-key

Fetch this host's private SSH key from Bitwarden or Vaultwarden and install it at
`~/.ssh/id_ed25519`, in one command.

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/marcubus/bw-ssh-key/main/install.sh)
```

The script derives the vault item name from the machine:

```
<hostname -s>-ssh-key-private      # maaate → maaate-ssh-key-private
```

If that item does not exist, it lists every `*-ssh-key-private` item in the vault
and asks which one to use. It never guesses and never writes a key it did not
fetch.

## What it does

1. Checks dependencies (`bash`, `curl`, `jq`, `bw`, `ssh-keygen`).
2. Asks which vault to use: `bitwarden.com` or a self-hosted Vaultwarden URL.
3. Logs in (email, master password, 2FA) or unlocks an existing session.
4. Syncs the vault and reads the item's SSH private key.
5. Backs up any existing key and installs the new one with mode `600`.
6. Regenerates the `.pub` file, validates the key with `ssh-keygen`, and prints
   the fingerprint and public key.
7. Locks the vault on exit unless `--no-lock` was passed.

## Requirements

| Tool | Why | Install |
|---|---|---|
| `bash` 4+ | arrays, `mapfile` | system package |
| `curl` | only for the one-liner; not used at runtime | system package |
| `jq` | parse `bw` JSON | `mise use -g jq@latest` |
| `bw` | Bitwarden CLI | `mise use -g bitwarden@latest` or `npm i -g @bitwarden/cli` |
| `ssh-keygen` | validate key, derive public key | `openssh-client` |

`--check` reports what is missing and exits `2`. `--install-deps` installs the
mise-managed tools for you.

This repo pins the same tools in `.mise.toml`; run `mise install` after cloning.

## Vault item format

Create an item in Bitwarden/Vaultwarden of type **SSH key**, named
`<hostname>-ssh-key-private`, and paste the private key into its *Private key*
field. The script reads `.sshKey.privateKey`.

For compatibility it also accepts:

- a custom field whose name contains `private` or `ssh`, or
- a secure note whose notes contain a PEM/OpenSSH private key block.

The key must be unencrypted (no passphrase); `ssh-keygen -y` is used to validate
it without prompting.

## Usage

```bash
# normal run on this host
bash <(curl -fsSL https://raw.githubusercontent.com/marcubus/bw-ssh-key/main/install.sh)

# hostname does not match the vault naming
bash <(curl -fsSL .../install.sh) --host maaate

# inspect what the vault has first
bash <(curl -fsSL .../install.sh) --list

# install somewhere other than ~/.ssh/id_ed25519
bash <(curl -fsSL .../install.sh) --path ~/.ssh/deploy_key

# check dependencies only
bash <(curl -fsSL .../install.sh) --check
```

Piping also works because every prompt is read from `/dev/tty`:

```bash
curl -fsSL https://raw.githubusercontent.com/marcubus/bw-ssh-key/main/install.sh | bash
```

### Flags

| Flag | Description |
|---|---|
| `--host NAME` | Derive the item name from `NAME` instead of this hostname |
| `--item NAME` | Use an exact vault item name |
| `--path PATH` | Install the private key at `PATH` (default `~/.ssh/id_ed25519`) |
| `--server URL` | Vault endpoint; skips the interactive prompt |
| `--list` | List available `*-ssh-key-private` items and exit |
| `--force` | Overwrite without confirmation (a timestamped backup is still made) |
| `--no-lock` | Leave the vault unlocked when the script exits |
| `--dry-run` | Fetch and validate the key, but do not install it |
| `--check` | Check dependencies only |
| `--install-deps` | Install missing dependencies with mise where possible |
| `-h`, `--help` | Show help |
| `-V`, `--version` | Show version |

### Environment

| Variable | Effect |
|---|---|
| `BW_EMAIL` | Skip the email prompt |
| `BW_PASSWORD` | Skip the master-password prompt |
| `VAULT_KEY_ITEM` | Exact item name, same as `--item` |

### Item resolution order

```
--item  >  --host  >  VAULT_KEY_ITEM  >  <hostname -s>-ssh-key-private
```

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `1` | Runtime failure (login, network, validation, aborted prompt) |
| `2` | Missing dependency |
| `3` | Vault item not found |

## Security

- The repo contains no secrets, vault IDs, or host-specific data.
- The private key is written with `umask 077`, mode `600`, via a temp file in the
  same directory and an atomic `mv`.
- The master password is never passed on the command line; it is passed to `bw`
  through the environment and cleared on exit.
- `BW_SESSION` is exported only for the lifetime of the script, and the vault is
  locked on exit.
- TLS verification is left on. There is no `--insecure` option.

`curl | bash` runs whatever `main` points at. To reduce that risk, pin a commit
or tag:

```bash
curl -fsSL https://raw.githubusercontent.com/marcubus/bw-ssh-key/<commit>/install.sh | bash
```

See [SECURITY.md](SECURITY.md) for reporting issues.

## Troubleshooting

**`bw` is missing** — run with `--install-deps`, or install it with
`mise use -g bitwarden@latest`.

**Wrong item name** — pass `--host` or `--item`, or run `--list` to see what the
vault contains. The script warns when the hostname looks generic (`localhost`,
`ubuntu`, container IDs).

**Old key still used by the agent** — `ssh-add -D && ssh-add ~/.ssh/id_ed25519`,
or open a new shell.

**2FA fails on login** — the login step runs interactively on `/dev/tty`; make
sure you are running it from a terminal, not from a non-interactive job.

## Development

```bash
mise install
mise run check     # shfmt -d + shellcheck
mise run fmt       # shfmt -w
```

CI runs the same checks on every push and pull request.

## License

MIT — see [LICENSE](LICENSE).
