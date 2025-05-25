#!/usr/bin/env bash

## Description: Clone a specific site from Acquia Cloud into the local DDEV environment with proper multisite setup.
## Usage: acquia-clone-site  [site_name]
## Example: ddev acquia-clone-site coorslight
## CanRunGlobally: false

set -e
source "$(dirname "$0")/../lib/utils.sh"

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

# 📌 Functions

function verify_dependencies() {
  echo "🔄 Verificando dependencias necesarias..."

  # Verificar Homebrew
  if ! command -v brew &>/dev/null; then
      echo "⚠️ Homebrew no está instalado. Instalando Homebrew..."
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
      echo "✅ Homebrew ya está instalado."
  fi

  # Verificar yq (para manipular YAML)
  if ! command -v yq &>/dev/null; then
      echo "⚠️ yq no encontrado. Instalando yq..."
      brew install yq
  else
      echo "✅ yq ya está instalado."
  fi

  # Verificar curl (normalmente preinstalado en macOS)
  if ! command -v curl &>/dev/null; then
      echo "⚠️ curl no encontrado. Instalando curl..."
      brew install curl
  else
      echo "✅ curl ya está instalado."
  fi

  # Verificar jq (para manipulación de JSON)
  if ! command -v jq &>/dev/null; then
      echo "⚠️ jq no encontrado. Instalando jq..."
      brew install jq
  else
      echo "✅ jq ya está instalado."
  fi
  echo "✅ Todas las dependencias necesarias están instaladas."
}

# Ejecutar la verificación de dependencias al inicio del script
verify_dependencies

function validate_environment() {
    echo "🔄 Validando entorno..."
    [[ -f ".ddev/config.yaml" ]] || { echo "❌ Error: No es un proyecto DDEV válido."; exit 1; }
    [[ -f "$PROJECTS_JSON" ]] || { echo "❌ Error: Falta acquia-projects.json."; exit 1; }
    [[ -n "$SITE_NAME" ]] || { echo "❌ Error: Debes especificar un nombre de sitio."; exit 1; }
    echo "✅ Entorno validado correctamente."
}

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

function verify_site_exists() {
    echo "🔄 Verificando existencia del sitio en Acquia..."
    DB_RESPONSE=$(curl -s -X GET "https://cloud.acquia.com/api/environments/$ENVIRONMENT_ID/databases" \
        -H "Authorization: Bearer $TOKEN" -H "Accept: application/json")
    SITE_DB_INFO=$(echo "$DB_RESPONSE" | jq -r --arg SITE "$SITE_NAME" '._embedded.items[]? | select(.name == $SITE)')
    [[ -n "$SITE_DB_INFO" ]] || { echo "❌ Error: Sitio '$SITE_NAME' no encontrado."; exit 1; }
    DB_NAME=$(echo "$SITE_DB_INFO" | jq -r '.name')
    echo "✅ Sitio '$SITE_NAME' encontrado en Acquia."
}

function site_already_cloned() {
    echo "🔄 Verificando si el sitio ya está clonado..."
    EXISTING_SITE=$(echo "$ENV_DATA" | jq -r --arg SITE_NAME "$SITE_NAME" '.databases[]? | select(. == $SITE_NAME)')
    [[ -n "$EXISTING_SITE" ]]
}

function verify_local_alias() {
    echo "🔄 Verificando alias local..."
    if ! grep -q "$DB_NAME:" "$LOCAL_SITE_YML"; then
        echo "⚠️  Alias local no encontrado, agregando..."
        echo "$DB_NAME:" >> "$LOCAL_SITE_YML"
        echo "  root: /var/www/html/docroot" >> "$LOCAL_SITE_YML"
        echo "  uri: '$DB_NAME-$ENVIRONMENT_TYPE.ddev.site'" >> "$LOCAL_SITE_YML"
    fi
    echo "✅ Alias local verificado."
}

function verify_database_settings() {
    echo "🔄 Verificando configuración de conexión a la base de datos..."
    SITE_PATH="$SITES_PATH/$DB_NAME"
    SETTINGS_PATH="$SITE_PATH/settings.php"
    SETTINGS_DDEV_PATH="$SITE_PATH/settings.ddev.php"

    # Obtener la información de DDEV
    DDEV_INFO=$(ddev describe -j)
    DDEV_DB_CONTAINER=$(echo "$DDEV_INFO" | jq -r '.raw.services.db.full_name')
    DDEV_PROJECT_NAME=$(echo "$DDEV_INFO" | jq -r '.raw.name')
    SITE_DOMAIN="${DB_NAME}-${ENVIRONMENT_TYPE}"

    # Crear settings.ddev.php con la configuración local
    if [[ ! -f "$SETTINGS_DDEV_PATH" ]]; then
        echo "⚠️  Creando settings.ddev.php..."
        cat > "$SETTINGS_DDEV_PATH" << EOL
<?php

/**
 * @file
 * DDEV local development override configuration file.
 */

\$databases['default']['default'] = [
  'database' => '$DB_NAME',
  'username' => 'db',
  'password' => 'db',
  'host' => '$DDEV_DB_CONTAINER',
  'port' => '3306',
  'driver' => 'mysql',
  'prefix' => '',
  'namespace' => 'Drupal\\Core\\Database\\Driver\\mysql',
  'collation' => 'utf8mb4_general_ci',
];

// Skip permissions hardening in local development.
\$settings['skip_permissions_hardening'] = TRUE;

// Trusted host patterns.
\$settings['trusted_host_patterns'] = [
  // Patrón para el dominio principal del proyecto
  '^millercoorsd8-test\.ddev\.site\$',
  // Patrón para el sitio específico
  '^$DB_NAME-$ENVIRONMENT_TYPE\.ddev\.site\$',
  // Patrones para localhost
  '^localhost\$',
  '^127\.0\.0\.1\$',
  // Patrón para puertos alternativos
  '^millercoorsd8-test\.ddev\.site:[0-9]+\$',
  '^$DB_NAME-$ENVIRONMENT_TYPE\.ddev\.site:[0-9]+\$',
];

// Configure Redis if available.
if (getenv('REDIS_HOSTNAME')) {
  \$settings['redis.connection']['interface'] = 'PhpRedis';
  \$settings['redis.connection']['host'] = getenv('REDIS_HOSTNAME');
  \$settings['redis.connection']['port'] = getenv('REDIS_PORT');
  \$settings['cache']['default'] = 'cache.backend.redis';
}
EOL
    fi

    # Asegurar que settings.php incluya settings.ddev.php
    if [[ ! -f "$SETTINGS_PATH" ]]; then
        echo "⚠️  Creando settings.php..."
        cat > "$SETTINGS_PATH" << EOL
<?php

if (file_exists(\$app_root . '/' . \$site_path . '/settings.ddev.php')) {
  include \$app_root . '/' . \$site_path . '/settings.ddev.php';
}
EOL
    elif ! grep -q "settings.ddev.php" "$SETTINGS_PATH"; then
        echo "⚠️  Agregando inclusión de settings.ddev.php..."
        echo "
if (file_exists(\$app_root . '/' . \$site_path . '/settings.ddev.php')) {
  include \$app_root . '/' . \$site_path . '/settings.ddev.php';
}" >> "$SETTINGS_PATH"
    fi

    chmod 644 "$SETTINGS_PATH" "$SETTINGS_DDEV_PATH"
    echo "✅ Configuración de conexión verificada."
}

function verify_multisite_config() {
    echo "🔄 Verificando configuración multisitio..."
    MULTISITE_CONFIG=".ddev/config.sites.yaml"
    SITE_DOMAIN="${DB_NAME}-${ENVIRONMENT_TYPE}"
    
    # Crear archivo si no existe con la estructura base
    if [[ ! -f "$MULTISITE_CONFIG" ]]; then
        echo "🔄 Creando nueva configuración multisitio..."
        mkdir -p "$(dirname "$MULTISITE_CONFIG")"
        cat > "$MULTISITE_CONFIG" << EOL
additional_hostnames:
database:
    additional_databases:
EOL
    fi

    # Verificar si el hostname ya existe
    if ! grep -q "^\s*-\s*${SITE_DOMAIN}\$" "$MULTISITE_CONFIG"; then
        echo "🔄 Agregando hostname ${SITE_DOMAIN}..."
        # Crear archivo temporal
        TEMP_FILE=$(mktemp)
        
        # Variable para rastrear si ya procesamos la sección
        HOSTNAME_ADDED=false
        DATABASE_ADDED=false
        
        while IFS= read -r line || [[ -n "$line" ]]; do
            echo "$line" >> "$TEMP_FILE"
            
            # Después de additional_hostnames, agregar el nuevo hostname si aún no se ha agregado
            if [[ "$line" =~ ^additional_hostnames:$ ]] && [[ "$HOSTNAME_ADDED" == "false" ]]; then
                echo "    - ${SITE_DOMAIN}" >> "$TEMP_FILE"
                HOSTNAME_ADDED=true
            fi
            
            # Después de additional_databases, agregar la nueva base de datos si aún no se ha agregado
            if [[ "$line" =~ ^.*additional_databases:$ ]] && [[ "$DATABASE_ADDED" == "false" ]]; then
                echo "        - ${DB_NAME}" >> "$TEMP_FILE"
                DATABASE_ADDED=true
            fi
        done < "$MULTISITE_CONFIG"
        
        # Si por alguna razón no se agregaron, agregarlos al final
        if [[ "$HOSTNAME_ADDED" == "false" ]]; then
            echo "additional_hostnames:" >> "$TEMP_FILE"
            echo "    - ${SITE_DOMAIN}" >> "$TEMP_FILE"
        fi
        if [[ "$DATABASE_ADDED" == "false" ]]; then
            echo "database:" >> "$TEMP_FILE"
            echo "    additional_databases:" >> "$TEMP_FILE"
            echo "        - ${DB_NAME}" >> "$TEMP_FILE"
        fi
        
        # Reemplazar el archivo original
        mv "$TEMP_FILE" "$MULTISITE_CONFIG"
        echo "✅ Configuración actualizada."
    else
        echo "ℹ️  El hostname ${SITE_DOMAIN} ya existe en la configuración."
    fi
    
    echo "✅ Configuración multisitio verificada."
}

function verify_configurations() {
    echo "🔄 Verificando configuraciones del sitio..."
    verify_local_alias
    verify_database_settings
    #verify_sites_local
    verify_multisite_config
    echo "✅ Configuraciones verificadas correctamente."
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



function update_acquia_projects() {
    echo "🔄 Actualizando registro de sitios clonados..."
    local TEMP_FILE=$(mktemp)
    
    if [[ ! -f "$PROJECTS_JSON" ]]; then
        echo "⚠️  Archivo de proyectos no encontrado, creando uno nuevo..."
        cat > "$PROJECTS_JSON" << EOL
{
  "projects": []
}
EOL
    fi
    jq --arg path "$PWD" \
       --arg db "$DB_NAME" \
       '(.projects[] | select(.project_path == $path)).databases |= if . then (. + [$db] | unique) else [$db] end' \
       "$PROJECTS_JSON" > "$TEMP_FILE"

    if [[ $? -eq 0 ]] && [[ -s "$TEMP_FILE" ]]; then
        mv "$TEMP_FILE" "$PROJECTS_JSON"
        echo "✅ Registro actualizado correctamente."
    else
        rm -f "$TEMP_FILE"
        echo "⚠️  Error al actualizar el registro, creando nuevo registro..."
        # Si falla, crear una nueva estructura
        cat > "$PROJECTS_JSON" << EOL
{
  "projects": [
    {
      "project_path": "$PWD",
      "databases": ["$DB_NAME"]
    }
  ]
}
EOL
    fi
}

function clone_site_from_scratch() {
    echo "🔄 Iniciando clonación desde cero..."
    verify_configurations
    sync_database
    #sync_files
    update_acquia_projects
    echo "✅ Clonación desde cero completada."
}

function offer_sync_options() {
    echo "🔄 Verificando opciones de sincronización..."
    read -p "¿Deseas sincronizar la base de datos? [y/N]: " SYNC_DB
    if [[ "$SYNC_DB" =~ ^[Yy]$ ]]; then
        sync_database
    fi

    #read -p "¿Deseas sincronizar los archivos? [y/N]: " SYNC_FILES
    #if [[ "$SYNC_FILES" =~ ^[Yy]$ ]]; then
     #   sync_files
    #fi
 #   echo "✅ Sincronización completada."
}

ddev auth ssh

function verify_database_access() {
    echo "🔄 Verificando acceso a la base de datos..."
    if ! ddev drush @loc."$DB_NAME" sql-query "SHOW DATABASES LIKE '$DB_NAME';" > /dev/null 2>&1; then
        echo "⚠️  Base de datos '$DB_NAME' no encontrada o inaccesible."
        return 1
    fi
    echo "✅ Acceso a base de datos verificado."
}

function verify_ddev_config() {
    echo "🔄 Verificando configuración de DDEV..."
    
    # Verificar que el hostname esté en la configuración
    if ! ddev describe -j | jq -e --arg site "${DB_NAME}-${ENVIRONMENT_TYPE}.ddev.site" '.raw.hostnames[] | select(. == $site)' > /dev/null; then
        echo "⚠️  Hostname no encontrado en la configuración de DDEV."
        return 1
    fi

    if ! ddev describe -j | jq -e --arg db "$DB_NAME" '.raw.dbinfo.databases[]? | select(. == $db)' > /dev/null 2>&1; then
        echo "⚠️  Base de datos no encontrada en la configuración de DDEV."
        return 1
    fi
    
    echo "✅ Configuración de DDEV verificada."
}
function fix_host_permissions() {
    echo "🔄 Corrigiendo permisos en el host para el directorio de archivos..."
    # Construir la ruta absoluta al directorio de archivos en el host
    HOST_SITE_FILES="$PROJECT_PATH/docroot/sites/$DB_NAME/files"
    
    if [[ -d "$HOST_SITE_FILES" ]]; then
        chmod -R 775 "$HOST_SITE_FILES"
        chown -R "$USER":staff "$HOST_SITE_FILES"
        echo "✅ Permisos en host actualizados en $HOST_SITE_FILES"
    else
        echo "⚠️ El directorio $HOST_SITE_FILES no existe, creándolo..."
        mkdir -p "$HOST_SITE_FILES"
        chmod -R 775 "$HOST_SITE_FILES"
        chown -R "$USER":staff "$HOST_SITE_FILES"
        echo "✅ Directorio $HOST_SITE_FILES creado y permisos configurados."
    fi
}


EOF
    else
        echo "ℹ️  Bloque de carga ya presente en sites.php, se omite su inserción."
    fi

    echo "✅ Verificación completada en sites.php."
}


function finalize_process() {
    echo "🔄 Finalizando proceso..."
    
    # Agregar las nuevas verificaciones
    # Verificar y actualizar registros en sites.php y sites.local.php
    verify_sites_php
    # Primero, ajustar permisos en el host
    fix_host_permissions
    # Luego, verificar y ajustar permisos dentro del contenedor
    verify_directory_permissions
    verify_database_access
    #verify_ddev_config
    
    # Reiniciar DDEV para aplicar cambios
    ddev restart
    
    # Limpiar caché de Drupal
    ddev drush @loc.$DB_NAME cr
    
    echo "✅ Sitio '$DB_NAME' disponible en: https://${DB_NAME}-${ENVIRONMENT_TYPE}.ddev.site"
    echo "ℹ️  Si el sitio no responde, verifica los siguientes puntos:"
    echo "   1. La URL https://${DB_NAME}-${ENVIRONMENT_TYPE}.ddev.site es accesible"
    echo "   2. La base de datos '$DB_NAME' existe y tiene contenido"
    echo "   3. Los archivos de configuración en sites/$DB_NAME están correctos"
    echo "   4. Los permisos de los directorios son correctos"
}

function fix_line_endings() {
    echo "🔄 Corrigiendo finales de línea..."
    local file="$1"
    if [[ -f "$file" ]]; then
        # Crear un archivo temporal
        local temp_file=$(mktemp)
        # Convertir CRLF a LF
        tr -d '\r' < "$file" > "$temp_file"
        mv "$temp_file" "$file"
        echo "✅ Finales de línea corregidos en $file"
    fi
}

function verify_drush_files() {
    echo "🔄 Verificando archivos de Drush..."
    
    # Corregir finales de línea en archivos importantes
    fix_line_endings "$LOCAL_SITE_YML"
    fix_line_endings "$SITES_PATH/sites.php"
    fix_line_endings "$SITES_PATH/sites.local.php"
    
    # Verificar permisos
    chmod 644 "$LOCAL_SITE_YML"
    
    echo "✅ Archivos de Drush verificados."
}

function verify_drush_executable() {
    echo "🔄 Verificando ejecutable de Drush..."
    
    # Primero corregir el ejecutable local
    if [[ -f "vendor/bin/drush" ]]; then
        echo "🔧 Corrigiendo finales de línea en vendor/bin/drush..."
        # Obtener los permisos actuales
        CURRENT_PERMS=$(stat -f %A "vendor/bin/drush")
        
        # Crear un archivo temporal
        TEMP_FILE=$(mktemp)
        
        # Convertir CRLF a LF
        tr -d '\r' < "vendor/bin/drush" > "$TEMP_FILE"
        
        # Aplicar los mismos permisos
        chmod "$CURRENT_PERMS" "$TEMP_FILE"
        
        # Reemplazar el archivo original
        mv "$TEMP_FILE" "vendor/bin/drush"
        
        echo "✅ Drush ejecutable corregido"
    fi
    
    # Corregir dentro del contenedor usando ddev exec
    echo "🔧 Corrigiendo Drush dentro del contenedor..."
    ddev exec "sudo find /var/www/html/vendor/bin -name 'drush' -type f -exec sh -c 'tr -d \"\r\" < \"{}\" > \"{}.tmp\" && mv \"{}.tmp\" \"{}\"' \;"
    
    # Verificar que Drush funciona
    if ddev exec "drush status" > /dev/null 2>&1; then
        echo "✅ Verificación de Drush completada."
    else
        echo "⚠️  Advertencia: Drush podría no estar funcionando correctamente."
        # Continuamos de todos modos, ya que esto no es crítico
    fi
}

# 📌 Main execution flow
function main() {
    echo "🚀 Iniciando proceso de clonación para el sitio: $SITE_NAME"
    
    validate_environment
    load_configuration
    authenticate_with_acquia
    verify_site_exists
    
    if site_already_cloned; then
        echo "ℹ️  El sitio ya está clonado. Verificando configuraciones..."
        verify_configurations
        verify_drush_files
        offer_sync_options
    else
        echo "ℹ️  Clonando sitio por primera vez..."
        clone_site_from_scratch
        verify_drush_files
    fi
    
    finalize_process
    echo "🎉 Proceso completado exitosamente!"
}

# Execute main function
main