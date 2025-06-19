#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Instalador para entorno DDEV + Acquia multisite (macOS)"
echo "-----------------------------------------------------------"

# 📌 Variables
GLOBAL_DDEV_DIR="$HOME/.ddev"
CUSTOM_COMMANDS_SOURCE="$(pwd)/ddev-custom-commands"
GLOBAL_COMMANDS_DIR="$GLOBAL_DDEV_DIR/commands"
NEEDED_TOOLS=(jq yq curl wget)
REQUIRED_FILES=("global_config.yaml" "acquia-projects.json")

# 📍 Funciones

function check_brew() {
  echo "🔍 Verificando Homebrew..."
  if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew no está instalado. Instalando..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "✅ Homebrew detectado."
  fi
}

function check_ddev() {
  echo "🔍 Verificando DDEV..."
  if ! command -v ddev &>/dev/null; then
    echo "❌ DDEV no está instalado."
    echo "➡️  Instálalo con: brew install drud/ddev/ddev"
    exit 1
  fi
  echo "✅ DDEV detectado: $(ddev --version)"
}

function install_tools() {
  echo "🔧 Verificando herramientas esenciales..."

  for tool in "${NEEDED_TOOLS[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      echo "⬇️  Instalando $tool..."
      brew install "$tool"
    else
      echo "✅ $tool ya está instalado."
    fi
  done
}

function install_acquia_cli() {
  echo "🔍 Verificando Acquia CLI..."
  if ! command -v acli &>/dev/null; then
    echo "⬇️  Instalando Acquia CLI..."
    brew tap acquia/cli
    brew install acquia-cli
  else
    echo "✅ Acquia CLI detectado: $(acli --version)"
  fi
}

function setup_global_commands() {
  echo "⚙️  Configurando comandos globales DDEV..."

  mkdir -p "$GLOBAL_COMMANDS_DIR/host"
  mkdir -p "$GLOBAL_COMMANDS_DIR/web"

  if [[ -d "$CUSTOM_COMMANDS_SOURCE/host" ]]; then
    echo "📁 Copiando comandos host..."
    cp -v "$CUSTOM_COMMANDS_SOURCE/host/"* "$GLOBAL_COMMANDS_DIR/host/"
    chmod +x "$GLOBAL_COMMANDS_DIR/host/"*
  fi

  if [[ -d "$CUSTOM_COMMANDS_SOURCE/web" ]]; then
    echo "📁 Copiando comandos web..."
    cp -v "$CUSTOM_COMMANDS_SOURCE/web/"* "$GLOBAL_COMMANDS_DIR/web/"
    chmod +x "$GLOBAL_COMMANDS_DIR/web/"*
  fi

  echo "✅ Comandos instalados globalmente en ~/.ddev/commands/"
}

function validate_global_files() {
  echo "📦 Verificando archivos de configuración en ~/.ddev/"

  mkdir -p "$GLOBAL_DDEV_DIR"

  for file in "${REQUIRED_FILES[@]}"; do
    full_path="$GLOBAL_DDEV_DIR/$file"
    if [[ ! -f "$full_path" ]]; then
      echo "⚠️  Archivo faltante: $file. Creando plantilla..."
      if [[ "$file" == "acquia-projects.json" ]]; then
        echo '{ "projects": [] }' > "$full_path"
      elif [[ "$file" == "global_config.yaml" ]]; then
        cat > "$full_path" <<EOL
# Añade aquí tus claves de Acquia
# ACQUIA_API_KEY=your-key
# ACQUIA_API_SECRET=your-secret
EOL
      fi
      echo "✅ Archivo creado: $file"
    else
      echo "✅ Archivo detectado: $file"
    fi
  done
}

function setup_multisite_base() {
  echo "🧱 Configurando estructura multisite (si es proyecto activo)..."

  if [[ -f .ddev/config.yaml ]]; then
    mkdir -p drush/sites

    [[ ! -f .ddev/config.sites.yaml ]] && echo -e "additional_hostnames:\ndatabase:\n    additional_databases:" > .ddev/config.sites.yaml
    [[ ! -f drush/sites/loc.site.yml ]] && touch drush/sites/loc.site.yml

    echo "✅ Archivos multisite base verificados."
  else
    echo "ℹ️ No estás en un proyecto DDEV activo. Puedes ejecutar esto dentro de uno si deseas configurar multisite."
  fi
}

function validate_ddev_drush_composer() {
  echo "🔍 Verificando que Composer y Drush funcionen dentro del contenedor..."

  if ! ddev exec composer --version &>/dev/null; then
    echo "⚠️ Composer no está disponible dentro del contenedor. ¿Deseas instalarlo ahora?"
    read -p "Instalar Composer dentro del contenedor con ddev? [Y/n]: " install_comp
    if [[ "$install_comp" =~ ^[Yy]$ || "$install_comp" == "" ]]; then
      ddev exec curl -sS https://getcomposer.org/installer | ddev exec php
      ddev exec mv composer.phar /usr/local/bin/composer
    fi
  else
    echo "✅ Composer disponible en el contenedor: $(ddev exec composer --version)"
  fi

  if ! ddev exec vendor/bin/drush --version &>/dev/null; then
    echo "⚠️ Drush no está instalado en este proyecto."
    echo "➡️  Instalando como dependencia de Composer..."
    ddev composer require drush/drush
  else
    echo "✅ Drush detectado: $(ddev exec vendor/bin/drush --version)"
  fi
}

function summary() {
  echo -e "\n🎉 Setup completo."
  echo "👉 Usa tus comandos con: ddev <nombre-del-comando>"
  echo "👉 Verifica tus credenciales Acquia en ~/.ddev/global_config.yaml"
  echo "👉 Si estás dentro de un proyecto, ejecuta: ddev restart"
  echo "👉 Ejecuta Drush como: ddev drush status"
  echo
}

check_brew
check_ddev
install_tools
#install_acquia_cli
setup_global_commands
validate_global_files
#setup_multisite_base
#validate_ddev_drush_composer
summary
