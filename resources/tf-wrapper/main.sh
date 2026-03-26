#!/usr/bin/env bash
set -euo pipefail

TERRAFORM_BIN="${TERRAFORM_BIN:-terraform}"
DEFAULT_IMPERSONATE_SA="sa-tf-app-gcp-iaastraining-s@iaastraining-s-0dwp.iam.gserviceaccount.com"
IMPERSONATE_SA="${TF_WRAPPER_IMPERSONATE_SERVICE_ACCOUNT:-${DEFAULT_IMPERSONATE_SA}}"
SKIP_IMPERSONATION_WARMUP="${TF_WRAPPER_SKIP_IMPERSONATION_WARMUP:-}"
ADC_FILE="${HOME}/.config/gcloud/application_default_credentials.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENABLE_LABEL_INJECTION="${TF_WRAPPER_ENABLE_LABEL_INJECTION:-1}"
LABEL_KEY="${TF_WRAPPER_LABEL_KEY:-iaas-training-user}"
LABELS_FILE_BASENAME="${TF_WRAPPER_LABELS_FILE:-zz-tf-wrapper-labels.tf}"
LABELS_LOCAL_SYMBOL="${TF_WRAPPER_LABELS_LOCAL_SYMBOL:-local.tf_wrapper_labels}"
MODULE_SOURCE_CONTAINS="${TF_WRAPPER_MODULE_SOURCE_CONTAINS:-tf-module-gcp-}"
ENABLE_REMOTE_STATE="${TF_WRAPPER_ENABLE_REMOTE_STATE:-1}"
STATE_BUCKET="${TF_WRAPPER_GCS_STATE_BUCKET:-iaastraining-s-bkt-tf_app_gcp_tfstate}"
STATE_PREFIX_BASE="${TF_WRAPPER_GCS_STATE_PREFIX_BASE:-SANDBOX/users}"
BACKEND_FILE_BASENAME="${TF_WRAPPER_BACKEND_FILE:-zz-tf-wrapper-backend.tf}"
LAB_ID="${TF_WRAPPER_LAB_ID:-$(basename "$PWD")}"

adc_already_impersonated_for_target() {
  [[ -f "${ADC_FILE}" ]] || return 1
  grep -q '"service_account_impersonation_url"' "${ADC_FILE}" || return 1
  grep -q "${IMPERSONATE_SA}" "${ADC_FILE}" || return 1
}

sanitize_label_value() {
  local value="$1"
  value="$(echo -n "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(echo -n "${value}" | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+|-+$//g')"
  value="${value:0:63}"
  if [[ -z "${value}" ]]; then
    value="unknown"
  fi
  echo "${value}"
}

discover_user_email() {
  local account
  account="$(gcloud auth list --filter='status:ACTIVE' --format='value(account)' 2>/dev/null | head -n1 || true)"
  if [[ -n "${account}" && "${account}" != *".iam.gserviceaccount.com" ]]; then
    echo "${account}"
  fi
}

build_remote_state_prefix() {
  local user_email
  local user_label
  local lab_label

  user_email="$(discover_user_email || true)"
  if [[ -z "${user_email}" ]]; then
    user_email="unknown-user"
  fi

  user_label="$(sanitize_label_value "${user_email}")"
  lab_label="$(sanitize_label_value "${LAB_ID}")"
  echo "${STATE_PREFIX_BASE}/user/${user_label}/lab/${lab_label}"
}

should_patch_for_command() {
  local cmd="${1:-}"
  case "${cmd}" in
    plan|apply|destroy|refresh|import)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_backend_block() {
  local tf_file
  shopt -s nullglob
  for tf_file in "${PWD}"/*.tf; do
    if grep -Eq '^[[:space:]]*backend[[:space:]]+"[^"]+"' "${tf_file}"; then
      shopt -u nullglob
      return 0
    fi
  done
  shopt -u nullglob
  return 1
}

ensure_backend_file_if_needed() {
  local backend_file
  backend_file="${PWD}/${BACKEND_FILE_BASENAME}"

  if has_backend_block; then
    return 0
  fi

  cat > "${backend_file}" <<EOF
terraform {
  backend "gcs" {}
}
EOF
}

run_init_with_remote_state() {
  local state_prefix

  if [[ "${ENABLE_REMOTE_STATE}" == "0" || "${ENABLE_REMOTE_STATE}" == "false" ]]; then
    exec "${TERRAFORM_BIN}" "$@"
  fi

  for arg in "$@"; do
    if [[ "${arg}" == "-backend=false" ]]; then
      exec "${TERRAFORM_BIN}" "$@"
    fi
  done

  if [[ -z "${STATE_BUCKET}" ]]; then
    echo "[tf-wrapper] Variable manquante: TF_WRAPPER_GCS_STATE_BUCKET." >&2
    exit 5
  fi

  ensure_backend_file_if_needed
  state_prefix="$(build_remote_state_prefix)"

  exec "${TERRAFORM_BIN}" "$@" \
    -backend-config="bucket=${STATE_BUCKET}" \
    -backend-config="prefix=${state_prefix}"
}

inject_labels_if_needed() {
  local terraform_subcmd="${1:-}"
  local user_email
  local user_label
  local labels_file

  if [[ "${ENABLE_LABEL_INJECTION}" == "0" || "${ENABLE_LABEL_INJECTION}" == "false" ]]; then
    return 0
  fi

  if ! should_patch_for_command "${terraform_subcmd}"; then
    return 0
  fi

  user_email="$(discover_user_email || true)"
  if [[ -z "${user_email}" ]]; then
    return 0
  fi

  user_label="$(sanitize_label_value "${user_email}")"
  labels_file="${PWD}/${LABELS_FILE_BASENAME}"

  cat > "${labels_file}" <<EOF
locals {
  tf_wrapper_labels = {
    "${LABEL_KEY}" = "${user_label}"
  }
}
EOF

  python3 "${SCRIPT_DIR}/tf_wrapper_patch_modules.py" \
    --dir "${PWD}" \
    --exclude "${LABELS_FILE_BASENAME}" \
    --locals-symbol "${LABELS_LOCAL_SYMBOL}" \
    --module-source-contains "${MODULE_SOURCE_CONTAINS}"
}

check_impersonation() {
  if [[ -n "${SKIP_IMPERSONATION_WARMUP}" ]]; then
    return 0
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    echo "[tf-wrapper] gcloud introuvable, verification d'impersonation impossible." >&2
    exit 3
  fi

  if ! adc_already_impersonated_for_target; then
    echo "[tf-wrapper] ADC impersonate absent/invalide, ouverture du login navigateur..."
    gcloud auth application-default login \
      --impersonate-service-account="${IMPERSONATE_SA}"
  fi

  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "[tf-wrapper] ADC invalide apres login pour ${IMPERSONATE_SA}." >&2
    exit 4
  fi
}

main() {
  local terraform_subcmd="${1:-}"
  check_impersonation
  inject_labels_if_needed "${terraform_subcmd}"
  if [[ "${terraform_subcmd}" == "init" ]]; then
    run_init_with_remote_state "$@"
  fi
  exec "${TERRAFORM_BIN}" "$@"
}

main "$@"
