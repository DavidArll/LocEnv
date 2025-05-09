#!/usr/bin/env bash

## Description: Fetch all Acquia environments and generate .ddev/acquia-projects.json
## Usage: acquia-sync-envs
## Example: ddev acquia-sync-envs
## CanRunGlobally: true

set -e

# 📌 Archivo de configuración global de DDEV
GLOBAL_CONFIG="$HOME/.ddev/global_config.yaml"
PROJECTS_JSON="$HOME/.ddev/acquia-projects.json"
PROJECTS_DIR="$HOME/Sites/ddev"

# 📌 Verificar si el archivo de configuración global existe
if [[ ! -f "$GLOBAL_CONFIG" ]]; then
    echo "❌ Error: global_config.yaml not found in .ddev directory."
    exit 1
fi

# 📌 Extraer credenciales de Acquia
ACQUIA_API_KEY=$(grep "ACQUIA_API_KEY=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_KEY=\(.*\)$/\1/')
ACQUIA_API_SECRET=$(grep "ACQUIA_API_SECRET=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_SECRET=\(.*\)$/\1/')
PROJECT_ID=$(grep "ACQUIA_ENVIRONMENT_ID=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_ENVIRONMENT_ID=\(.*\)$/\1/')

# 📌 Obtener token de autenticación
TOKEN=$(curl -s -X POST "https://accounts.acquia.com/api/auth/oauth/token" \
  -d "client_id=$ACQUIA_API_KEY" \
  -d "client_secret=$ACQUIA_API_SECRET" \
  -d "grant_type=client_credentials" | jq -r '.access_token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
    echo "❌ Error: Could not retrieve authentication token."
    exit 1
fi

# 📌 Obtener lista de entornos desde Acquia Cloud
ENVIRONMENTS=$(curl -s -X GET "https://cloud.acquia.com/api/applications/$PROJECT_ID/environments" \
  -H "Authorization: Bearer $TOKEN" -H "Accept: application/json")

if [[ $(echo "$ENVIRONMENTS" | jq -r '._embedded.items | length') -eq 0 ]]; then
    echo "❌ Error: No environments found for application."
    exit 1
fi

# 📌 Crear archivo vacío si no existe
if [[ ! -f "$PROJECTS_JSON" ]]; then
    echo '{"projects": []}' > "$PROJECTS_JSON"
fi

# 📌 Recorrer cada entorno y generar JSON
PROJECTS=()
while IFS= read -r ENV; do
    ENV_ID=$(echo "$ENV" | jq -r '.id')
    ENV_TYPE=$(echo "$ENV" | jq -r '.name')
    APP_NAME=$(echo "$ENV" | jq -r '.application.name' | tr -d ' ' | tr '[:upper:]' '[:lower:]')
    BRANCH=$(echo "$ENV" | jq -r '.vcs.path')
    REPO_URL=$(echo "$ENV" | jq -r '.vcs.url')
    SSH_URL=$(echo "$ENV" | jq -r '.ssh_url')

    # 📌 Definir ruta esperada del proyecto en ~/Sites/ddev
    PROJECT_PATH="$PROJECTS_DIR/${APP_NAME}-${ENV_TYPE}"

    # 📌 Verificar si la carpeta existe
    if [[ -d "$PROJECT_PATH" && -f "$PROJECT_PATH/.ddev/config.yaml" ]]; then
        CLONED_PATH="$PROJECT_PATH"
    else
        CLONED_PATH=""
    fi

    # 📌 Agregar datos al array de proyectos
    PROJECTS+=("{
      \"app_name\": \"$APP_NAME\",
      \"environment_id\": \"$ENV_ID\",
      \"environment_type\": \"$ENV_TYPE\",
      \"project_path\": \"$CLONED_PATH\",
      \"repository\": \"$REPO_URL\",
      \"branch\": \"$BRANCH\",
      \"ssh_url\": \"$SSH_URL\"
    }")

done <<< "$(echo "$ENVIRONMENTS" | jq -c '._embedded.items[]')"

# 📌 Escribir datos en el archivo JSON global
echo "{ \"projects\": [" > "$PROJECTS_JSON"
IFS=,
echo "${PROJECTS[*]}" >> "$PROJECTS_JSON"
echo "]}" >> "$PROJECTS_JSON"

echo "✅ Acquia environments synchronized successfully!"
