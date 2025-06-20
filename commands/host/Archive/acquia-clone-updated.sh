#!/usr/bin/env bash

## Description: Clone an Acquia environment into a new DDEV project or update an existing one.
## Usage: acquia-clone [environment]
## Example: ddev acquia-clone dev
## CanRunGlobally: true

set -e

# 📌 Define paths
GLOBAL_CONFIG="$HOME/.ddev/global_config.yaml"
PROJECTS_JSON="$HOME/.ddev/acquia-projects.json"
PROJECTS_DIR="$HOME/sites/ddev2script"

validate_env_data() {

    if [[ -z "$1" ]]; then
        echo "⚠️ Warning: No environment specified."
        echo "Please choose an environment:"
        echo "1: dev"
        echo "2: test"
        echo "3: prod"
        read -rp "Enter 1, 2, 3 or the environment name: " user_choice
        case "$user_choice" in
            1|dev|DEV) ENV_NAME="dev" ;;
            2|test|TEST) ENV_NAME="test" ;;
            3|prod|PROD) ENV_NAME="prod" ;;
            *) echo "Invalid selection, defaulting to 'dev'." ; ENV_NAME="dev" ;;
        esac
    else
        ENV_NAME=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    fi

    if [[ ! -f "$PROJECTS_JSON" ]]; then
        echo "⚠️ Warning: '$PROJECTS_JSON' does not exist. Running 'ddev acquia-sync-envs'..."
        ddev acquia-sync-envs
        if [[ ! -f "$PROJECTS_JSON" ]]; then
            echo "❌ Error: '$PROJECTS_JSON' still does not exist after syncing."
            exit 1
        fi
    fi

    ENV_DATA=$(jq -c --arg ENV_NAME "$ENV_NAME" '.projects[] | select(.environment_type == $ENV_NAME)' "$PROJECTS_JSON")
    if [[ -z "$ENV_DATA" ]]; then
        echo "⚠️ Warning: The environment '$ENV_NAME' does not exist in Acquia Cloud. Running 'ddev acquia-sync-envs' to refresh..."
        ddev acquia-sync-envs
        ENV_DATA=$(jq -c --arg ENV_NAME "$ENV_NAME" '.projects[] | select(.environment_type == $ENV_NAME)' "$PROJECTS_JSON")
        if [[ -z "$ENV_DATA" ]]; then
            echo "❌ Error: The environment '$ENV_NAME' still does not exist after syncing."
            exit 1
        fi
    fi

    export ENV_NAME
    export ENV_DATA
}

if ! command -v jq &> /dev/null; then
    echo "⚠️ Warning: 'jq' is not installed. Installing using brew..."
    brew install jq
fi

validate_env_data "$1"

# 📌 Extract environment details
APP_NAME=$(echo "$ENV_DATA" | jq -r '.app_name')
ENVIRONMENT_ID=$(echo "$ENV_DATA" | jq -r '.environment_id')
PROJECT_PATH=$(echo "$ENV_DATA" | jq -r '.project_path')
BRANCH=$([ "$ENV_NAME" = "prod" ] && echo "main" || echo "$(echo "$ENV_DATA" | jq -r '.branch')")
REPO_URL=git@gitcode.acquia.com:MillerCoorsD8/millercoors-d8.git
SSH_URL=$(echo "$ENV_DATA" | jq -r '.ssh_url')

EXPECTED_PROJECT_PATH="$PROJECTS_DIR/${APP_NAME}-${ENV_NAME}"
if [[ -z "$PROJECT_PATH" ]]; then
    echo "⚠️ Warning: 'project_path' is empty in the JSON. Using EXPECTED_PROJECT_PATH: $EXPECTED_PROJECT_PATH"
    PROJECT_PATH="$EXPECTED_PROJECT_PATH"
fi

# 📌 Check if project directory already exists
if [[ -d "$PROJECT_PATH" ]]; then
    echo "⚠️ The environment '$ENV_NAME' already exists at: $PROJECT_PATH"
    cd "$PROJECT_PATH"

    # 📌 Check if it's a valid Git repository
    if [[ -d ".git" ]]; then
        echo "🔄 Pulling latest changes from branch '$BRANCH'..."
        git checkout "$BRANCH"
        git pull origin "$BRANCH"
        echo "✅ Code updated successfully!"
    else
        echo "❌ Error: The directory exists but is not a valid Git repository. Please check manually."
        exit 1
    fi

    # 📌 Check if DDEV is already initialized
    if [[ -f ".ddev/config.yaml" ]]; then
        echo "✅ DDEV is already configured. Restarting the environment..."
        ddev restart
    else
        echo "🚀 DDEV is not configured. Initializing DDEV..."
        ddev config --project-type=drupal10 --php-version=8.3 --docroot=docroot
        ddev start
    fi

    # 📌 Ensure the project path is correctly registered in the JSON
    echo "🔄 Updating 'acquia-projects.json' with the correct project path..."
    jq --arg APP_NAME "$APP_NAME" --arg ENV_NAME "$ENV_NAME" --arg PROJECT_PATH "$PROJECT_PATH" \
        '(.projects[] | select(.app_name == $APP_NAME and .environment_type == $ENV_NAME)) .project_path = $PROJECT_PATH' \
        "$PROJECTS_JSON" > "$PROJECTS_JSON.tmp" && mv "$PROJECTS_JSON.tmp" "$PROJECTS_JSON"

    echo "✅ Environment '$ENV_NAME' is up to date and running at: $EXPECTED_PROJECT_PATH"
    exit 0
fi

# 📌 Clone the repository if it doesn't exist
echo "🔄 Cloning repository for '$ENV_NAME' into '$PROJECT_PATH'..."
mkdir -p "$PROJECT_PATH"
git clone --branch "$BRANCH" "$REPO_URL" "$PROJECT_PATH"

# 📌 Enter the project directory
cd "$PROJECT_PATH"

# 📌 Configure DDEV
echo "🚀 Configuring DDEV for Drupal 10..."
ddev config --project-type=drupal10 --php-version=8.3 --docroot=docroot

# Verificar si el hook "composer: install" ya está presente
if ! grep -q "composer: install" .ddev/config.yaml; then
    cat << 'EOF' >> .ddev/config.yaml
hooks:
  post-start:
    - composer: install
EOF
else
    echo "ℹ️ Hook 'composer: install' already exists in .ddev/config.yaml, skipping addition."
fi

function check_port_availability() {
    echo "🔄 Verificando disponibilidad del puerto 80..."
    if sudo lsof -i :80 &>/dev/null; then
        echo "⚠️ Warning: El puerto 80 está en uso. DDEV usará un puerto alternativo, pero esto podría afectar la salud del contenedor."
    else
        echo "✅ Puerto 80 libre."
    fi
}

function verify_container_health() {
    echo "🔄 Verificando salud de los contenedores..."
    sleep 10  # Espera un momento para que los contenedores se estabilicen
    HEALTH_STATUS=$(ddev describe -j | jq -r '.raw.services.web.health')
    if [[ "$HEALTH_STATUS" != "healthy" ]]; then
        echo "❌ Error: El contenedor web no está saludable. Verifica con:"
        echo "   ddev logs -s web"
        echo "   docker logs ddev-<project>-web"
        exit 1
    else
        echo "✅ Contenedores saludables."
    fi
}


# 📌 Start DDEV
echo "🚀 Starting DDEV..."
check_port_availability
ddev start

# Verificar que los contenedores se hayan iniciado correctamente
verify_container_health


echo "🔄 Updating 'acquia-projects.json' with the correct project path..."
jq --arg APP_NAME "$APP_NAME" --arg ENV_NAME "$ENV_NAME" --arg PROJECT_PATH "$PROJECT_PATH" \
    '(.projects[] | select(.app_name == $APP_NAME and .environment_type == $ENV_NAME)) .project_path = $PROJECT_PATH' \
    "$PROJECTS_JSON" > "$PROJECTS_JSON.tmp" && mv "$PROJECTS_JSON.tmp" "$PROJECTS_JSON"

# 📌 Verify update success
UPDATED_PATH=$(jq -r --arg APP_NAME "$APP_NAME" --arg ENV_NAME "$ENV_NAME" \
    '(.projects[] | select(.app_name == $APP_NAME and .environment_type == $ENV_NAME)) | .project_path' \
    "$PROJECTS_JSON")
if [[ "$UPDATED_PATH" != "$PROJECT_PATH" && "$UPDATED_PATH" != "$EXPECTED_PROJECT_PATH" ]]; then
    echo "❌ Error: Failed to update 'acquia-projects.json'."
    exit 1
fi


echo "✅ Cloning and configuration complete. You can access the project at: $EXPECTED_PROJECT_PATH"