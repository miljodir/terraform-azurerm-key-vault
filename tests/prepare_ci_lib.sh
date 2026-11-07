prepare_ci() {
  local module_root="${1:-.}"
  local main_file="$module_root/main.tf"
  local fixture_dir="$module_root/tests/fixtures/public_nw_ips"
  local fixture_template="$fixture_dir/outputs.tf.fixture"
  local fixture_file="$fixture_dir/outputs.tf"
  local expected_source='git@github.com:miljodir/cp-shared.git//modules/public_nw_ips?ref=public_nw_ips/v1'
  local fixture_source='./tests/fixtures/public_nw_ips'
  local source_count block_count assignment_count source_match_count temp_file

  if [[ ! -d "$module_root" || ! -f "$main_file" || -L "$main_file" ]]; then
    echo "prepare-ci: main.tf must be a regular file in the module root" >&2
    return 1
  fi
  if [[ -L "$fixture_dir" || ! -f "$fixture_template" || -L "$fixture_template" ]]; then
    echo "prepare-ci: the synthetic public_nw_ips fixture is missing" >&2
    return 1
  fi
  if [[ -e "$fixture_file" || -L "$fixture_file" ]]; then
    echo "prepare-ci: refusing to overwrite an existing fixture output file" >&2
    return 1
  fi

  source_count="$( (grep -F -o -- "$expected_source" "$main_file" || true) | wc -l | tr -d '[:space:]' )"
  read -r block_count assignment_count source_match_count < <(
    awk -v expected="\"$expected_source\"" '
      /^module[[:space:]]+"network_vars"[[:space:]]*\{/ {
        in_network_vars = 1
        blocks++
      }
      in_network_vars && /^[[:space:]]*source[[:space:]]*=/ {
        assignments++
        if ($1 == "source" && $2 == "=" && $3 == expected) matches++
      }
      in_network_vars && /^[[:space:]]*\}/ { in_network_vars = 0 }
      END { printf "%d %d %d\n", blocks, assignments, matches }
    ' "$main_file"
  )

  if [[ "$source_count" != 1 || "$block_count" != 1 || "$assignment_count" != 1 || "$source_match_count" != 1 ]]; then
    echo 'prepare-ci: expected exactly one unchanged SSH source in module "network_vars"' >&2
    return 1
  fi

  temp_file="$(mktemp "$main_file.XXXXXX")"
  if ! sed "s|$expected_source|$fixture_source|" "$main_file" > "$temp_file"; then
    rm -f -- "$temp_file"
    return 1
  fi
  mv -- "$temp_file" "$main_file"
  cp -- "$fixture_template" "$fixture_file"
}
