#!/usr/bin/env bash

set -e

# 📌 Paths
GLOBAL_CONFIG="$HOME/.ddev/global_config.yaml"
PROJECTS_JSON="$HOME/.ddev/acquia-projects.json"
SITES_PATH="docroot/sites"
LOCAL_SITE_YML="drush/sites/loc.site.yml"

# 📌 Variables
SITE_NAME=$1
DB_NAME=""
APP_NAME=""
ENVIRONMENT_ID=""
ENVIRONMENT_TYPE=""
TOKEN=""

function load_configuration() {
    echo "🔄 Cargando configuración..."
    ENV_DATA=$(jq -c --arg PROJECT_PATH "$PWD" '.projects[] | select(.project_path == $PROJECT_PATH)' "$PROJECTS_JSON")
    [[ -n "$ENV_DATA" ]] || { echo "❌ Error: Proyecto no registrado en acquia-projects.json."; exit 1; }
    APP_NAME=$(echo "$ENV_DATA" | jq -r '.app_name')
    ENVIRONMENT_ID=$(echo "$ENV_DATA" | jq -r '.environment_id')
    ENVIRONMENT_TYPE=$(echo "$ENV_DATA" | jq -r '.environment_type')
    PROJECT_PATH=$(echo "$ENV_DATA" | jq -r '.project_path')
    echo "✅ Configuración cargada correctamente."
}

function authenticate_with_acquia() {
    echo "🔄 Autenticando con Acquia..."
    ACQUIA_API_KEY=$(grep "ACQUIA_API_KEY=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_KEY=\(.*\)$/\1/')
    ACQUIA_API_SECRET=$(grep "ACQUIA_API_SECRET=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_SECRET=\(.*\)$/\1/')
    # Validar que las credenciales no estén vacías
    if [[ -z "$ACQUIA_API_KEY" || -z "$ACQUIA_API_SECRET" ]]; then
        echo "❌ Error: Las credenciales de Acquia no se encuentran en $GLOBAL_CONFIG."
        exit 1
    fi
    echo "   - ACQUIA_API_KEY y ACQUIA_API_SECRET obtenidos correctamente."

    # Obtener token y capturar respuesta completa para fines de debugging
    RESPONSE=$(curl -s -X POST "https://accounts.acquia.com/api/auth/oauth/token" \
        -d "client_id=$ACQUIA_API_KEY" \
        -d "client_secret=$ACQUIA_API_SECRET" \
        -d "grant_type=client_credentials")
    
    TOKEN=$(echo "$RESPONSE" | jq -r '.access_token')
    
    if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
        echo "❌ Error: No se pudo obtener el token de autenticación."
        echo "   - Respuesta de Acquia: $RESPONSE"
        exit 1
    fi
    
    echo "✅ Autenticación exitosa. Token obtenido."
}

function sync_database() {
    echo "🔄 Sincronizando base de datos..."
    if ddev drush sql-sync "@$DB_NAME.$ENVIRONMENT_TYPE" "@loc.$DB_NAME" -y; then
        echo "✅ Base de datos sincronizada correctamente."
    else
        echo "⚠️  Falló la sincronización con Drush, usando backup de Acquia..."
        BACKUP_DATA=$(curl -s -X GET "https://cloud.acquia.com/api/environments/$ENVIRONMENT_ID/databases/$DB_NAME/backups" \
            -H "Authorization: Bearer $TOKEN" -H "Accept: application/json")
        
        if [[ $(echo "$BACKUP_DATA" | jq -r '._embedded.items | length') -eq 0 ]]; then
            echo "❌ No se encontraron backups para la base de datos '$DB_NAME'."
            exit 1
        fi
        
        LATEST_BACKUP=$(echo "$BACKUP_DATA" | jq -r '._embedded.items | max_by(.started_at)')
        DOWNLOAD_URL=$(echo "$LATEST_BACKUP" | jq -r '._links.download.href')
        
        echo "📥 Descargando backup desde $DOWNLOAD_URL..."
        curl -L -o "$DB_NAME.sql.gz" -X GET "$DOWNLOAD_URL" \
            -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream"
        
        echo "🔄 Importando base de datos en DDEV..."
        ddev import-db --database="$DB_NAME" --file="$DB_NAME.sql.gz"
        rm -f "$DB_NAME.sql.gz"
        echo "✅ Base de datos importada correctamente."
    fi
}

echo "********** - Acquia Sync-DB - **********"
echo ""
read -p "please input the alias of the site you'd like to sync it's db":
read -p "Please input the environment type(dev,test or prod) you would like to sync your local env in:"
load_configuration
authenticate_with_acquia
sync_database