#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$script_dir/prepare_ci_lib.sh"

expected_source='git@github.com:miljodir/cp-shared.git//modules/public_nw_ips?ref=public_nw_ips/v1'
fixture_source='./tests/fixtures/public_nw_ips'
fixture_content='output "known_public_ips" {
  value = {
    office = "192.0.2.10"
    vpn    = "198.51.100.20"
  }
}'

tmp_root="$(mktemp -d)"
trap 'rm -rf -- "$tmp_root"' EXIT

fail() {
  echo "prepare-ci test failed: $*" >&2
  exit 1
}

make_case() {
  local root="$1"
  mkdir -p "$root/tests/fixtures/public_nw_ips"
  cat > "$root/main.tf" <<EOF
module "network_vars" {
  count  = 1
  source = "$expected_source"
}

resource "example" "untouched" {}
EOF
  printf '%s\n' "$fixture_content" > "$root/tests/fixtures/public_nw_ips/outputs.tf.fixture"
}

assert_unchanged() {
  local actual
  actual="$(cat "$1")"
  [[ "$actual" == "$2" ]] || fail "main.tf was changed after a rejected preparation"
}

success_root="$tmp_root/success"
make_case "$success_root"
prepare_ci "$success_root"
grep -Fqx "  source = \"$fixture_source\"" "$success_root/main.tf" ||
  fail "the expected module source was not replaced"
grep -Fqx 'resource "example" "untouched" {}' "$success_root/main.tf" ||
  fail "unrelated main.tf content changed"
diff -u \
  "$success_root/tests/fixtures/public_nw_ips/outputs.tf.fixture" \
  "$success_root/tests/fixtures/public_nw_ips/outputs.tf" ||
  fail "the synthetic fixture was not materialized exactly"

changed_root="$tmp_root/changed-source"
make_case "$changed_root"
sed -i "s|$expected_source|git@github.com:other/repo.git|" "$changed_root/main.tf"
original="$(cat "$changed_root/main.tf")"
if prepare_ci "$changed_root" 2>/dev/null; then
  fail "a changed dependency source was accepted"
fi
assert_unchanged "$changed_root/main.tf" "$original"

duplicate_root="$tmp_root/duplicate-source"
make_case "$duplicate_root"
printf '\nmodule "unexpected" { source = "%s" }\n' "$expected_source" >> "$duplicate_root/main.tf"
original="$(cat "$duplicate_root/main.tf")"
if prepare_ci "$duplicate_root" 2>/dev/null; then
  fail "a duplicate dependency source was accepted"
fi
assert_unchanged "$duplicate_root/main.tf" "$original"

missing_module_root="$tmp_root/missing-module"
make_case "$missing_module_root"
sed -i 's/module "network_vars"/module "other"/' "$missing_module_root/main.tf"
original="$(cat "$missing_module_root/main.tf")"
if prepare_ci "$missing_module_root" 2>/dev/null; then
  fail "a missing network_vars block was accepted"
fi
assert_unchanged "$missing_module_root/main.tf" "$original"

missing_fixture_root="$tmp_root/missing-fixture"
make_case "$missing_fixture_root"
rm "$missing_fixture_root/tests/fixtures/public_nw_ips/outputs.tf.fixture"
original="$(cat "$missing_fixture_root/main.tf")"
if prepare_ci "$missing_fixture_root" 2>/dev/null; then
  fail "a missing synthetic fixture was accepted"
fi
assert_unchanged "$missing_fixture_root/main.tf" "$original"

existing_output_root="$tmp_root/existing-output"
make_case "$existing_output_root"
cp "$existing_output_root/tests/fixtures/public_nw_ips/outputs.tf.fixture" \
  "$existing_output_root/tests/fixtures/public_nw_ips/outputs.tf"
original="$(cat "$existing_output_root/main.tf")"
if prepare_ci "$existing_output_root" 2>/dev/null; then
  fail "an existing fixture output was overwritten"
fi
assert_unchanged "$existing_output_root/main.tf" "$original"

echo "prepare-ci guard tests passed (6 cases)"
