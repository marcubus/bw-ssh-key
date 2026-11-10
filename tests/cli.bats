#!/usr/bin/env bats

load test_helper

setup() {
	common_setup
}

@test "--help exits 0 and documents the flags" {
	run "${INSTALL_SH}" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"--host NAME"* ]]
	[[ "$output" == *"--item NAME"* ]]
	[[ "$output" == *"--path PATH"* ]]
	[[ "$output" == *"--server URL"* ]]
	[[ "$output" == *"--list"* ]]
	[[ "$output" == *"--force"* ]]
	[[ "$output" == *"--no-create"* ]]
	[[ "$output" == *"--on-mismatch ACTION"* ]]
	[[ "$output" == *"--no-reconcile"* ]]
	[[ "$output" == *"--no-lock"* ]]
	[[ "$output" == *"--dry-run"* ]]
	[[ "$output" == *"--check"* ]]
	[[ "$output" == *"--install-deps"* ]]
	[[ "$output" == *"-h, --help"* ]]
	[[ "$output" == *"-V, --version"* ]]
}

@test "--version matches SCRIPT_VERSION" {
	local expected
	expected=$(sed -n 's/^readonly SCRIPT_VERSION="\(.*\)"$/\1/p' "${INSTALL_SH}")
	run "${INSTALL_SH}" --version
	[ "$status" -eq 0 ]
	[ "$output" = "bw-ssh-key ${expected}" ]
}

@test "unknown flags exit 1 with a clean message" {
	run "${INSTALL_SH}" --bogus
	[ "$status" -eq 1 ]
	[[ "$output" == *"bw-ssh-key: unknown option: --bogus"* ]]
}

@test "flags with missing values exit 1 with a clean message" {
	local flag
	for flag in --host --item --path --server --on-mismatch; do
		run "${INSTALL_SH}" "${flag}"
		[ "$status" -eq 1 ]
		[[ "$output" == *"bw-ssh-key: ${flag} requires a value"* ]]
	done
}

@test "invalid --on-mismatch values exit 1" {
	run "${INSTALL_SH}" --on-mismatch nope
	[ "$status" -eq 1 ]
	[[ "$output" == *"invalid --on-mismatch value: nope"* ]]
}

@test "--on-mismatch accepts every documented alias" {
	local value
	for value in pull p push u upload skip s; do
		run "${INSTALL_SH}" --check --on-mismatch "${value}"
		[ "$status" -eq 0 ]
	done
}

@test "--check succeeds when dependencies are present" {
	run "${INSTALL_SH}" --check
	[ "$status" -eq 0 ]
	[[ "$output" == *"All dependencies present."* ]]
}

@test "--check reports missing dependencies with exit 2" {
	run env PATH=/usr/bin:/bin "${INSTALL_SH}" --check
	[ "$status" -eq 2 ]
	[[ "$output" == *"missing dependencies"* ]]
	[[ "$output" == *"bw"* ]]
}

@test "--install-deps explains how to proceed when mise is unavailable" {
	run env PATH=/usr/bin:/bin "${INSTALL_SH}" --check --install-deps
	[ "$status" -eq 2 ]
	[[ "$output" == *"mise is not installed"* ]]
}

@test "--install-deps continues after installing dependencies" {
	local install_bin="${BATS_TEST_TMPDIR}/install-bin"
	mkdir -p "${install_bin}"
	ln -s "$(command -v jq)" "${install_bin}/jq"
	make_fake_mise "${install_bin}" "${TEST_BIN}/bw"

	run env PATH="${install_bin}:/usr/bin:/bin" "${INSTALL_SH}" --check --install-deps
	[ "$status" -eq 0 ]
	[[ "$output" == *"All dependencies present."* ]]
}
