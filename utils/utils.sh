#!/usr/bin/env bash

# 💬 Logging helpers
info()    { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warn()    { echo "⚠️  $*"; }
error()   { echo "❌ $*"; exit 1; }

# 🔁 Paths usados por todos los scripts
GLOBAL_CONFIG="$HOME/.ddev/global_config.yaml"
PROJECTS_JSON="$HOME/.ddev/acquia-projects.json"
PROJECTS_DIR="$HOME/Sites/ddev"
SITES_PATH="docroot/sites"
LOCAL_SITE_YML="drush/sites/loc.site.yml"

# 📦 Extraer credenciales de Acquia (si existen en global_config)
if [[ -f "$GLOBAL_CONFIG" ]]; then
  ACQUIA_API_KEY=$(grep "ACQUIA_API_KEY=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_KEY=\(.*\)$/\1/')
  ACQUIA_API_SECRET=$(grep "ACQUIA_API_SECRET=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_SECRET=\(.*\)$/\1/')
  ACQUIA_ENVIRONMENT_ID=$(grep "ACQUIA_ENVIRONMENT_ID=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_ENVIRONMENT_ID=\(.*\)$/\1/')
else
  warn "global_config.yaml not found, Acquia credentials may be missing."
fi

export ACQUIA_API_KEY ACQUIA_API_SECRET ACQUIA_ENVIRONMENT_ID

# 📦 Verificar dependencias necesarias
function verify_dependencies() {
  local dependencies=("jq" "curl" "sed" "grep")
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      warn "$dep is not installed. Attempting to install..."
      if command -v brew &> /dev/null; then
        brew install "$dep"
      else
        error "Missing dependency: $dep and Homebrew not found."
      fi
    else
      success "$dep is installed."
    fi
  done
}

function get_acquia_token() {
  local global_config="$HOME/.ddev/global_config.yaml"
  local key=$(grep "ACQUIA_API_KEY=" "$global_config" | sed 's/.*ACQUIA_API_KEY=\(.*\)$/\1/')
  local secret=$(grep "ACQUIA_API_SECRET=" "$global_config" | sed 's/.*ACQUIA_API_SECRET=\(.*\)$/\1/')

  curl -s -X POST "https://accounts.acquia.com/api/auth/oauth/token" \
    -d "client_id=$key" \
    -d "client_secret=$secret" \
    -d "grant_type=client_credentials" | jq -r '.access_token'
}

# 🧪 Validar entorno local DDEV
function validate_environment() {
  [[ -f ".ddev/config.yaml" ]] || error "Not a valid DDEV project."
  [[ -f "$HOME/.ddev/acquia-projects.json" ]] || error "Missing acquia-projects.json."
}

# 📘 Asegura inclusión de sites.local.php en sites.php
function verify_sites_php() {
  local sites_path="docroot/sites"
  local sites_php="$sites_path/sites.php"

  info "Verifying sites.php includes sites.local.php..."

  [[ -f "$sites_php" ]] || error "$sites_php does not exist."

  if ! grep -q 'if (file_exists(__DIR__ . "/sites.local.php")) {' "$sites_php"; then
    warn "sites.local.php include block not found. Appending..."
    cat << 'EOF' >> "$sites_php"

if (file_exists(__DIR__ . "/sites.local.php")) {
  require __DIR__ . "/sites.local.php";
}
EOF
  else
    info "sites.local.php inclusion already present. Skipping."
  fi
  success "sites.php verification completed."
}

# 🧩 Añadir entrada a sites.local.php si no existe
function register_local_site() {
  local domain="$1"
  local directory="$2"
  local sites_file="docroot/sites/sites.local.php"

  info "Registering site '$domain' => '$directory'..."

  [[ -f "$sites_file" ]] || error "$sites_file does not exist."

  if grep -q "\$sites\['$domain'\]" "$sites_file"; then
    info "The domain '$domain' is already registered. Skipping."
    return
  fi

  if grep -q "];" "$sites_file"; then
    sed -i '' "/];/i\
\$sites['$domain'] = '$directory';
" "$sites_file"
  else
    echo "\$sites['$domain'] = '$directory';" >> "$sites_file"
  fi

  success "Site '$domain' registered successfully."
}
