#!/usr/bin/env bash

common_setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
	INSTALL_SH="${REPO_ROOT}/install.sh"
	TEST_HOME="${BATS_TEST_TMPDIR}/home"
	TEST_BIN="${BATS_TEST_TMPDIR}/bin"
	LOCAL_KEY="${TEST_HOME}/.ssh/id_ed25519"
	OTHER_KEY="${BATS_TEST_TMPDIR}/other_key"

	mkdir -p "${TEST_HOME}/.ssh" "${TEST_BIN}"
	export HOME="${TEST_HOME}"
	export PATH="${TEST_BIN}:${PATH}"

	export BW_LOG="${BATS_TEST_TMPDIR}/bw.log"
	export BW_ITEMS_FILE="${BATS_TEST_TMPDIR}/items.json"
	export BW_CREATE_FILE="${BATS_TEST_TMPDIR}/create.json"
	export BW_EDIT_FILE="${BATS_TEST_TMPDIR}/edit.json"
	export BW_STATUS=unlocked
	export BW_SERVER_URL="https://vault.example"

	: >"${BW_LOG}"
	: >"${BW_CREATE_FILE}"
	: >"${BW_EDIT_FILE}"
	printf '[]\n' >"${BW_ITEMS_FILE}"

	unset BW_EMAIL BW_PASSWORD BW_2FA_CODE BW_2FA_METHOD VAULT_KEY_ITEM
	export BW_SESSION=test-session

	write_fake_bw
	make_key "${LOCAL_KEY}"
	make_key "${OTHER_KEY}"
}

make_key() { # path
	ssh-keygen -q -t ed25519 -N "" -C "test@example" -f "$1"
}

vault_item_json() { # name key_path
	local name=$1 key=$2
	jq -n \
		--arg name "$name" \
		--rawfile private "$key" \
		--rawfile public "${key}.pub" \
		--arg fingerprint "$(ssh-keygen -lf "${key}.pub" | awk '{print $2}')" \
		'{id: ("item-" + $name), name: $name, type: 5, sshKey: {privateKey: ($private | rtrimstr("\n")), publicKey: ($public | rtrimstr("\n")), keyFingerprint: $fingerprint}}'
}

set_vault_item() { # name key_path
	vault_item_json "$1" "$2" | jq -s '.' >"${BW_ITEMS_FILE}"
}

set_vault_items() { # name key_path [name key_path ...]
	local json='[]' name key
	while (($#)); do
		name=$1
		key=$2
		shift 2
		json=$(jq --argjson item "$(vault_item_json "$name" "$key")" '. + [$item]' <<<"$json")
	done
	printf '%s\n' "$json" >"${BW_ITEMS_FILE}"
}

write_fake_bw() {
	cat >"${TEST_BIN}/bw" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
	printf 'bw'
	printf ' %q' "$@"
	printf '\n'
} >>"${BW_LOG}"

case ${1:-} in
--version)
	printf '%s\n' "2026.10.1"
	;;
status)
	jq -n --arg status "${BW_STATUS:-unlocked}" --arg server "${BW_SERVER_URL:-}" \
		'{status: $status, serverUrl: $server}'
	;;
sync | logout | lock)
	;;
config)
	[[ ${2:-} == server ]]
	;;
login)
	;;
unlock)
	printf '%s\n' "test-session"
	;;
get)
	[[ ${2:-} == item ]]
	jq -e --arg name "${3:-}" '.[] | select(.name == $name)' "${BW_ITEMS_FILE}"
	;;
list)
	[[ ${2:-} == items ]]
	cat "${BW_ITEMS_FILE}"
	;;
encode)
	cat
	;;
create)
	[[ ${2:-} == item ]]
	cat >"${BW_CREATE_FILE}"
	;;
edit)
	[[ ${2:-} == item ]]
	cat >"${BW_EDIT_FILE}"
	;;
*)
	exit 1
	;;
esac
EOF
	chmod +x "${TEST_BIN}/bw"
}

make_fake_mise() { # bin_dir bw_source
	local bin=$1 source=$2
	{
		printf '#!/usr/bin/env bash\n'
		printf 'cp %q %q\n' "$source" "${bin}/bw"
		printf 'chmod +x %q\n' "${bin}/bw"
	} >"${bin}/mise"
	chmod +x "${bin}/mise"
}

run_no_tty() {
	command -v setsid >/dev/null 2>&1 || skip "setsid is required for no-TTY tests"
	run setsid "${INSTALL_SH}" "$@"
}

bw_log_contains() {
	grep -Fq -- "$1" "${BW_LOG}"
}

bw_log_not_contains() {
	! grep -Fq -- "$1" "${BW_LOG}"
}

assert_key_matches() { # actual expected
	[ "$(ssh-keygen -y -f "$1")" = "$(ssh-keygen -y -f "$2")" ]
}
