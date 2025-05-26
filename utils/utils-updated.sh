#!/usr/bin/env bash

# 💬 Logging helpers
info()    { echo "ℹ️  $*"; }
success() { echo "✅ $*"; }
warn()    { echo "⚠️  $*"; }
error()   { echo "❌ $*"; exit 1; }

# 🔁 Paths used across scripts
GLOBAL_CONFIG="$HOME/.ddev/global_config.yaml"
PROJECTS_JSON="$HOME/.ddev/acquia-projects.json"
PROJECTS_DIR="$HOME/Sites/ddev"
SITES_PATH="docroot/sites"
LOCAL_SITE_YML="drush/sites/loc.site.yml"

# 📦 Extract Acquia credentials from global config if available
if [[ -f "$GLOBAL_CONFIG" ]]; then
  ACQUIA_API_KEY=$(grep "ACQUIA_API_KEY=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_KEY=\(.*\)$/\1/')
  ACQUIA_API_SECRET=$(grep "ACQUIA_API_SECRET=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_API_SECRET=\(.*\)$/\1/')
  ACQUIA_ENVIRONMENT_ID=$(grep "ACQUIA_ENVIRONMENT_ID=" "$GLOBAL_CONFIG" | sed 's/.*ACQUIA_ENVIRONMENT_ID=\(.*\)$/\1/')
else
  warn "global_config.yaml not found. Acquia credentials may be missing."
fi

# Warn if credentials are missing
[[ -z "$ACQUIA_API_KEY" || -z "$ACQUIA_API_SECRET" ]] && warn "One or more Acquia credentials are empty."

export ACQUIA_API_KEY ACQUIA_API_SECRET ACQUIA_ENVIRONMENT_ID

# 📦 Check required dependencies
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

# 🔐 Get Acquia API token using exported credentials
function get_acquia_token() {
  curl -s -X POST "https://accounts.acquia.com/api/auth/oauth/token" \
    -d "client_id=$ACQUIA_API_KEY" \
    -d "client_secret=$ACQUIA_API_SECRET" \
    -d "grant_type=client_credentials" | jq -r '.access_token'
}

# 🧪 Validate DDEV environment
function validate_environment() {
  [[ -f ".ddev/config.yaml" ]] || error "Not a valid DDEV project."
  [[ -f "$PROJECTS_JSON" ]] || error "Missing acquia-projects.json."
}

# 📘 Ensure sites.local.php is included in sites.php
function verify_sites_php() {
  local sites_php="$SITES_PATH/sites.php"

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

# 🧩 Register site in sites.local.php if not already added
function register_local_site() {
  local domain="$1"
  local directory="$2"
  local sites_file="$SITES_PATH/sites.local.php"

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
