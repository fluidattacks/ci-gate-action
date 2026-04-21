#!/usr/bin/env bash
set -euo pipefail

STRICT_FLAG="--lax"
if [[ "${FA_STRICT}" == "true" ]]; then
  STRICT_FLAG="--strict"
fi

DOCKER_ARGS=(--rm)
FORCES_ARGS=(forces --token "${FA_TOKEN}" --repo-name "${FA_REPO_NAME}" "${STRICT_FLAG}")

if [[ -n "${FA_REPORT_PATH}" ]]; then
  DOCKER_ARGS+=(-v "${GITHUB_WORKSPACE}:/workspace")
  FORCES_ARGS+=(--output "/workspace/${FA_REPORT_PATH}")
fi

exit_code=0
docker run "${DOCKER_ARGS[@]}" fluidattacks/forces:latest "${FORCES_ARGS[@]}" || exit_code=$?

if [[ ${exit_code} -eq 0 ]]; then
  echo "vulnerabilities_found=false" >> "${GITHUB_OUTPUT}"
elif [[ ${exit_code} -eq 1 ]]; then
  echo "vulnerabilities_found=true" >> "${GITHUB_OUTPUT}"
else
  echo "::error::CI Agent exited with unexpected code ${exit_code}"
  exit "${exit_code}"
fi

if [[ -n "${FA_REPORT_PATH}" ]]; then
  echo "report_output_path=${FA_REPORT_PATH}" >> "${GITHUB_OUTPUT}"
fi

exit "${exit_code}"
