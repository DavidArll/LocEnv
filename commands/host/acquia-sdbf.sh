#!/usr/bin/env bash

#set -e

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

