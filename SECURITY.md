# Security policy

`bw-ssh-key` handles private SSH keys and vault credentials, so please report
issues privately.

## Reporting a vulnerability

Open a private security advisory on GitHub:

<https://github.com/marcubus/bw-ssh-key/security/advisories/new>

If that is unavailable, contact the maintainer directly. Please do not open a
public issue for anything that could expose key material or a session token.

Include:

- the version or commit you ran,
- the command and flags used,
- what happened, and what you expected,
- the relevant output with **all secrets removed**.

## Never paste

- private or public key material,
- `BW_SESSION` values,
- master passwords or API keys,
- vault item IDs if you consider them sensitive.

## Supported versions

Only the latest commit on `main` is supported. Fixes are released as new commits;
pin a commit SHA if you need reproducibility.

## Scope

In scope: the `install.sh` script in this repository.

Out of scope: the Bitwarden CLI (`bw`) itself, Vaultwarden, and the server hosting
the vault. Report those upstream.
