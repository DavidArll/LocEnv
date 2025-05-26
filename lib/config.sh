#!/usr/bin/env bash

# === Paths y constantes globales ===
export GLOBAL_CONFIG="${HOME}/.ddev/global_config.yaml"
export PROJECTS_JSON="${HOME}/.ddev/acquia-projects.json"
export PROJECTS_DIR="${HOME}/Sites/ddev"
export TMP_DIR=".ddev/tmp"
export DRUSH_TIMEOUT=200
export BACKUP_RETRIES=3
export DEFAULT_BRANCH="main"

# === Variables de entorno extraídas del global_config.yaml ===
load_acquia_credentials() {
  ACQUIA_API_KEY=$( { yq e '.web_environment[]' "$GLOBAL_CONFIG" | grep '^ACQUIA_API_KEY=' | cut -d '=' -f2-; } || true )
  ACQUIA_API_SECRET=$( { yq e '.web_environment[]' "$GLOBAL_CONFIG" | grep '^ACQUIA_API_SECRET=' | cut -d '=' -f2-; } || true )
  ACQUIA_PROJECT_ID=$( { yq e '.web_environment[]' "$GLOBAL_CONFIG" | grep '^ACQUIA_ENVIRONMENT_ID=' | cut -d '=' -f2-; } || true )

  if [[ -z "$ACQUIA_API_KEY" || -z "$ACQUIA_API_SECRET" ]]; then
    log_error "❌ Faltan credenciales en $GLOBAL_CONFIG"
    exit 1
  fi

  export ACQUIA_API_KEY ACQUIA_API_SECRET ACQUIA_PROJECT_ID
}

load_acquia_credentials

get_auth_token() {
  start_spinner "Solicitando token..."
  TOKEN=$(curl -fsS -X POST "https://accounts.acquia.com/api/auth/oauth/token" \
    -d "client_id=$ACQUIA_API_KEY" \
    -d "client_secret=$ACQUIA_API_SECRET" \
    -d "grant_type=client_credentials" | jq -r '.access_token')
  stop_spinner $?
  if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    log_error "❌ Error al obtener token de autenticación."
    exit 1
  fi

  export TOKEN
}

