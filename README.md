# Fluid Attacks CI Gate

CI gate action for your GitHub repositories. Connects to the Fluid Attacks platform and checks whether your repository has open vulnerabilities reported by Fluid Attacks. Requires a Fluid Attacks account. Authenticate with OpenID Connect (no secret to store) or with a CI Gate token.

## Quick Start

### 1. Choose how to authenticate

The action needs the `group` input with both ways of authenticating.

- **OpenID Connect (recommended).** No secret to store. In Fluid Attacks, add a trust for issuer `https://token.actions.githubusercontent.com` with the bound claim `repository` = `my-org/my-repo` and enable it for the group. See the [OIDC federation guide](https://docs.fluidattacks.com/find-fix/use-cli/authentication/oidc-federation).
- **CI Gate token.** In your repository, go to **Settings → Secrets and variables → Actions** and create a new secret named `FA_API_TOKEN` with your CI Gate token. To generate or retrieve the token, go to **Organization → Groups → GroupName → DevSecOps** in the Fluid Attacks platform and click **Manage token**. The token is valid for 180 days.

### 2. Create the GitHub Actions workflow

Add the file `.github/workflows/ci-gate.yml` to your repository:

```yaml
name: Fluid Attacks CI Gate

on:
  pull_request_target:
    types: [opened, synchronize, reopened]

jobs:
  ci-gate:
    runs-on: ubuntu-latest
    permissions:
      id-token: write # only for OpenID Connect
      contents: read
    steps:
      - uses: fluidattacks/ci-gate-action@<version>
        id: gate
        with:
          group: my-group
          repo_name: my-repo
```

Replace `<version>` with the latest release tag, `my-group` with your Fluid Attacks group, and `my-repo` with the repository nickname configured in the Fluid Attacks platform. To use a token instead of OpenID Connect, add `api_token: ${{ secrets.FA_API_TOKEN }}` and drop the `id-token` permission. Push the file and the check will run automatically.

> **Why `pull_request_target` instead of `pull_request`?**
> GitHub withholds secrets from workflows triggered by `pull_request` when the PR comes from a fork,
> so the action would fail to authenticate with a token. `pull_request_target` runs in the context of the base branch
> and always has access to secrets. This is safe here because the action never checks out or executes
> any code from the PR — it only calls the Fluid Attacks API.

## Prerequisites

- A Fluid Attacks account with an active group and a repository configured on the platform.
- Credentials: a trust for your repository (OpenID Connect), or a **CI Gate token** generated from the **DevSecOps** section of the platform.
- GitHub Actions enabled on the repository.
- A **Linux runner** (`ubuntu-latest` or equivalent) — the action requires Docker, which is only available on Linux-hosted runners.
- The step runs directly on the runner, not inside a job container (`jobs.<job_id>.container`), because the action mounts the workspace into its own container.

## Authentication

The gate has nothing to check without credentials, so unlike the scanner actions it never runs unauthenticated: the job fails if it has none.

### OpenID Connect (recommended)

No secret to store. Set the `group` input and grant the job `id-token: write`:

```yaml
permissions:
  id-token: write
  contents: read
jobs:
  ci-gate:
    runs-on: ubuntu-latest
    steps:
      - uses: fluidattacks/ci-gate-action@<version>
        with:
          group: my-group
```

In Fluid Attacks, add a trust for issuer `https://token.actions.githubusercontent.com` with the bound claim `repository` = `my-org/my-repo` and enable it for the group. See the [OIDC federation guide](https://docs.fluidattacks.com/find-fix/use-cli/authentication/oidc-federation).

### CI Gate token

```yaml
- uses: fluidattacks/ci-gate-action@<version>
  with:
    group: my-group
    api_token: ${{ secrets.FA_API_TOKEN }}
```

The token takes precedence over OpenID Connect. The action passes it to the container as an environment variable, never in the command line.

## How it works

The action runs the Fluid Attacks CI Gate (`ghcr.io/fluidattacks/forces:latest`) as a Docker container. The gate authenticates with the Fluid Attacks platform, retrieves the vulnerability findings already reported for the specified repository, and evaluates them against your group's security policies.

In lax mode (default), the job passes even when vulnerabilities break policy, and `vulnerabilities_found` tells you whether they did. In strict mode, the job fails with exit code 66 when they do. In both modes, the job fails if the gate itself cannot finish, for example because the credentials are invalid.

The container runs in the job workspace, mounted read-only. If the workflow checks out the repository before this step, the gate reads the commit, branch and origin from Git. Otherwise, it takes the commit and branch from GitHub (`GITHUB_SHA` and `GITHUB_REF_NAME`). The gate needs no Git credentials, so set `persist-credentials: false` on `actions/checkout`. With `pull_request_target`, keep the checkout on its default ref, the base branch, and do not check out the pull request's code.

## Action inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `group` | Yes | — | Fluid Attacks group of the repository. Required with both ways of authenticating. |
| `api_token` | No | — | CI Gate token, used when OpenID Connect is not an option. Use a secret: `${{ secrets.FA_API_TOKEN }}`. Takes precedence over OpenID Connect. When omitted, the action authenticates with OpenID Connect. See [Authentication](#authentication). |
| `repo_name` | No | GitHub repo name | Repository nickname as configured in the Fluid Attacks platform. When not set, defaults to the GitHub repository name (`GITHUB_REPOSITORY` minus the owner prefix). |
| `strict` | No | `false` | Set to `true` to enable strict mode. The job fails if open or untreated vulnerabilities that break policy are found. |
| `report_output_path` | No | — | Path relative to the workspace root where the JSON report will be saved. It must stay inside the workspace. If not set, the report is not saved in the workspace. |

## Action outputs

| Output | Description |
|---|---|
| `vulnerabilities_found` | `true` if policy-breaking vulnerabilities were found, in lax or strict mode, `false` otherwise. Not set when the gate itself fails. |
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
    group: my-group
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
    group: my-group
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
    group: my-group
    repo_name: my-repo

- name: Fail if vulnerabilities found
  if: steps.gate.outputs.vulnerabilities_found == 'true'
  run: exit 1
```

## Troubleshooting

### The action fails with "CI Gate needs credentials"

The job has neither `api_token` nor OpenID Connect credentials. Grant the job `permissions: id-token: write`, or provide `api_token`. Pull requests from forks get neither the permission nor secrets.

### The action fails with an authentication error

With a token, verify that it is correct, has not expired, and belongs to the group in the `group` input. Tokens are valid for 180 days. To renew it, go to **Organization → Groups → GroupName → DevSecOps** in the platform and click **Manage token**. Update the `FA_API_TOKEN` secret in your repository with the new token.

With OpenID Connect, verify that the group has a trust for your repository. See [OpenID Connect](#openid-connect-recommended).

### The job fails with "Invalid 'group' value"

The `group` input must be the name of your Fluid Attacks group: letters, digits, dots, underscores and hyphens, starting with a letter or digit.

### You see the error "Remote check failed"

Ensure that `repo_name` matches the nickname registered in the Fluid Attacks platform exactly. When `repo_name` is not set, the action derives it from the GitHub repository name, which may differ from the nickname on the platform. Set `repo_name` explicitly to resolve the mismatch.

### The action reports no vulnerabilities but I expect some

Confirm that the `repo_name` input matches the repository nickname configured in the Fluid Attacks platform exactly. A mismatch causes the action to query the wrong repository and return no findings.

### The pipeline fails unexpectedly

If `strict: true` is set, the job fails with exit code 66 whenever policy-breaking vulnerabilities are found. This is intentional. Set `strict: false` if you want the check to report results without failing the pipeline.

Any other non-zero exit code means the check did not finish, and the log shows the reason as an error. `CI Gate failed with exit code` followed by the code comes from the gate: check the credentials, the `group` and `repo_name` inputs and the network access to the Fluid Attacks platform. The errors `must be a single line` and `must be a file path inside the workspace` point to the `repo_name` or `report_output_path` inputs.

### The action fails on a non-Linux runner

The action requires Docker. Docker is only available on Linux-hosted runners. Make sure your workflow uses `runs-on: ubuntu-latest` or another Linux runner.

## More information

- [CI Gate documentation](https://docs.fluidattacks.com/quick-start/verify-fixes/ci-gate-installation)
- [Fluid Attacks platform](https://app.fluidattacks.com)
- [Fluid Attacks documentation](https://docs.fluidattacks.com)
