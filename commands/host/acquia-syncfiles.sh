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

function sync_files() {
    echo "🔄 Sincronizando archivos..."
    
    # Asegurar que el directorio de destino existe y tiene los permisos correctos
    echo "test 0"
    mkdir -p "$SITES_PATH/$DB_NAME/files"
    chmod 755 "$SITES_PATH/$DB_NAME/files"
    ddev exec sudo chown -R www-data:www-data /var/www/html/docroot/sites/"$DB_NAME"/files
    echo "test 1"
    # Ejecutar la sincronización y capturar la salida y el código de salida
    verify_directory_permissions
    echo "ddev drush rsync @$DB_NAME.$ENVIRONMENT_TYPE:%files/ @loc.$DB_NAME:%files/ -y --verbose"
    rsync_output=$(ddev drush rsync @$DB_NAME.$ENVIRONMENT_TYPE:%files/ @loc.$DB_NAME:%files/ -y --verbose 2>&1)
    RSYNC_EXIT=$?
    echo "test 2"
    if [[ $RSYNC_EXIT -eq 0 ]]; then
        echo "✅ Archivos sincronizados correctamente."
        verify_directory_permissions
    elif [[ $RSYNC_EXIT -eq 23 ]]; then
        echo "⚠️ Sincronización completada con warnings (algunos archivos no se transfirieron)."
        echo "$rsync_output"
        verify_directory_permissions
    else
        echo "❌ Error al sincronizar archivos (código de salida: $RSYNC_EXIT)."
        echo "$rsync_output"
        echo "ℹ️ Por favor, intenta ejecutar manualmente el siguiente comando:"
        echo "    ddev drush rsync \"@$DB_NAME.$ENVIRONMENT_TYPE:%files/\" \"@loc.$DB_NAME:%files/\" -y"
        echo "Continuando con el proceso..."
        # No se detiene el script, simplemente se continúa.
    fi
}

echo "********** - Acquia Sync-Files - **********"
echo ""
read -p "please input the alias of the site you'd like to sync it's Files:"
read -p "Please input the environment type(dev,test or prod) you would like to sync your local env files from:"

sync_files