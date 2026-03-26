#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER_PATH="${REPO_DIR}/resources/tf-wrapper/terraform"

SECRET_PROJECT="${LAB_BOOTSTRAP_SECRET_PROJECT:-iaastraining-s-0dwp}"
SECRET_NAME="${LAB_BOOTSTRAP_SECRET_NAME:-github-terraform-lab}"
SSH_KEY_PATH="${LAB_BOOTSTRAP_SSH_KEY_PATH:-${HOME}/.ssh/github-terraform-lab}"
GITHUB_HOST_ALIAS="${LAB_BOOTSTRAP_GITHUB_HOST_ALIAS:-github.com}"
TERRAFORM_VERSION="${LAB_BOOTSTRAP_TERRAFORM_VERSION:-1.13.2}"
TERRAFORM_BIN_DIR="${LAB_BOOTSTRAP_TERRAFORM_BIN_DIR:-${HOME}/.local/bin}"
TERRAFORM_VERSIONED_BIN="${TERRAFORM_BIN_DIR}/terraform-${TERRAFORM_VERSION}"
TF_STATE_BUCKET="${LAB_BOOTSTRAP_TF_STATE_BUCKET:-}"
TF_STATE_PREFIX_BASE="${LAB_BOOTSTRAP_TF_STATE_PREFIX_BASE:-terraform-labs}"

ensure_ssh_key() {
  mkdir -p "${HOME}/.ssh"

  if [[ -s "${SSH_KEY_PATH}" ]]; then
    echo "[bootstrap] Cle SSH deja presente: ${SSH_KEY_PATH}"
    return 0
  fi

  if ! command -v gcloud >/dev/null 2>&1; then
    echo "[bootstrap] gcloud introuvable, impossible de recuperer la cle SSH." >&2
    return 1
  fi

  echo "[bootstrap] Recuperation de la cle SSH depuis Secret Manager..."
  gcloud secrets versions access latest \
    --secret="${SECRET_NAME}" \
    --project="${SECRET_PROJECT}" \
    > "${SSH_KEY_PATH}"

  chmod 600 "${SSH_KEY_PATH}"
}

ensure_ssh_config() {
  local marker="# iaas-factory-terraform-lab"
  local config_file="${HOME}/.ssh/config"

  touch "${config_file}"
  chmod 600 "${config_file}"

  if grep -qF "${marker}" "${config_file}"; then
    echo "[bootstrap] Configuration SSH deja en place."
    return 0
  fi

  cat >> "${config_file}" <<EOF
${marker}
Host ${GITHUB_HOST_ALIAS}
  IdentityFile ${SSH_KEY_PATH}
  StrictHostKeyChecking no
EOF
}

ensure_git_https_rewrite() {
  git config --global url."git@github.com:".insteadOf "https://github.com/"
}

ensure_shell_path_defaults() {
  local marker="# iaas-factory-terraform-lab-path"
  local path_line='export PATH="$HOME/.local/bin:$HOME/bin:$PATH"'
  local tf_bin_line="export TF_WRAPPER_REAL_TERRAFORM_BIN=\"\${HOME}/.local/bin/terraform-${TERRAFORM_VERSION}\""
  local state_bucket_line=""
  local state_prefix_line="export TF_WRAPPER_GCS_STATE_PREFIX_BASE=\"${TF_STATE_PREFIX_BASE}\""
  local enable_remote_state_line="export TF_WRAPPER_ENABLE_REMOTE_STATE=\"1\""
  local rc_file

  if [[ -n "${TF_STATE_BUCKET}" ]]; then
    state_bucket_line="export TF_WRAPPER_GCS_STATE_BUCKET=\"${TF_STATE_BUCKET}\""
  fi

  for rc_file in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    touch "${rc_file}"
    if ! grep -qF "${marker}" "${rc_file}"; then
      cat >> "${rc_file}" <<EOF

${marker}
${path_line}
${tf_bin_line}
${enable_remote_state_line}
${state_prefix_line}
EOF
      if [[ -n "${state_bucket_line}" ]]; then
        echo "${state_bucket_line}" >> "${rc_file}"
      fi
      continue
    fi

    if ! grep -qF "${path_line}" "${rc_file}"; then
      echo "${path_line}" >> "${rc_file}"
    fi
    if ! grep -qF "${tf_bin_line}" "${rc_file}"; then
      echo "${tf_bin_line}" >> "${rc_file}"
    fi
    if ! grep -qF "${enable_remote_state_line}" "${rc_file}"; then
      echo "${enable_remote_state_line}" >> "${rc_file}"
    fi
    if ! grep -qF "${state_prefix_line}" "${rc_file}"; then
      echo "${state_prefix_line}" >> "${rc_file}"
    fi
    if [[ -n "${state_bucket_line}" ]] && ! grep -qF "${state_bucket_line}" "${rc_file}"; then
      echo "${state_bucket_line}" >> "${rc_file}"
    fi
  done
}

ensure_terraform_version() {
  mkdir -p "${TERRAFORM_BIN_DIR}"

  if [[ -x "${TERRAFORM_VERSIONED_BIN}" ]]; then
    echo "[bootstrap] Terraform ${TERRAFORM_VERSION} deja present: ${TERRAFORM_VERSIONED_BIN}"
    return 0
  fi

  local archive
  local tmp_dir
  archive="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
  tmp_dir="$(mktemp -d)"

  echo "[bootstrap] Installation Terraform ${TERRAFORM_VERSION}..."
  curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${archive}" -o "${tmp_dir}/${archive}"
  unzip -q "${tmp_dir}/${archive}" -d "${tmp_dir}"
  mv "${tmp_dir}/terraform" "${TERRAFORM_VERSIONED_BIN}"
  chmod 755 "${TERRAFORM_VERSIONED_BIN}"
  rm -rf "${tmp_dir}"
}

ensure_terraform_wrapper() {
  local user_bin="${HOME}/bin"
  local local_bin="${HOME}/.local/bin"
  mkdir -p "${user_bin}" "${local_bin}"

  if [[ ! -x "${WRAPPER_PATH}" ]]; then
    echo "[bootstrap] Wrapper Terraform introuvable: ${WRAPPER_PATH}" >&2
    return 1
  fi

  ln -sfn "${WRAPPER_PATH}" "${local_bin}/terraform"
  ln -sfn "${WRAPPER_PATH}" "${user_bin}/terraform"
  echo "[bootstrap] Wrapper Terraform installe: ${local_bin}/terraform"
}

main() {
  ensure_ssh_key
  ensure_ssh_config
  ensure_git_https_rewrite
  ensure_shell_path_defaults
  ensure_terraform_version
  ensure_terraform_wrapper
  export PATH="${HOME}/.local/bin:${HOME}/bin:${PATH}"
  export TF_WRAPPER_REAL_TERRAFORM_BIN="${TERRAFORM_VERSIONED_BIN}"
  export TF_WRAPPER_ENABLE_REMOTE_STATE="1"
  export TF_WRAPPER_GCS_STATE_PREFIX_BASE="${TF_STATE_PREFIX_BASE}"
  if [[ -n "${TF_STATE_BUCKET}" ]]; then
    export TF_WRAPPER_GCS_STATE_BUCKET="${TF_STATE_BUCKET}"
  fi
  echo "[bootstrap] Environnement pret."
}

main "$@"
