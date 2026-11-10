#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

load test_helper

setup() {
	common_setup
	set_vault_item "workstation-ssh-key" "${LOCAL_KEY}"
}

@test "--host derives the vault item name" {
	run "${INSTALL_SH}" --host workstation --server https://vault.example
	[ "$status" -eq 0 ]
	[[ "$output" == *"workstation-ssh-key"* ]]
}

@test "--item uses an exact vault item name" {
	set_vault_item "exact-item" "${LOCAL_KEY}"
	run "${INSTALL_SH}" --item exact-item --server https://vault.example
	[ "$status" -eq 0 ]
	[[ "$output" == *"exact-item"* ]]
}

@test "VAULT_KEY_ITEM is used when no item flag is passed" {
	set_vault_item "env-item" "${LOCAL_KEY}"
	run env VAULT_KEY_ITEM=env-item "${INSTALL_SH}" --server https://vault.example
	[ "$status" -eq 0 ]
	[[ "$output" == *"env-item"* ]]
}

@test "--item takes precedence over --host and VAULT_KEY_ITEM" {
	set_vault_item "exact-item" "${LOCAL_KEY}"
	run env VAULT_KEY_ITEM=env-item "${INSTALL_SH}" \
		--item exact-item --host workstation --server https://vault.example
	[ "$status" -eq 0 ]
	[[ "$output" == *"exact-item"* ]]
	[[ "$output" != *"workstation-ssh-key"* ]]
	[[ "$output" != *"env-item"* ]]
}

@test "--list prints only ssh-key items" {
	set_vault_items \
		"workstation-ssh-key" "${LOCAL_KEY}" \
		"other-ssh-key" "${OTHER_KEY}" \
		"unrelated" "${LOCAL_KEY}"
	run "${INSTALL_SH}" --list --server https://vault.example
	[ "$status" -eq 0 ]
	[[ "$output" == *"workstation-ssh-key"* ]]
	[[ "$output" == *"other-ssh-key"* ]]
	[[ "$output" != *"unrelated"* ]]
}

@test "--server configures the endpoint and strips a trailing slash" {
	export BW_STATUS=unauthenticated
	export BW_SERVER_URL=""
	export BW_EMAIL=test@example
	export BW_PASSWORD=secret

	run "${INSTALL_SH}" --list --server "https://vault.example/" --host workstation
	[ "$status" -eq 0 ]
	bw_log_contains "bw config server https://vault.example"
}

@test "--no-create still uses an existing item" {
	run "${INSTALL_SH}" --host workstation --no-create --server https://vault.example
	[ "$status" -eq 0 ]
	[[ "$output" == *"workstation-ssh-key"* ]]
}

@test "--no-create does not create a missing item" {
	set_vault_items
	run_no_tty --host missing --no-create --server https://vault.example
	[ "$status" -eq 3 ]
	[[ "$output" == *"No vault item named 'missing-ssh-key'."* ]]
	[ ! -s "${BW_CREATE_FILE}" ]
}

@test "--force overwrites an existing key and makes a backup" {
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run "${INSTALL_SH}" --host workstation --server https://vault.example \
		--on-mismatch pull --force
	[ "$status" -eq 0 ]
	assert_key_matches "${LOCAL_KEY}" "${OTHER_KEY}"
	compgen -G "${LOCAL_KEY}.bak.*" >/dev/null
}

@test "overwriting without --force fails without a TTY" {
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run_no_tty --host workstation --server https://vault.example --on-mismatch pull
	[ "$status" -eq 1 ]
	[[ "$output" == *"bw-ssh-key: aborted"* ]]
}

@test "--path installs to a custom path and skips reconciliation" {
	local custom="${BATS_TEST_TMPDIR}/custom_key"
	run "${INSTALL_SH}" --host workstation --server https://vault.example --path "${custom}"
	[ "$status" -eq 0 ]
	[ -f "${custom}" ]
	[ -f "${custom}.pub" ]
	assert_key_matches "${custom}" "${LOCAL_KEY}"
	[[ "$output" != *"do not match"* ]]
}

@test "--path expands a leading tilde" {
	# shellcheck disable=SC2088 # intentional literal tilde
	run "${INSTALL_SH}" --host workstation --server https://vault.example --path "~/tilde_key"
	[ "$status" -eq 0 ]
	[ -f "${HOME}/tilde_key" ]
}

@test "--dry-run with --path validates but does not install" {
	local custom="${BATS_TEST_TMPDIR}/dry_key"
	run "${INSTALL_SH}" --host workstation --server https://vault.example \
		--path "${custom}" --dry-run
	[ "$status" -eq 0 ]
	[ ! -e "${custom}" ]
	[[ "$output" == *"[dry-run] key is valid; would install it at ${custom}"* ]]
}

@test "--dry-run with a missing item does not upload the local key" {
	set_vault_items
	run "${INSTALL_SH}" --host new --server https://vault.example --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"[dry-run] would create vault item 'new-ssh-key' from the local key."* ]]
	[ ! -s "${BW_CREATE_FILE}" ]
}

@test "--dry-run with no local key does not create the key or vault item" {
	set_vault_items
	rm -f "${LOCAL_KEY}" "${LOCAL_KEY}.pub"
	run "${INSTALL_SH}" --host new --server https://vault.example --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" == *"[dry-run] would create vault item 'new-ssh-key'"* ]]
	[ ! -e "${LOCAL_KEY}" ]
	[ ! -s "${BW_CREATE_FILE}" ]
}

@test "--no-reconcile installs the vault key without comparing" {
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run "${INSTALL_SH}" --host workstation --server https://vault.example \
		--no-reconcile --force
	[ "$status" -eq 0 ]
	assert_key_matches "${LOCAL_KEY}" "${OTHER_KEY}"
	[[ "$output" != *"do not match"* ]]
}

@test "--on-mismatch pull installs the vault key" {
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run "${INSTALL_SH}" --host workstation --server https://vault.example \
		--on-mismatch pull --force
	[ "$status" -eq 0 ]
	assert_key_matches "${LOCAL_KEY}" "${OTHER_KEY}"
}

@test "--on-mismatch push uploads the local key" {
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run "${INSTALL_SH}" --host workstation --server https://vault.example \
		--on-mismatch push
	[ "$status" -eq 0 ]
	[ -s "${BW_EDIT_FILE}" ]
	[ "$(jq -r '.sshKey.privateKey' "${BW_EDIT_FILE}")" = "$(cat "${LOCAL_KEY}")" ]
}

@test "--on-mismatch skip leaves both keys unchanged" {
	local original
	original=$(ssh-keygen -y -f "${LOCAL_KEY}")
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run "${INSTALL_SH}" --host workstation --server https://vault.example \
		--on-mismatch skip
	[ "$status" -eq 0 ]
	[[ "$output" == *"Skipped."* ]]
	[ ! -s "${BW_EDIT_FILE}" ]
	[ "$(ssh-keygen -y -f "${LOCAL_KEY}")" = "$original" ]
}

@test "a key mismatch without --on-mismatch fails without a TTY" {
	set_vault_item "workstation-ssh-key" "${OTHER_KEY}"
	run_no_tty --host workstation --server https://vault.example
	[ "$status" -eq 1 ]
	[[ "$output" == *"local and vault keys differ; pass --on-mismatch pull|push|skip"* ]]
}

@test "--no-lock leaves an acquired session unlocked" {
	export BW_STATUS=locked
	export BW_PASSWORD=secret
	run "${INSTALL_SH}" --list --server https://vault.example --no-lock
	[ "$status" -eq 0 ]
	bw_log_not_contains "bw lock"
}

@test "the vault is locked on exit by default" {
	export BW_STATUS=locked
	export BW_PASSWORD=secret
	run "${INSTALL_SH}" --list --server https://vault.example
	[ "$status" -eq 0 ]
	bw_log_contains "bw lock"
}

@test "BW_2FA_CODE and BW_2FA_METHOD are passed to login" {
	export BW_STATUS=unauthenticated
	export BW_SERVER_URL=""
	export BW_EMAIL=test@example
	export BW_PASSWORD=secret
	export BW_2FA_CODE=123456
	export BW_2FA_METHOD=1

	run "${INSTALL_SH}" --list --server https://vault.example
	[ "$status" -eq 0 ]
	bw_log_contains "bw login --passwordenv BW_PASSWORD --method 1 --code 123456 test@example"
}
