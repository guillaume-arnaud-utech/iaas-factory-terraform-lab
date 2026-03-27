#!/usr/bin/env bash
set -euo pipefail

STATE_PREFIX_BASE="SANDBOX/users"
DEFAULT_IMPERSONATE_SA="sa-tf-app-gcp-iaastraining-s@iaastraining-s-0dwp.iam.gserviceaccount.com"
STATE_DIR="${HOME}/.tf-wrapper"
LABEL_KEY="iaas-training-user"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

terraform_bin() {
  echo "${TERRAFORM_BIN:-terraform}"
}

run_terraform() {
  local tf_bin
  tf_bin="$(terraform_bin)"
  exec "${tf_bin}" "$@"
}

has_arg() {
  local needle="$1"
  shift
  local arg
  for arg in "$@"; do
    if [[ "${arg}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

sanitize_sa_for_filename() {
  local value="$1"
  value="$(echo -n "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(echo -n "${value}" | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
  if [[ -z "${value}" ]]; then
    value="unknown-sa"
  fi
  echo "${value}"
}

impersonation_state_file() {
  local impersonate_sa="$1"
  local sa_file
  sa_file="$(sanitize_sa_for_filename "${impersonate_sa}")"
  mkdir -p "${STATE_DIR}"
  echo "${STATE_DIR}/adc-impersonation-${sa_file}.ok"
}

impersonation_token_ok() {
  local impersonate_sa="$1"
  gcloud auth application-default print-access-token \
    --impersonate-service-account="${impersonate_sa}" \
    >/dev/null 2>&1
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

sanitize_instance_base_name() {
  local value="$1"
  value="$(echo -n "${value}" | tr '[:upper:]' '[:lower:]')"
  value="$(echo -n "${value}" | sed -E 's/[^a-z0-9]+//g')"
  value="${value:0:9}"
  if [[ -z "${value}" ]]; then
    value="vmuser"
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
  local lab_id="$1"
  local user_email
  local user_label
  local lab_label

  user_email="$(discover_user_email || true)"
  if [[ -z "${user_email}" ]]; then
    user_email="unknown-user"
  fi

  user_label="$(sanitize_label_value "${user_email}")"
  lab_label="$(sanitize_label_value "${lab_id}")"
  echo "${STATE_PREFIX_BASE}/${user_label}/${lab_label}"
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
  local backend_file_basename="zz-tf-wrapper-backend.tf"
  local backend_file
  backend_file="${PWD}/${backend_file_basename}"

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
  local state_bucket="iaastraining-s-bkt-tf_app_gcp_tfstate"
  local lab_id="$(basename "${PWD}")"
  local state_prefix

  if has_arg "-backend=false" "$@"; then
    run_terraform "$@"
  fi

  ensure_backend_file_if_needed
  state_prefix="$(build_remote_state_prefix "${lab_id}")"

  run_terraform "$@" \
    -backend-config="bucket=${state_bucket}" \
    -backend-config="prefix=${state_prefix}"
}

inject_labels_if_needed() {
  local terraform_subcmd="${1:-}"
  local labels_file_basename="zz-tf-wrapper-labels.tf"
  local user_email
  local user_label
  local instance_base_name
  local labels_file

  if ! should_patch_for_command "${terraform_subcmd}"; then
    return 0
  fi

  user_email="$(discover_user_email || true)"
  if [[ -z "${user_email}" ]]; then
    return 0
  fi

  user_label="$(sanitize_label_value "${user_email}")"
  instance_base_name="$(sanitize_instance_base_name "${user_email%%@*}")"
  labels_file="${PWD}/${labels_file_basename}"

  cat > "${labels_file}" <<EOF
locals {
  tf_wrapper_labels = {
    "${LABEL_KEY}" = "${user_label}"
  }
}
EOF

  python3 "${SCRIPT_DIR}/tf_wrapper_patch_modules.py" \
    --dir "${PWD}" \
    --exclude "${labels_file_basename}" \
    --locals-symbol "local.tf_wrapper_labels" \
    --module-source-contains "tf-module-gcp-" \
    --set-instance-base-name "1" \
    --instance-base-name "${instance_base_name}" \
    --instance-base-name-module-source-contains "tf-module-gcp-ceins"
}

check_impersonation() {
  local impersonate_sa="${DEFAULT_IMPERSONATE_SA}"
  local warm_file

  if ! command -v gcloud >/dev/null 2>&1; then
    echo "[tf-wrapper] gcloud introuvable, verification d'impersonation impossible." >&2
    exit 3
  fi

  warm_file="$(impersonation_state_file "${impersonate_sa}")"

  # Fast path: already warmed for this SA and impersonation still valid.
  if [[ -f "${warm_file}" ]] && impersonation_token_ok "${impersonate_sa}"; then
    return 0
  fi

  if ! impersonation_token_ok "${impersonate_sa}"; then
    echo "[tf-wrapper] ADC impersonate absent/invalide, ouverture du login navigateur..."
    gcloud auth application-default login \
      --impersonate-service-account="${impersonate_sa}"
  fi

  if ! impersonation_token_ok "${impersonate_sa}"; then
    echo "[tf-wrapper] ADC invalide apres login pour ${impersonate_sa}." >&2
    exit 4
  fi

  touch "${warm_file}"
}

main() {
  local terraform_subcmd="${1:-}"

  check_impersonation
  inject_labels_if_needed "${terraform_subcmd}"
  if [[ "${terraform_subcmd}" == "init" ]]; then
    run_init_with_remote_state "$@"
  fi
  run_terraform "$@"
}

main "$@"
