# Fluid Attacks CI Gate

CI gate action for your GitHub repositories. Connects to the Fluid Attacks platform and checks whether your repository has open vulnerabilities reported by Fluid Attacks. Requires a Fluid Attacks account and a CI Gate token.

## Quick Start

### 1. Store your CI Gate token as a secret

In your repository, go to **Settings → Secrets and variables → Actions** and create a new secret named `FA_API_TOKEN` with your CI Gate token.

To generate or retrieve the token, go to **Organization → Groups → GroupName → DevSecOps** in the Fluid Attacks platform and click **Manage token**. The token is valid for 180 days.

### 2. Create the GitHub Actions workflow

Add the file `.github/workflows/ci-gate.yml` to your repository:

```yaml
name: Fluid Attacks CI Gate

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  ci-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: fluidattacks/ci-gate-action@<version>
        id: gate
        with:
          api_token: ${{ secrets.FA_API_TOKEN }}
          repo_name: my-repo
```

Replace `<version>` with the latest release tag and `my-repo` with the repository nickname configured in the Fluid Attacks platform. Push the file and the check will run automatically.

## Prerequisites

- A Fluid Attacks account with an active group and a repository configured on the platform.
- A **CI Gate token** generated from the **DevSecOps** section of the platform.
- GitHub Actions enabled on the repository.
- A **Linux runner** (`ubuntu-latest` or equivalent) — the action requires Docker, which is only available on Linux-hosted runners.

## How it works

The action runs the Fluid Attacks CI Gate (`fluidattacks/forces:latest`) as a Docker container. The gate authenticates with the Fluid Attacks platform using the CI Gate token, retrieves the vulnerability findings already reported for the specified repository, and evaluates them against your group's security policies.

In lax mode (default), the action always exits successfully and sets `vulnerabilities_found` based on the result. In strict mode, the action fails the job if open or untreated vulnerabilities that break policy are found.

## Action inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `api_token` | Yes | — | CI Gate token for authenticating with the Fluid Attacks platform. Use a secret: `${{ secrets.FA_API_TOKEN }}`. |
| `repo_name` | No | GitHub repo name | Repository nickname as configured in the Fluid Attacks platform. When not set, defaults to the GitHub repository name (`GITHUB_REPOSITORY` minus the owner prefix). |
| `strict` | No | `false` | Set to `true` to enable strict mode. The job fails if open or untreated vulnerabilities that break policy are found. |
| `report_output_path` | No | — | Path relative to the workspace root where the JSON report will be saved. If not set, no report file is written. |

## Action outputs

| Output | Description |
|---|---|
| `vulnerabilities_found` | `true` if policy-breaking vulnerabilities were found, `false` otherwise. |
| `report_output_path` | Path to the JSON report file. Only set when the `report_output_path` input is configured. |

You can use these outputs in subsequent workflow steps:

```yaml
- name: Print result
  if: steps.gate.outputs.vulnerabilities_found == 'true'
  run: echo "Open vulnerabilities found. Review them on the Fluid Attacks platform."
```

## Common scenarios

### Strict mode: block merges with open vulnerabilities

Set `strict: true` to make the job fail when policy-breaking vulnerabilities are found. Combined with branch protection rules, this prevents vulnerable code from being merged:

```yaml
- uses: fluidattacks/ci-gate-action@<version>
  with:
    api_token: ${{ secrets.FA_API_TOKEN }}
    repo_name: my-repo
    strict: true
```

Then, in your repository settings, enable **Require status checks to pass before merging** and select the CI Gate check.

### Save the vulnerability report as JSON

Use `report_output_path` to write the full report to a file, then upload it as a workflow artifact:

```yaml
- uses: fluidattacks/ci-gate-action@<version>
  id: gate
  with:
    api_token: ${{ secrets.FA_API_TOKEN }}
    repo_name: my-repo
    report_output_path: fa-report.json

- name: Upload report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: fluid-attacks-report
    path: ${{ steps.gate.outputs.report_output_path }}
```

### Lax mode with conditional failure

Run in lax mode but fail the job manually based on the output:

```yaml
- uses: fluidattacks/ci-gate-action@<version>
  id: gate
  with:
    api_token: ${{ secrets.FA_API_TOKEN }}
    repo_name: my-repo

- name: Fail if vulnerabilities found
  if: steps.gate.outputs.vulnerabilities_found == 'true'
  run: exit 1
```

## Troubleshooting

### The action fails with an authentication error

Verify that your CI Gate token is correct and has not expired. Tokens are valid for 180 days. To renew it, go to **Organization → Groups → GroupName → DevSecOps** in the platform and click **Manage token**. Update the `FA_API_TOKEN` secret in your repository with the new token.

### You see the error "Remote check failed"

Ensure that `repo_name` matches the nickname registered in the Fluid Attacks platform exactly. When `repo_name` is not set, the action derives it from the GitHub repository name, which may differ from the nickname on the platform. Set `repo_name` explicitly to resolve the mismatch.

### The action reports no vulnerabilities but I expect some

Confirm that the `repo_name` input matches the repository nickname configured in the Fluid Attacks platform exactly. A mismatch causes the action to query the wrong repository and return no findings.

### The pipeline fails unexpectedly

If `strict: true` is set, the job fails whenever policy-breaking vulnerabilities are found. This is intentional. Set `strict: false` if you want the check to report results without failing the pipeline.

### The action fails on a non-Linux runner

The action requires Docker. Docker is only available on Linux-hosted runners. Make sure your workflow uses `runs-on: ubuntu-latest` or another Linux runner.

## More information

- [CI Gate documentation](https://docs.fluidattacks.com/quick-start/verify-fixes/ci-gate-installation)
- [Fluid Attacks platform](https://app.fluidattacks.com)
- [Fluid Attacks documentation](https://docs.fluidattacks.com)
