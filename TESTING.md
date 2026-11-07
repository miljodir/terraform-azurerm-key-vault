# Testing

This module is tested with the native [`terraform test`](https://developer.hashicorp.com/terraform/language/tests)
framework. GitHub Actions runs formatting, validation and tests with both
Terraform and OpenTofu for pull requests to any target branch and pushes to
`main` (see `.github/workflows/terraform-test.yaml`).

## What runs in CI

| Job      | Command                              | Purpose                                         |
| -------- | ------------------------------------ | ----------------------------------------------- |
| Format   | `terraform fmt` / `tofu fmt`         | Consistent formatting                          |
| Validate | `init` + `validate`                  | Syntax, types and references are valid         |
| Test     | `terraform test` / `tofu test`       | Module behaviour (defaults, wiring, validation) |

CI uses the shared reusable workflow
[`terraform-test.yaml@terraform-test/v0`](https://github.com/miljodir/workflow-templates/blob/terraform-test/v0/.github/workflows/terraform-test.yaml).
It checks the same test suite with both tools and requires at least one test run
to pass for each engine. CI requests OpenTofu `1.x`, a floating SemVer range
that selects the latest stable 1.x release when the workflow runs; it is not a
fixed version pin. OpenTofu 1.13.9 was verified locally for this change. A
command that exits successfully but reports zero tests is not evidence that the
suite passed.

## How the tests work

- Test files live in `tests/` and end in `.tftest.hcl`.
- Every test file declares `mock_provider` blocks. Mocked providers never call
  Azure: no credentials are needed and **no real resources are created**.
  Resource attributes that Azure would compute (for example `id`) get generated
  fake values.
- Each `run` block plans (`command = plan`) or "applies" against the mocks
  (`command = apply`) with a set of input variables, then checks the result with
  `assert` blocks.
- Input validation is tested with `expect_failures`, which passes only when the
  listed variable validation or precondition fails.
- Data sources and nested modules that would need real lookups can be replaced
  with `override_data` / `override_module`.
- This module references a private network-IP module over SSH. In CI, a guarded
  preparation script replaces only that exact dependency reference in a
  disposable copy with a local synthetic module containing documentation-range
  IPs. The script runs guard tests before making the substitution. CI therefore
  needs no SSH key or private-module access. These tests cover this module's
  behavior with the fixture; they do not test the private dependency itself.

These are unit-style tests: they verify how the module turns inputs into
resource configuration. They do not prove that Azure accepts the configuration;
that still happens when a consuming workload runs `terraform plan`/`apply`.

## Writing a test

```hcl
mock_provider "azurerm" {}

variables {
  resource_group_name = "rg-test"
}

run "defaults" {
  command = plan

  assert {
    condition     = azurerm_example.this.name == "expected"
    error_message = "Name should default to 'expected'."
  }
}

run "rejects_invalid_input" {
  command = plan

  variables {
    some_setting = "not-allowed"
  }

  expect_failures = [var.some_setting]
}
```

Guidelines:

- Add or update a test whenever you change behaviour, defaults or validation.
- Use obviously fake values (`rg-test`, `00000000-0000-0000-0000-000000000000`,
  documentation IP ranges such as `192.0.2.0/24`). Never use real subscription
  IDs, tenant IDs, names or addresses — this repository is public.
- Prefer one behaviour per `run` block with a descriptive name.

## Running locally

Requires Terraform >= 1.7 or a compatible OpenTofu release. Tests use mock
providers and fake inputs, so no Azure credentials are needed.

To run without private SSH access, use a temporary copy. The preparation script
rewrites `main.tf`, so never run it in your working checkout:

```sh
tmpdir="$(mktemp -d)"
git archive HEAD | tar -x -C "$tmpdir"
cd "$tmpdir"
bash tests/prepare-ci.sh
terraform init -backend=false -input=false -test-directory=tests
terraform validate
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) FILTER_PATH='tests\key_vault.tftest.hcl' ;;
  *) FILTER_PATH='tests/key_vault.tftest.hcl' ;;
esac
terraform test -test-directory=tests "-filter=$FILTER_PATH"
```

For OpenTofu, replace `terraform` with `tofu` in the CLI commands. To run all
tests, omit the `-filter` option and its quoted argument. The test command should
report a nonzero passing-run count, e.g. `Success! 9 passed, 0 failed.`; a
success message with zero runs means no test was exercised. The filter variable
is quoted because Bash consumes unquoted backslashes on Windows.

On Windows, run the same steps in PowerShell, replacing `$engine` with
`terraform` or `tofu`. The filter path uses backslashes:

```powershell
$testCopy = Join-Path $env:TEMP ("terraform-module-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force $testCopy | Out-Null
git archive --format=tar --output "$testCopy.tar" HEAD
tar -xf "$testCopy.tar" -C $testCopy
Push-Location $testCopy
bash tests/prepare-ci.sh
terraform init -backend=false -input=false -test-directory=tests
terraform validate
terraform test -test-directory=tests '-filter=tests\key_vault.tftest.hcl'
Pop-Location
```

Replace `terraform` with `tofu` for OpenTofu. `git archive HEAD` copies the
committed snapshot only; commit changes you want to test first, or copy your
uncommitted changes into the temporary directory before running the tests. The
preparation script modifies only the temporary copy, not the checkout.

If you already have SSH access to the private module, you can instead initialize
the working checkout directly and run all tests:

```sh
terraform init -backend=false
terraform test            # all tests
terraform test -verbose   # include plan output
```

For OpenTofu, replace `terraform` with `tofu`. To run only `key_vault.tftest.hcl`,
use the shell-aware `FILTER_PATH` example above, or the quoted PowerShell example.

Running `init` directly against this module downloads its real private
dependency and therefore requires SSH access to GitHub. CI avoids that by
running `tests/prepare-ci.sh` in a disposable copy; that fixture tests this
module's logic, not the private dependency itself.
