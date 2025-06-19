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

function verify_directory_permissions() {
    echo "🔄 Verificando permisos de directorios..."
    SITE_PATH="$SITES_PATH/$DB_NAME"
    
    # Crear directorios necesarios si no existen
    mkdir -p "$SITE_PATH/files"
    
    # Establecer permisos base
    chmod 755 "$SITE_PATH"
    chmod 755 "$SITE_PATH/files"
    
    echo "🔄 Ajustando propietario de archivos dentro del contenedor..."
    # Usar sudo dentro del contenedor para cambiar el propietario
    if ! ddev exec "sudo chown -R www-data:www-data /var/www/html/$SITE_PATH/files"; then
        echo "⚠️  No se pudieron cambiar los permisos usando sudo, intentando sin sudo..."
        if ! ddev exec "chown -R www-data:www-data /var/www/html/$SITE_PATH/files"; then
            echo "⚠️  No se pudieron establecer los permisos correctos. Los archivos podrían no ser escribibles."
            # Continuar a pesar del error, ya que los archivos podrían funcionar con los permisos actuales
        fi
    fi
    
    echo "✅ Permisos de directorios verificados."
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
read -p "please input the alias of the site you'd like to sync it's db": DB_NAME
read -p "Please input the environment type(dev,test or prod) you would like to sync your local env in:" ENVIRONMENT_TYPE

authenticate_with_acquia
sync_files