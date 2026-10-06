#!/usr/bin/env bash
set -euo pipefail

if [[ -z ${FA_REPO_NAME} ]]; then
  FA_REPO_NAME="${GITHUB_REPOSITORY##*/}"
fi

if [[ ${FA_REPO_NAME} == *[$'\n\r']* || ${FA_REPORT_PATH} == *[$'\n\r']* ]]; then
  echo "::error::repo_name and report_output_path must be a single line"
  exit 2
fi

REPORT_COPY=""
if [[ -n ${FA_REPORT_PATH} ]]; then
  WORKSPACE="$(realpath -m -- "${GITHUB_WORKSPACE}")"
  REPORT_COPY="$(realpath -m -- "${GITHUB_WORKSPACE}/${FA_REPORT_PATH}")"
  if [[ ${REPORT_COPY} != "${WORKSPACE}"/* || -d ${REPORT_COPY} ]]; then
    echo "::error::report_output_path must be a file path inside the workspace"
    exit 2
  fi
fi

echo "::notice::Running CI Gate for repository: ${FA_REPO_NAME}"

STRICT_FLAG="--lax"
if [[ ${FA_STRICT} == "true" ]]; then
  STRICT_FLAG="--strict"
fi

REPORT_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/ci-gate.XXXXXX")"
REPORT_FILE="${REPORT_DIR}/report.json"

DOCKER_ARGS=(
  --rm
  -v "${GITHUB_WORKSPACE}:/workspace:ro"
  -v "${REPORT_DIR}:/ci-gate"
  -w /workspace
  -e GITHUB_ACTIONS
  -e GITHUB_ACTOR
  -e GITHUB_REF_NAME
  -e GITHUB_REPOSITORY
  -e GITHUB_SHA
)
FORCES_ARGS=(forces --token "${FA_TOKEN}" --repo-name "${FA_REPO_NAME}" "${STRICT_FLAG}" --output /ci-gate/report.json)

exit_code=0
docker run "${DOCKER_ARGS[@]}" ghcr.io/fluidattacks/forces:latest "${FORCES_ARGS[@]}" || exit_code=$?

if [[ ${exit_code} -ne 0 && ${exit_code} -ne 66 ]]; then
  echo "::error::CI Gate failed with exit code ${exit_code}"
  exit "${exit_code}"
fi

if [[ -L ${REPORT_FILE} || (-e ${REPORT_FILE} && ! -f ${REPORT_FILE}) ]]; then
  echo "::error::Could not read the CI Gate report"
  exit 1
fi

found="true"
if [[ ${exit_code} -eq 0 ]]; then
  compliance="$(grep -Eo '"overall_compliance"[[:space:]]*:[[:space:]]*(true|false)' "${REPORT_FILE}" 2> /dev/null | grep -Eo '(true|false)$' || true)"
  if [[ ${compliance} == "true" ]]; then
    found="false"
  elif [[ ${compliance} != "false" ]]; then
    echo "::error::Could not read the CI Gate report"
    exit 1
  fi
fi

if [[ -n ${REPORT_COPY} ]]; then
  if ! cp -- "${REPORT_FILE}" "${REPORT_COPY}"; then
    echo "::error::Could not save the report to ${FA_REPORT_PATH}"
    exit 1
  fi
  echo "report_output_path=${FA_REPORT_PATH}" >> "${GITHUB_OUTPUT}"
fi

echo "vulnerabilities_found=${found}" >> "${GITHUB_OUTPUT}"

exit "${exit_code}"
