#!/usr/bin/env bash
set -euo pipefail

STATE_PREFIX_BASE="SANDBOX/users"
DEFAULT_IMPERSONATE_SA="sa-terraform-lab@iaastraining-s-0dwp.iam.gserviceaccount.com"
STATE_DIR="${HOME}/.tf-wrapper"
LABEL_KEY="iaas-training-user"
WRAPPER_VERSION="2026-03-31-audit-v1"
AUDIT_ENABLED="${TF_WRAPPER_AUDIT_ENABLED:-1}"
AUDIT_PROJECT_ID="${TF_WRAPPER_AUDIT_PROJECT_ID:-iaastraining-s-0dwp}"
AUDIT_TOPIC="${TF_WRAPPER_AUDIT_TOPIC:-terraform-lab-events}"
AUDIT_MAX_RESOURCES="${TF_WRAPPER_AUDIT_MAX_RESOURCES:-100}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

gcloud_config_dir() {
  local dir
  dir="$(gcloud info --format='value(config.paths.global_config_dir)' 2>/dev/null || true)"
  if [[ -n "${dir}" ]]; then
    echo "${dir}"
    return 0
  fi
  if [[ -n "${CLOUDSDK_CONFIG:-}" ]]; then
    echo "${CLOUDSDK_CONFIG}"
    return 0
  fi
  echo "${HOME}/.config/gcloud"
}

active_adc_file() {
  echo "$(gcloud_config_dir)/application_default_credentials.json"
}

terraform_bin() {
  echo "${TERRAFORM_BIN:-terraform}"
}

impersonate_sa() {
  echo "${TF_WRAPPER_IMPERSONATE_SERVICE_ACCOUNT:-${DEFAULT_IMPERSONATE_SA}}"
}

run_terraform() {
  local tf_bin
  tf_bin="$(terraform_bin)"
  exec "${tf_bin}" "$@"
}

run_terraform_no_exec() {
  local tf_bin
  tf_bin="$(terraform_bin)"
  "${tf_bin}" "$@"
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

adc_impersonation_configured_for_target() {
  local impersonate_sa="$1"
  local adc_file
  adc_file="$(active_adc_file)"
  [[ -f "${adc_file}" ]] || return 1
  grep -q '"service_account_impersonation_url"' "${adc_file}" || return 1
  grep -q "${impersonate_sa}" "${adc_file}" || return 1
}

adc_token_ok() {
  gcloud auth application-default print-access-token >/dev/null 2>&1
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

collect_state_resources_json() {
  local tf_bin
  local max_resources
  local state_json_file
  local parsed_json

  tf_bin="$(terraform_bin)"
  max_resources="${AUDIT_MAX_RESOURCES}"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "[]"
    return 0
  fi

  state_json_file="$(mktemp)"
  if ! "${tf_bin}" show -json >"${state_json_file}" 2>/dev/null; then
    rm -f "${state_json_file}"
    echo "[]"
    return 0
  fi

  if ! parsed_json="$(MAX_RESOURCES="${max_resources}" STATE_JSON_FILE="${state_json_file}" python3 - <<'PY'
import json
import os

max_resources = int(os.environ.get("MAX_RESOURCES", "100"))
state_json_file = os.environ.get("STATE_JSON_FILE", "")
if not state_json_file:
    print("[]")
    raise SystemExit(0)

try:
    with open(state_json_file, "r", encoding="utf-8") as f:
        raw = f.read().strip()
    if not raw:
        print("[]")
        raise SystemExit(0)
    data = json.loads(raw)
except Exception:
    print("[]")
    raise SystemExit(0)

root = data.get("values", {}).get("root_module", {})
items = []

def simplify_values(values):
    keys = ["name", "project", "region", "zone", "address", "machine_type", "service_account", "labels"]
    out = {}
    for key in keys:
        if key in values and values.get(key) is not None:
            out[key] = values.get(key)
    return out

def walk(module):
    for r in module.get("resources", []):
        values = r.get("values", {}) if isinstance(r.get("values", {}), dict) else {}
        items.append({
            "address": r.get("address"),
            "type": r.get("type"),
            "name": r.get("name"),
            "mode": r.get("mode"),
            "values": simplify_values(values),
        })
    for child in module.get("child_modules", []):
        walk(child)

if isinstance(root, dict):
    walk(root)

print(json.dumps(items[:max_resources], ensure_ascii=False))
PY
  )"; then
    rm -f "${state_json_file}"
    echo "[]"
    return 0
  fi

  rm -f "${state_json_file}"
  echo "${parsed_json}"
}

emit_audit_event() {
  local action="$1"
  local status="$2"
  local resources_json="$3"
  local lab_id="$4"
  local user_email="$5"
  local state_prefix="$6"
  local active_impersonate_sa="$7"
  local event_timestamp
  local event_id
  local resources_count
  local payload

  if [[ "${AUDIT_ENABLED}" == "0" || "${AUDIT_ENABLED}" == "false" ]]; then
    return 0
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    return 0
  fi

  event_timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  event_id="$(python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
)"
  resources_count="$(RESOURCES_JSON="${resources_json}" python3 - <<'PY'
import json
import os
raw = os.environ.get("RESOURCES_JSON", "[]")
try:
    data = json.loads(raw)
    print(len(data) if isinstance(data, list) else 0)
except Exception:
    print(0)
PY
)"

  payload="$(EVENT_ID="${event_id}" EVENT_TIMESTAMP="${event_timestamp}" LAB_ID="${lab_id}" USER_EMAIL="${user_email}" ACTION="${action}" STATUS="${status}" PROJECT_ID="${AUDIT_PROJECT_ID}" STATE_PREFIX="${state_prefix}" RESOURCES_COUNT="${resources_count}" RESOURCES_JSON="${resources_json}" WRAPPER_VERSION="${WRAPPER_VERSION}" python3 - <<'PY'
import json
import os

payload = {
    "event_id": os.environ["EVENT_ID"],
    "event_timestamp": os.environ["EVENT_TIMESTAMP"],
    "lab_name": os.environ["LAB_ID"],
    "user_email": os.environ.get("USER_EMAIL", ""),
    "action": os.environ["ACTION"],
    "status": os.environ["STATUS"],
    "project_id": os.environ["PROJECT_ID"],
    "state_prefix": os.environ.get("STATE_PREFIX", ""),
    "resources_count": int(os.environ.get("RESOURCES_COUNT", "0")),
    "resources_json": os.environ.get("RESOURCES_JSON", "[]"),
    "wrapper_version": os.environ.get("WRAPPER_VERSION", ""),
}
print(json.dumps(payload, ensure_ascii=False))
PY
)"

  gcloud pubsub topics publish "${AUDIT_TOPIC}" \
    --project="${AUDIT_PROJECT_ID}" \
    --message="${payload}" \
    --impersonate-service-account="${active_impersonate_sa}" \
    >/dev/null 2>&1 || true
}

run_terraform_with_audit() {
  local action="$1"
  shift
  local active_impersonate_sa="$1"
  shift

  local lab_id
  local user_email
  local state_prefix
  local resources_before="[]"
  local resources_after="[]"
  local status="error"
  local rc=1

  lab_id="$(basename "${PWD}")"
  user_email="$(discover_user_email || true)"
  state_prefix="$(build_remote_state_prefix "${lab_id}")"

  if [[ "${action}" == "destroy" ]]; then
    resources_before="$(collect_state_resources_json)"
  fi

  if run_terraform_no_exec "$@"; then
    rc=0
    status="success"
  fi

  if [[ "${action}" == "apply" && "${rc}" -eq 0 ]]; then
    resources_after="$(collect_state_resources_json)"
  fi

  if [[ "${action}" == "destroy" ]]; then
    emit_audit_event "${action}" "${status}" "${resources_before}" "${lab_id}" "${user_email}" "${state_prefix}" "${active_impersonate_sa}"
  else
    emit_audit_event "${action}" "${status}" "${resources_after}" "${lab_id}" "${user_email}" "${state_prefix}" "${active_impersonate_sa}"
  fi

  return "${rc}"
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
  local active_impersonate_sa
  local configured_cli_impersonation_sa
  local warm_file
  local adc_file

  active_impersonate_sa="$(impersonate_sa)"
  if [[ -z "${active_impersonate_sa}" ]]; then
    echo "[tf-wrapper] Service account d'impersonation manquant." >&2
    exit 2
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    echo "[tf-wrapper] gcloud introuvable, verification d'impersonation impossible." >&2
    exit 3
  fi

  # Prevent clashes between persistent gcloud CLI impersonation config
  # and our wrapper-managed ADC impersonation flow.
  configured_cli_impersonation_sa="$(gcloud config get-value auth/impersonate_service_account 2>/dev/null || true)"
  if [[ -n "${configured_cli_impersonation_sa}" && "${configured_cli_impersonation_sa}" != "(unset)" ]]; then
    gcloud config unset auth/impersonate_service_account --quiet >/dev/null 2>&1 || true
  fi

  warm_file="$(impersonation_state_file "${active_impersonate_sa}")"
  adc_file="$(active_adc_file)"

  # Fast path: already warmed for this SA and ADC still valid.
  if [[ -f "${warm_file}" ]] && adc_impersonation_configured_for_target "${active_impersonate_sa}" && adc_token_ok; then
    return 0
  fi

  if ! adc_impersonation_configured_for_target "${active_impersonate_sa}" || ! adc_token_ok; then
    echo "[tf-wrapper] ADC impersonate absent/invalide, ouverture du login navigateur..."
    gcloud auth application-default login \
      --impersonate-service-account="${active_impersonate_sa}"
  fi

  if ! adc_impersonation_configured_for_target "${active_impersonate_sa}" || ! adc_token_ok; then
    echo "[tf-wrapper] ADC invalide apres login pour ${active_impersonate_sa}." >&2
    exit 4
  fi

  # Ensure Terraform uses the same ADC file as gcloud in Cloud Shell.
  if [[ -f "${adc_file}" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="${adc_file}"
  fi

  touch "${warm_file}"
}

main() {
  local terraform_subcmd="${1:-}"
  local active_impersonate_sa
  active_impersonate_sa="$(impersonate_sa)"
  # Keep Terraform on explicit ADC credentials to avoid metadata fallback.
  unset GOOGLE_IMPERSONATE_SERVICE_ACCOUNT || true
  check_impersonation
  inject_labels_if_needed "${terraform_subcmd}"
  if [[ "${terraform_subcmd}" == "init" ]]; then
    run_init_with_remote_state "$@"
  fi
  if [[ "${terraform_subcmd}" == "apply" || "${terraform_subcmd}" == "destroy" ]]; then
    run_terraform_with_audit "${terraform_subcmd}" "${active_impersonate_sa}" "$@"
    exit $?
  fi
  run_terraform "$@"
}

main "$@"
