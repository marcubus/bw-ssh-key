#!/usr/bin/env bash
#
# bw-ssh-key: fetch a per-host private SSH key from Bitwarden/Vaultwarden
# and install it at the OpenSSH default identity for this host.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/marcubus/bw-ssh-key/main/install.sh)
#
# The vault item name is derived from the machine:
#   <hostname -s>-ssh-key      e.g. workstation-ssh-key
#
# See --help for flags.

set -euo pipefail

readonly SCRIPT_NAME="bw-ssh-key"
readonly SCRIPT_VERSION="2026.11.1"
readonly ITEM_SUFFIX="-ssh-key"
readonly DEFAULT_KEY_DIR="${HOME}/.ssh"
readonly DEFAULT_KEY_FALLBACK="${DEFAULT_KEY_DIR}/id_ed25519"
readonly -a DEFAULT_KEY_NAMES=(id_rsa id_ecdsa id_ecdsa_sk id_ed25519 id_ed25519_sk id_dsa)

resolve_default_key_path() {
	local name
	for name in "${DEFAULT_KEY_NAMES[@]}"; do
		if [[ -f "${DEFAULT_KEY_DIR}/${name}" ]]; then
			printf '%s' "${DEFAULT_KEY_DIR}/${name}"
			return 0
		fi
	done
	printf '%s' "$DEFAULT_KEY_FALLBACK"
}

is_default_key_path() { # path
	local path=$1 name
	[[ $(dirname "$path") == "$DEFAULT_KEY_DIR" ]] || return 1
	for name in "${DEFAULT_KEY_NAMES[@]}"; do
		[[ $(basename "$path") == "$name" ]] && return 0
	done
	return 1
}

readonly EX_OK=0
readonly EX_FAIL=1
readonly EX_DEPS=2
readonly EX_NOTFOUND=3

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
	C_RESET=$'\033[0m'
	C_BOLD=$'\033[1m'
	C_RED=$'\033[31m'
	C_YEL=$'\033[33m'
	C_DIM=$'\033[2m'
else
	C_RESET=""
	C_BOLD=""
	C_RED=""
	C_YEL=""
	C_DIM=""
fi

info() { printf '%s\n' "$*"; }
warn() { printf '%s%s%s\n' "$C_YEL" "$*" "$C_RESET" >&2; }
err() { printf '%s%s%s\n' "$C_RED" "$*" "$C_RESET" >&2; }

die() {
	err "$SCRIPT_NAME: $1"
	exit "${2:-$EX_FAIL}"
}

usage() {
	cat <<EOF
${C_BOLD}${SCRIPT_NAME} ${SCRIPT_VERSION}${C_RESET}: install this host's SSH key from Bitwarden/Vaultwarden

Usage:
  bash <(curl -fsSL https://raw.githubusercontent.com/marcubus/bw-ssh-key/main/install.sh) [options]

Options:
  --host NAME       Derive the item name from NAME instead of this hostname
  --item NAME       Use an exact vault item name
  --path PATH       Install at PATH (default: first existing id_* key, else ~/.ssh/id_ed25519)
  --server URL      Vault endpoint (skips the interactive prompt)
  --list            List available *${ITEM_SUFFIX} items and exit
  --force           Overwrite without confirmation (a backup is still made)
  --no-create       Do not create a vault item when the key is missing
  --on-mismatch ACTION
                    Local key differs from the vault: pull, push, or skip
                    (default: ask; applies only to the default key path)
  --no-reconcile    Do not compare the local default key with the vault
  --no-lock         Leave the vault unlocked when the script exits
  --dry-run         Fetch or generate and validate the key, but do not create or install it
  --check           Check dependencies only, then exit
  --install-deps    Install missing dependencies with mise where possible
  -h, --help        Show this help
  -V, --version     Show the version

Environment:
  BW_EMAIL          Bitwarden email (skips the email prompt)
  BW_PASSWORD       Master password (skips the password prompt)
  BW_2FA_CODE       Two-step login code (enables non-interactive 2FA)
  BW_2FA_METHOD     Two-step method number (default: 0, authenticator)
  VAULT_KEY_ITEM    Exact vault item name (same as --item)

Item resolution order:
  --item  >  --host  >  VAULT_KEY_ITEM  >  <hostname -s>${ITEM_SUFFIX}

If the item is missing, a new ed25519 key is generated for this host and stored
in the vault as an SSH key item. Use --no-create to pick an existing item instead.

Exit codes:
  0 success   1 failure   2 missing dependency   3 item not found
EOF
}

# ---------------------------------------------------------------------------
# Terminal handling
# ---------------------------------------------------------------------------

TTY_OPEN=0

have_tty() {
	[[ -r /dev/tty && -w /dev/tty ]]
}

open_tty() {
	((TTY_OPEN)) && return 0
	have_tty || return 1
	if ! { exec 3<>/dev/tty; } 2>/dev/null; then
		return 1
	fi
	TTY_OPEN=1
}

prompt() { # prompt [default]
	local msg=$1 def=${2-} ans
	if ((! TTY_OPEN)); then
		err "no TTY available for prompts (pass flags or set BW_EMAIL/BW_PASSWORD)"
		return 1
	fi
	if [[ -n $def ]]; then
		printf '%s [%s]: ' "$msg" "$def" >&3
	else
		printf '%s: ' "$msg" >&3
	fi
	IFS= read -r ans <&3 || return 1
	printf '%s' "${ans:-$def}"
}

prompt_secret() { # prompt
	local msg=$1 ans
	if ((! TTY_OPEN)); then
		err "no TTY available for prompts (pass flags or set BW_EMAIL/BW_PASSWORD)"
		return 1
	fi
	printf '%s: ' "$msg" >&3
	IFS= read -rs ans <&3 || return 1
	printf '\n' >&3
	printf '%s' "$ans"
}

confirm() { # message [default]
	local msg=$1 def=${2:-n} ans
	ans=$(prompt "$msg" "$def") || return 1
	case ${ans,,} in
	y | yes) return 0 ;;
	*) return 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------

declare -a MISSING=()

collect_dep() { # command hint
	command -v "$1" >/dev/null 2>&1 || MISSING+=("$1|$2")
}

version_ge() { # actual required
	local -a actual required
	IFS=. read -ra actual <<<"$1"
	IFS=. read -ra required <<<"$2"

	local i av bv
	for ((i = 0; i < ${#required[@]}; i++)); do
		av=${actual[i]:-0}
		bv=${required[i]:-0}
		if ((10#$av > 10#$bv)); then
			return 0
		fi
		if ((10#$av < 10#$bv)); then
			return 1
		fi
	done
	return 0
}

check_jq_version() {
	local v
	v=$(jq --version 2>/dev/null) || return 0
	v=${v#jq-}
	version_ge "$v" "1.6" || MISSING+=("jq>=1.6|found jq $v; mise use -g jq@latest")
}

check_bw_version() {
	local v=""
	if command -v timeout >/dev/null 2>&1; then
		v=$(timeout 5 bw --version 2>/dev/null | tail -n1) || v=""
	else
		v=$(bw --version 2>/dev/null | tail -n1) || v=""
	fi
	[[ -n $v ]] || return 0
	version_ge "$v" "2024.12.0" || MISSING+=("bw>=2024.12.0|found bw $v; mise use -g bitwarden@latest")
}

preflight() {
	MISSING=()
	if ((BASH_VERSINFO[0] < 4)); then
		die "bash 4 or newer is required" "$EX_DEPS"
	fi
	collect_dep jq "mise use -g jq@latest"
	collect_dep bw "mise use -g bitwarden@latest  (or: npm i -g @bitwarden/cli)"
	collect_dep ssh-keygen "system package: openssh-client"
	collect_dep hostname "system package: coreutils"
	collect_dep mktemp "system package: coreutils"

	if command -v jq >/dev/null 2>&1; then
		check_jq_version
	fi
	if command -v bw >/dev/null 2>&1; then
		check_bw_version
	fi
}

report_missing() {
	err "$SCRIPT_NAME: missing dependencies"
	err ""
	local entry cmd hint
	for entry in "${MISSING[@]}"; do
		cmd=${entry%%|*}
		hint=${entry#*|}
		printf '  %-16s %s\n' "$cmd" "$hint" >&2
	done
	err ""
	err "Re-run with --install-deps to let mise install what it can."
	exit "$EX_DEPS"
}

install_deps() {
	local need_mise=0 entry
	for entry in "${MISSING[@]}"; do
		case ${entry%%|*} in
		jq | bw) need_mise=1 ;;
		esac
	done

	if ((need_mise)); then
		if command -v mise >/dev/null 2>&1; then
			info "Installing jq and the Bitwarden CLI via mise ..."
			mise use -g jq@latest bitwarden@latest
		else
			err "mise is not installed; install the missing tools manually:"
			err "  jq: https://jqlang.github.io/jq/download/"
			err "  bw: npm i -g @bitwarden/cli"
			exit "$EX_DEPS"
		fi
	fi

	preflight
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

HOST_OVERRIDE=""
ITEM_OVERRIDE=${VAULT_KEY_ITEM:-}
KEY_PATH=""
SERVER_URL=""
LIST_ONLY=0
FORCE=0
CREATE=1
RECONCILE=1
ON_MISMATCH=""
SKIP_INSTALL=0
LOCK_AFTER=1
DRY_RUN=0
CHECK_ONLY=0
INSTALL_DEPS=0

need_value() { # flag value
	[[ -n ${2:-} ]] || die "$1 requires a value"
}

parse_args() {
	while (($#)); do
		case $1 in
		--host)
			need_value "$1" "${2:-}"
			HOST_OVERRIDE=$2
			shift 2
			;;
		--item)
			need_value "$1" "${2:-}"
			ITEM_OVERRIDE=$2
			shift 2
			;;
		--path)
			need_value "$1" "${2:-}"
			KEY_PATH=$2
			shift 2
			;;
		--server)
			need_value "$1" "${2:-}"
			SERVER_URL=$2
			shift 2
			;;
		--list)
			LIST_ONLY=1
			shift
			;;
		--force)
			FORCE=1
			shift
			;;
		--no-create)
			CREATE=0
			shift
			;;
		--on-mismatch)
			need_value "$1" "${2:-}"
			ON_MISMATCH=$2
			case ${ON_MISMATCH,,} in
			pull | p | push | u | upload | skip | s) ;;
			*) die "invalid --on-mismatch value: $ON_MISMATCH" ;;
			esac
			shift 2
			;;
		--no-reconcile)
			RECONCILE=0
			shift
			;;
		--no-lock)
			LOCK_AFTER=0
			shift
			;;
		--dry-run)
			DRY_RUN=1
			shift
			;;
		--check)
			CHECK_ONLY=1
			shift
			;;
		--install-deps)
			INSTALL_DEPS=1
			shift
			;;
		-h | --help)
			usage
			exit "$EX_OK"
			;;
		-V | --version)
			printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
			exit "$EX_OK"
			;;
		*) die "unknown option: $1 (try --help)" ;;
		esac
	done

	if [[ -z $KEY_PATH ]]; then
		KEY_PATH=$(resolve_default_key_path)
	fi

	# shellcheck disable=SC2088 # intentional literal-tilde match
	case $KEY_PATH in
	"~/"*) KEY_PATH="${HOME}/${KEY_PATH#\~/}" ;;
	"~") KEY_PATH=$HOME ;;
	esac
}

# ---------------------------------------------------------------------------
# Item name resolution
# ---------------------------------------------------------------------------

detect_host() {
	local h
	h=$(hostname -s 2>/dev/null || uname -n)
	h=${h,,}
	h=${h%.local}
	printf '%s' "$h"
}

is_generic_host() {
	case $1 in
	localhost | ubuntu | debian | linux | host | container | docker | wsl | vm | test) return 0 ;;
	esac
	[[ $1 =~ ^[0-9a-f]{8,}$ ]] && return 0
	return 1
}

resolve_item() {
	if [[ -n $ITEM_OVERRIDE ]]; then
		ITEM=$ITEM_OVERRIDE
		return 0
	fi

	local host=${HOST_OVERRIDE:-$(detect_host)}
	[[ -n $host ]] || die "could not determine hostname; pass --host"

	if [[ -z $HOST_OVERRIDE ]] && is_generic_host "$host"; then
		warn "hostname '$host' looks generic; the vault item may not exist."
		if open_tty; then
			host=$(prompt "Hostname to use for the item name" "$host") || die "aborted"
		fi
	fi

	ITEM="${host}${ITEM_SUFFIX}"
}

# ---------------------------------------------------------------------------
# Vault endpoint and authentication
# ---------------------------------------------------------------------------

choose_server() {
	if [[ -n $SERVER_URL ]]; then
		SERVER_URL=${SERVER_URL%/}
		return 0
	fi

	local choice
	choice=$(prompt "Vault endpoint: 1) bitwarden.com  2) self-hosted Vaultwarden (enter URL)" "1") || die "aborted"

	case $choice in
	1) SERVER_URL="https://vault.bitwarden.com" ;;
	2) SERVER_URL=$(prompt "Vaultwarden URL" "") || die "aborted" ;;
	http*) SERVER_URL=$choice ;;
	*) die "invalid choice: $choice" ;;
	esac

	[[ $SERVER_URL == http* ]] || die "invalid server URL: $SERVER_URL"
	SERVER_URL=${SERVER_URL%/}
}

bw_status() {
	local status
	status=$(bw status 2>/dev/null | jq -r '.status // "unknown"' 2>/dev/null) || status="unknown"
	printf '%s' "$status"
}

current_server() {
	local server
	server=$(bw status 2>/dev/null | jq -r '.serverUrl // empty' 2>/dev/null) || server=""
	printf '%s' "${server%/}"
}

configure_server() {
	local cur
	cur=$(current_server)

	if [[ -n $cur && $cur != "$SERVER_URL" ]]; then
		local status
		status=$(bw_status)
		if [[ $status != "unauthenticated" ]]; then
			warn "Currently logged in to $cur."
			if ((! FORCE)); then
				confirm "Log out and switch to $SERVER_URL?" "y" || die "aborted"
			fi
			bw logout >/dev/null 2>&1 || true
		fi
	fi

	if [[ $cur != "$SERVER_URL" ]]; then
		bw config server "$SERVER_URL" >/dev/null
	fi
}

SESSION_ACQUIRED=0
VAULT_PASSWORD=""

login_vault() {
	local email=${BW_EMAIL:-}

	if [[ -z $VAULT_PASSWORD ]]; then
		VAULT_PASSWORD=${BW_PASSWORD:-}
	fi
	if [[ -z $email ]]; then
		email=$(prompt "Bitwarden email" "") || die "aborted"
	fi
	if [[ -z $VAULT_PASSWORD ]]; then
		VAULT_PASSWORD=$(prompt_secret "Master password") || die "aborted"
	fi

	local -a login_cmd=(bw login --passwordenv BW_PASSWORD)
	if [[ -n ${BW_2FA_CODE:-} ]]; then
		login_cmd+=(--method "${BW_2FA_METHOD:-0}" --code "$BW_2FA_CODE")
	fi
	login_cmd+=("$email")

	info "Logging in as $email ..."
	local rc=0
	if ((TTY_OPEN)); then
		BW_PASSWORD="$VAULT_PASSWORD" "${login_cmd[@]}" <&3 || rc=$?
	else
		BW_PASSWORD="$VAULT_PASSWORD" "${login_cmd[@]}" || rc=$?
	fi

	((rc == 0)) || die "login failed"
}

unlock_vault() {
	if [[ -z $VAULT_PASSWORD ]]; then
		VAULT_PASSWORD=${BW_PASSWORD:-}
	fi
	if [[ -z $VAULT_PASSWORD ]]; then
		VAULT_PASSWORD=$(prompt_secret "Master password") || die "aborted"
	fi

	info "Unlocking vault ..."
	local session rc=0
	session=$(BW_PASSWORD="$VAULT_PASSWORD" bw unlock --passwordenv BW_PASSWORD --raw) || rc=$?

	((rc == 0)) && [[ -n $session ]] || die "unlock failed"
	BW_SESSION=$session
	SESSION_ACQUIRED=1
}

authenticate() {
	local status
	status=$(bw_status)

	case $status in
	unlocked)
		info "Vault already unlocked."
		;;
	locked)
		unlock_vault
		;;
	unauthenticated)
		login_vault
		unlock_vault
		;;
	*)
		die "unexpected vault status: $status"
		;;
	esac

	[[ -n ${BW_SESSION:-} ]] || die "failed to obtain a vault session"
	export BW_SESSION
}

sync_vault() {
	info "Syncing vault ..."
	bw sync >/dev/null 2>&1 || warn "sync failed; continuing with cached vault data"
}

# ---------------------------------------------------------------------------
# Item lookup
# ---------------------------------------------------------------------------

KEY=""

extract_key() { # json
	local json=$1 key

	key=$(jq -r '.sshKey.privateKey // empty' <<<"$json")
	if [[ -z $key ]]; then
		key=$(jq -r '
      [ .fields[]? | select((.name // "") | test("private|ssh"; "i")) | .value ]
      | map(select(. != null and . != ""))
      | first // empty
    ' <<<"$json")
	fi
	if [[ -z $key ]]; then
		local notes
		notes=$(jq -r '.notes // empty' <<<"$json")
		if [[ $notes == *"PRIVATE KEY"* ]]; then
			key=$notes
		fi
	fi

	printf '%s' "$key"
}

fetch_item() { # name
	local name=$1 json

	json=$(bw get item "$name" 2>/dev/null) || return 1
	[[ -n $json ]] || return 1

	local key
	key=$(extract_key "$json")
	[[ -n $key ]] || return 1

	KEY=$key
	VAULT_PUB=$(jq -r '.sshKey.publicKey // empty' <<<"$json")
	ITEM=$name
	return 0
}

list_ssh_items() {
	bw list items 2>/dev/null |
		jq -r --arg suffix "$ITEM_SUFFIX" '.[] | select(.name | endswith($suffix)) | .name' |
		sort -u
}

item_exists() { # name
	bw get item "$1" >/dev/null 2>&1
}

pub_blob() { # public key line -> "type base64"
	awk '{print $1" "$2}' <<<"$1"
}

fingerprint_of_pub() { # public key line
	ssh-keygen -lf <(printf '%s\n' "$1") 2>/dev/null | awk '{print $2}'
}

ssh_fingerprint() { # private or public key file
	local fp
	fp=$(ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}')
	[[ -n $fp ]] || fp=$(ssh-keygen -lf "$1.pub" 2>/dev/null | awk '{print $2}')
	printf '%s' "$fp"
}

derive_pub_from_private() { # private key string
	local dir keyfile pub
	dir=$(mktemp -d "${HOME}/.ssh/.bw-ssh-key.XXXXXX")
	chmod 700 "$dir"
	TMP_DIR=$dir
	keyfile="${dir}/key"

	(umask 077 && printf '%s\n' "$1" >"$keyfile")
	pub=$(ssh-keygen -y -f "$keyfile" 2>/dev/null) || pub=""

	rm -rf "$dir"
	TMP_DIR=""
	printf '%s' "$pub"
}

create_key_item_from_local() { # name
	local name=$1
	local dir pubfile private fingerprint json

	dir=$(mktemp -d "${HOME}/.ssh/.bw-ssh-key.XXXXXX")
	chmod 700 "$dir"
	TMP_DIR=$dir
	pubfile="${dir}/key.pub"

	if ! ssh-keygen -y -f "$KEY_PATH" >"$pubfile" 2>/dev/null; then
		die "cannot read local key $KEY_PATH (passphrase-protected?)"
	fi

	private=$(cat "$KEY_PATH")
	fingerprint=$(ssh_fingerprint "$pubfile")
	[[ -n $fingerprint ]] || die "cannot compute SSH fingerprint for $KEY_PATH"

	json=$(jq -n \
		--arg name "$name" \
		--rawfile private "$KEY_PATH" \
		--rawfile public "$pubfile" \
		--arg fingerprint "$fingerprint" \
		'{type: 5, name: $name, notes: null, favorite: false, sshKey: {privateKey: ($private | rtrimstr("\n")), publicKey: ($public | rtrimstr("\n")), keyFingerprint: $fingerprint}}')

	if ! printf '%s' "$json" | bw encode | bw create item >/dev/null; then
		err "Hint: Vaultwarden needs EXPERIMENTAL_CLIENT_FEATURE_FLAGS=ssh-key-vault-item,ssh-agent"
		die "failed to create vault item '$name'"
	fi

	KEY=$private
	ITEM=$name
	SKIP_INSTALL=1

	rm -rf "$dir"
	TMP_DIR=""
	info "Created vault item '$name' from the local key."
}

push_local_key() { # item
	local name=$1
	local item_json id dir pubfile fingerprint updated

	item_json=$(bw get item "$name" 2>/dev/null) || die "could not read vault item '$name'"
	id=$(jq -r '.id // empty' <<<"$item_json")
	[[ -n $id ]] || die "vault item '$name' has no id"

	dir=$(mktemp -d "${HOME}/.ssh/.bw-ssh-key.XXXXXX")
	chmod 700 "$dir"
	TMP_DIR=$dir
	pubfile="${dir}/key.pub"

	if ! ssh-keygen -y -f "$KEY_PATH" >"$pubfile" 2>/dev/null; then
		die "cannot read local key $KEY_PATH (passphrase-protected?)"
	fi
	fingerprint=$(ssh_fingerprint "$pubfile")
	[[ -n $fingerprint ]] || die "cannot compute SSH fingerprint for $KEY_PATH"

	updated=$(jq \
		--rawfile private "$KEY_PATH" \
		--rawfile public "$pubfile" \
		--arg fingerprint "$fingerprint" \
		'.sshKey.privateKey = ($private | rtrimstr("\n"))
		 | .sshKey.publicKey = ($public | rtrimstr("\n"))
		 | .sshKey.keyFingerprint = $fingerprint' <<<"$item_json")

	if ! printf '%s' "$updated" | bw encode | bw edit item "$id" >/dev/null; then
		die "failed to update vault item '$name'"
	fi

	rm -rf "$dir"
	TMP_DIR=""
	info "Uploaded the local key to vault item '$name'."
}

reconcile_key() {
	((RECONCILE)) || return 0
	is_default_key_path "$KEY_PATH" || return 0
	[[ -f $KEY_PATH ]] || return 0
	[[ -n $KEY ]] || return 0

	local local_pub vault_pub
	local_pub=$(ssh-keygen -y -f "$KEY_PATH" 2>/dev/null) || local_pub=""
	if [[ -z $local_pub ]]; then
		warn "Cannot read $KEY_PATH (passphrase-protected?); skipping key comparison."
		return 0
	fi

	vault_pub=${VAULT_PUB:-}
	if [[ -z $vault_pub ]]; then
		vault_pub=$(derive_pub_from_private "$KEY")
	fi
	if [[ -z $vault_pub ]]; then
		warn "Could not derive the vault public key; skipping comparison."
		return 0
	fi

	if [[ $(pub_blob "$local_pub") == "$(pub_blob "$vault_pub")" ]]; then
		info "Local key matches vault item '$ITEM'."
		SKIP_INSTALL=1
		return 0
	fi

	warn "Local key and vault item '$ITEM' do not match."
	info "  local fingerprint: $(fingerprint_of_pub "$local_pub")"
	info "  vault fingerprint: $(fingerprint_of_pub "$vault_pub")"

	local action=${ON_MISMATCH:-}
	if [[ -z $action ]]; then
		if ((DRY_RUN)); then
			info "[dry-run] would ask to pull the vault key or push the local key."
			return 0
		fi
		if ((! TTY_OPEN)); then
			die "local and vault keys differ; pass --on-mismatch pull|push|skip"
		fi
		action=$(prompt "Keys differ: [p]ull vault key, [u]pload local key, [s]kip" "s") || die "aborted"
	fi

	case ${action,,} in
	p | pull) action=pull ;;
	u | upload | push) action=push ;;
	s | skip) action=skip ;;
	*) die "invalid --on-mismatch value: $action" ;;
	esac

	case $action in
	pull)
		if ((DRY_RUN)); then
			info "[dry-run] would pull the vault key over the local key."
		fi
		return 0
		;;
	push)
		if ((DRY_RUN)); then
			info "[dry-run] would push the local key to the vault."
			return 0
		fi
		push_local_key "$ITEM"
		SKIP_INSTALL=1
		;;
	skip)
		info "Skipped."
		exit "$EX_OK"
		;;
	esac
}

create_key_item() { # name
	local name=$1
	local dir keyfile private fingerprint json

	mkdir -p "${HOME}/.ssh"
	chmod 700 "${HOME}/.ssh" 2>/dev/null || true
	dir=$(mktemp -d "${HOME}/.ssh/.bw-ssh-key.XXXXXX")
	chmod 700 "$dir"
	TMP_DIR=$dir
	keyfile="${dir}/key"

	(umask 077 && ssh-keygen -t ed25519 -N "" -C "$(id -un)@$(hostname -s)" -f "$keyfile" >/dev/null)

	private=$(cat "$keyfile")
	fingerprint=$(ssh_fingerprint "$keyfile")
	[[ -n $fingerprint ]] || die "cannot compute SSH fingerprint for the generated key"

	if ((DRY_RUN)); then
		info "[dry-run] would create vault item '$name' (${fingerprint})"
	else
		json=$(jq -n \
			--arg name "$name" \
			--rawfile private "$keyfile" \
			--rawfile public "$keyfile.pub" \
			--arg fingerprint "$fingerprint" \
			'{type: 5, name: $name, notes: null, favorite: false, sshKey: {privateKey: ($private | rtrimstr("\n")), publicKey: ($public | rtrimstr("\n")), keyFingerprint: $fingerprint}}')
		if ! printf '%s' "$json" | bw encode | bw create item >/dev/null; then
			err "Hint: Vaultwarden needs EXPERIMENTAL_CLIENT_FEATURE_FLAGS=ssh-key-vault-item,ssh-agent"
			die "failed to create vault item '$name'"
		fi
		info "Created vault item '$name'"
	fi

	KEY=$private
	ITEM=$name

	rm -rf "$dir"
	TMP_DIR=""
	return 0
}

find_item() {
	if fetch_item "$ITEM"; then
		return 0
	fi

	if item_exists "$ITEM"; then
		warn "Vault item '$ITEM' exists but has no usable private key."
	elif ((CREATE)); then
		if ((RECONCILE)) && is_default_key_path "$KEY_PATH" && [[ -f $KEY_PATH ]]; then
			if ((DRY_RUN)); then
				info "[dry-run] would create vault item '$ITEM' from the local key."
				exit "$EX_OK"
			fi
			info "No vault item named '$ITEM'; uploading the existing local key."
			create_key_item_from_local "$ITEM"
			return 0
		fi
		info "No vault item named '$ITEM'; generating a new key for this host."
		create_key_item "$ITEM"
		return 0
	else
		warn "No vault item named '$ITEM'."
	fi

	local -a names=()
	mapfile -t names < <(list_ssh_items)

	if ((${#names[@]})); then
		info ""
		info "Available SSH key items:"
		local i=1 name
		for name in "${names[@]}"; do
			printf '  %d) %s\n' "$i" "$name"
			i=$((i + 1))
		done
		info ""
	else
		warn "No items ending in '$ITEM_SUFFIX' were found."
	fi

	if ((! TTY_OPEN)); then
		die "item not found: $ITEM" "$EX_NOTFOUND"
	fi

	while :; do
		local choice
		choice=$(prompt "Pick a number, [h]ost to retry, or [q]uit" "q") || return 1

		case $choice in
		q | Q)
			return 1
			;;
		h | H)
			local host
			host=$(prompt "Hostname" "") || return 1
			[[ -n $host ]] || continue
			ITEM="${host,,}${ITEM_SUFFIX}"
			if fetch_item "$ITEM"; then
				return 0
			fi
			warn "No vault item named '$ITEM'."
			;;
		"")
			continue
			;;
		*[!0-9]*)
			warn "Enter a number, h, or q."
			;;
		*)
			if ((choice >= 1 && choice <= ${#names[@]})); then
				if fetch_item "${names[choice - 1]}"; then
					return 0
				fi
				warn "Could not read a private key from '${names[choice - 1]}'."
			else
				warn "No item number $choice."
			fi
			;;
		esac
	done
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------

TMP_KEY=""
TMP_DIR=""

install_key() { # key path
	local key=$1 path=$2
	local dir base
	dir=$(dirname "$path")
	base=$(basename "$path")

	mkdir -p "$dir"
	chmod 700 "$dir" 2>/dev/null || true

	local tmp
	tmp=$(mktemp "${dir}/.${base}.XXXXXX")
	TMP_KEY=$tmp

	(umask 077 && printf '%s\n' "$key" >"$tmp")
	chmod 600 "$tmp"

	local pub
	if ! pub=$(ssh-keygen -y -f "$tmp" 2>/dev/null); then
		die "fetched value is not a usable private key"
	fi

	if ((DRY_RUN)); then
		info "[dry-run] key is valid; would install it at $path"
		info "[dry-run] fingerprint: $(ssh-keygen -lf "$tmp" 2>/dev/null | awk '{print $2}')"
		return 0
	fi

	if [[ -e $path ]]; then
		if ((! FORCE)); then
			confirm "$path exists. Back it up and overwrite?" "y" || die "aborted"
		fi
		local backup
		backup="${path}.bak.$(date +%Y%m%d-%H%M%S)"
		cp -p "$path" "$backup"
		info "Backed up existing key to $backup"
	fi

	mv -f "$tmp" "$path"
	TMP_KEY=""
	chmod 600 "$path"

	printf '%s\n' "$pub" >"${path}.pub"
	chmod 644 "${path}.pub"

	info ""
	info "Installed private key: $path"
	info "Installed public key:  ${path}.pub"
	info "Fingerprint:           $(ssh-keygen -lf "$path" 2>/dev/null | awk '{print $2}')"
	info ""
	info "Public key (add it to GitHub if it is not registered yet):"
	info "$pub"
	info ""
	info "${C_DIM}If ssh-agent already holds an old key, run: ssh-add -D && ssh-add $path${C_RESET}"
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

cleanup() {
	local rc=$?

	if [[ -n ${TMP_KEY:-} && -f ${TMP_KEY:-} ]]; then
		rm -f "$TMP_KEY"
	fi
	if [[ -n ${TMP_DIR:-} && -d ${TMP_DIR:-} ]]; then
		rm -rf "$TMP_DIR"
	fi

	if [[ -n ${BW_SESSION:-} ]]; then
		if ((LOCK_AFTER && SESSION_ACQUIRED)); then
			bw lock >/dev/null 2>&1 || true
		fi
		unset BW_SESSION
	fi

	unset VAULT_PASSWORD
	exit "$rc"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
	parse_args "$@"

	preflight

	if ((${#MISSING[@]})); then
		if ((INSTALL_DEPS)); then
			install_deps
		fi
		if ((${#MISSING[@]})); then
			report_missing
		fi
	fi

	if ((CHECK_ONLY)); then
		info "All dependencies present."
		exit "$EX_OK"
	fi

	open_tty || true

	resolve_item
	choose_server
	configure_server
	authenticate
	sync_vault

	if ((LIST_ONLY)); then
		list_ssh_items
		exit "$EX_OK"
	fi

	find_item || die "no SSH key item found" "$EX_NOTFOUND"
	reconcile_key

	if ((SKIP_INSTALL)); then
		local pubtmp="${KEY_PATH}.pub.tmp"
		if ssh-keygen -y -f "$KEY_PATH" >"$pubtmp" 2>/dev/null; then
			mv -f "$pubtmp" "${KEY_PATH}.pub"
			chmod 644 "${KEY_PATH}.pub"
		else
			rm -f "$pubtmp"
		fi
		info "Local key already matches vault item '$ITEM'; nothing to install."
		return 0
	fi

	install_key "$KEY" "$KEY_PATH"
}

main "$@"
