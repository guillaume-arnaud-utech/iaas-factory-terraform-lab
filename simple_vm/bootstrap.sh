#!/usr/bin/env bash
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GLOBAL_BOOTSTRAP="${LAB_DIR}/../resources/bootstrap_global.sh"

if [[ ! -f "${GLOBAL_BOOTSTRAP}" ]]; then
  echo "Erreur: bootstrap global introuvable: ${GLOBAL_BOOTSTRAP}" >&2
  exit 1
fi

bash "${GLOBAL_BOOTSTRAP}" "$@"
