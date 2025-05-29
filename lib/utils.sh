#!/usr/bin/env bash

# === Estilos y colores ===
export BOLD='\033[1m'
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# === Funciones de logging ===
log_info()    { echo -e "${BLUE}ℹ $1${NC}"; }
log_success() { echo -e "${GREEN}✓ $1${NC}"; }
log_error()   { echo -e "${RED}✗ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
log_debug()   { echo -e "${BOLD}DEBUG: $1${NC}"; }

# ─────────────────────────────────────────────
# 🔁 Spinner / Progress
# ─────────────────────────────────────────────
# === Spinner / Progress Indicator ===

_SPINNER_PID=""
_SPINNER_DELAY=0.1
_SPINNER_CHARS='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'  # '|/-\'Puedes cambiar por '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏' para estilo braille

start_spinner() {
  local message="$1"
  [[ -n "$DEBUG" ]] && log_info "$message (sin spinner)" && return 0

  echo -ne "${BLUE}⏳ $message ${NC}"
  {
    while true; do
      for c in $(echo "$_SPINNER_CHARS" | grep -o .); do
        echo -ne "$c"
        echo -ne "\b"
        sleep "$_SPINNER_DELAY"
      done
    done
  } &
  _SPINNER_PID=$!
  disown
}

stop_spinner() {
  local exit_code=$1

  if [[ -n "$_SPINNER_PID" ]]; then
    kill "$_SPINNER_PID" &>/dev/null
    wait "$_SPINNER_PID" 2>/dev/null
    _SPINNER_PID=""
    echo -ne "\b"  # limpiar spinner
  fi

  if [[ "$exit_code" -eq 0 ]]; then
    echo -e "${GREEN}✅${NC}"
  else
    echo -e "${RED}❌${NC}"
  fi
}
# ─────────────────────────────────────────────
# 🔁 Fin de Spinner / Progress

# ─────────────────────────────────────────────
# 🧪 Validar entorno local DDEV
validate_environment() {
  [[ -f ".ddev/config.yaml" ]] || error "Not a valid DDEV project."
  [[ -f "$PROJECTS_JSON" ]] || error "Missing acquia-projects.json."
}

# 🔧 Verificar dependencias necesarias
verify_dependencies() {
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

# 📘 Asegura inclusión de sites.local.php en sites.php
verify_sites_php() {
  local sites_php="$SITES_PATH/sites.php"
  [[ -f "$sites_php" ]] || error "$sites_php does not exist."

  info "Verifying sites.php includes sites.local.php..."
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
register_local_site() {
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