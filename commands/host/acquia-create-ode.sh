#!/bin/bash

# Script to automate the creation of an Acquia Cloud On-Demand Environment (ODE)
#
# Usage: ./create_ode.sh <applicationUuid> <newOdeName> <sourceEnvironmentUuid> <gitRef> <label>
#
# Example:
# ./create_ode.sh "a1b2c3d4-e5f6-7890-1234-567890abcdef" "my-new-ode" "s1t2a3g4-e5f6-7890-1234-567890abcdef" "refs/heads/feature-branch" "My New ODE for Feature X"
#
# Prerequisites:
# 1. Acquia CLI (acli) must be installed and configured.
#    See: https://docs.acquia.com/acquia-cli/install/
# 2. You must be authenticated with acli and have the necessary permissions.

# --- Configuration ---
# You can set default values here if you prefer, but command-line arguments are recommended for flexibility.
# DEFAULT_APP_UUID=""
# DEFAULT_ODE_NAME=""
# DEFAULT_SOURCE_ENV_UUID="" # e.g., UUID of your 'dev', 'stage', or another ODE
# DEFAULT_GIT_REF="refs/heads/main" # e.g., refs/heads/main, refs/tags/v1.0.0
# DEFAULT_LABEL=""

# --- Script Logic ---

# Check if acli is installed
if ! command -v acli &> /dev/null
then
    echo "ERROR: Acquia CLI (acli) could not be found. Please install and configure it."
    echo "See: https://docs.acquia.com/acquia-cli/install/"
    exit 1
fi

# Check for the correct number of arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <applicationUuid> <newOdeName> <sourceEnvironmentUuid> <gitRef> <label>"
    echo "Example:"
    echo "$0 \"a1b2c3d4-e5f6-7890-1234-567890abcdef\" \"my-new-ode\" \"s1t2a3g4-e5f6-7890-1234-567890abcdef\" \"refs/heads/feature-branch\" \"My New ODE for Feature X\""
    exit 1
fi

# 📌 Paths
GLOBAL_CONFIG="$HOME/.ddev/global_config.yaml"
PROJECTS_JSON="$HOME/.ddev/acquia-projects.json"
SITES_PATH="docroot/sites"
LOCAL_SITE_YML="drush/sites/loc.site.yml"
SETTINGS_FILE="$SITES_PATH/$DB_NAME/settings.php"

# 📌 Variables
UUID="ddbb7077-3843-4873-86dd-28fde7046bfd"
SITE_NAME=$1
DB_NAME=""
APP_NAME=""
ENVIRONMENT_ID=""
ENVIRONMENT_TYPE=""
TOKEN=""

# Assign arguments to variables for clarity
APP_UUID="$1"
NEW_ODE_NAME="$2"
SOURCE_ENV_UUID="$3"
GIT_REF="$4"
LABEL="$5"

# Check if acli is installed
if ! command -v acli &> /dev/null
then
    echo "ERROR: Acquia CLI (acli) could not be found. Please install and configure it."
    echo "you need to have acli installed in order to proceed"
    echo "See: https://docs.acquia.com/acquia-cli/install/"
    exit 1
fi

#CREATE THE PROJECT FOLDER FUNCTION AND ADD SETTINGS.PHP
function create_folder(){
    echo "Creating the project folder..."
    mkdir $SITES_PATH/$DB_NAME
    cd $SITES_PATH/$DB_NAME
    touch settings.php 
}

#CREATE A DB IN ACQUIA
function create_db{
if command -v jq &> /dev/null; then
  echo ""
        echo "--- Attempting Database Creation ---"
        echo "Attempting to parse new environment UUID using jq..."
        
        # Try to extract the new environment UUID. Common keys are 'uuid', 'id', or 'environment_uuid'.
        # This parsing logic might need adjustment based on the actual JSON structure of acli's response.
        NEW_ENV_UUID=$(echo "$ODE_CREATE_OUTPUT" | jq -r '.uuid // .id // .environment_uuid // .resource.uuid // .resource.id // empty')

        if [ -n "$NEW_ENV_UUID" ] && [ "$NEW_ENV_UUID" != "null" ] && [ "$NEW_ENV_UUID" != "empty" ]; then
            echo "Successfully parsed new Environment UUID: $NEW_ENV_UUID"
            # Use the NEW_ODE_NAME as the database name, as implied by the user's request structure.
            # You might want to make this more specific, e.g., "${NEW_ODE_NAME}_db"
            DB_NAME="$NEW_ODE_NAME" 
            
            echo "Attempting to create database '$DB_NAME' for Application '$APP_UUID' in Environment '$NEW_ENV_UUID'..."

            # Execute the acli command for database creation and capture its output
            # Command: acli api:applications:database-create [applicationUuid] [environmentUuid] [databaseName]
            DB_CREATE_OUTPUT=$(acli api:applications:database-create "$APP_UUID" "$NEW_ENV_UUID" "$DB_NAME" 2>&1)
            ACLI_DB_CREATE_STATUS=$?

            if [ $ACLI_DB_CREATE_STATUS -eq 0 ]; then
                echo "SUCCESS: Database '$DB_NAME' creation command sent successfully."
                echo "Database Creation Raw Response:"
                echo "$DB_CREATE_OUTPUT"
                
                echo "Appending database creation output to $SETTINGS_FILE..."
                # Create or append to the settings file
                echo "" >> "$SETTINGS_FILE" # Add a newline for separation if file exists
                echo "// --- Acquia ODE Database Creation Output ---" >> "$SETTINGS_FILE"
                echo "// Timestamp: $(date)" >> "$SETTINGS_FILE"
                echo "// Application UUID: $APP_UUID" >> "$SETTINGS_FILE"
                echo "// Environment UUID (New ODE): $NEW_ENV_UUID" >> "$SETTINGS_FILE"
                echo "// Database Name: $DB_NAME" >> "$SETTINGS_FILE"
                echo "// Raw Output from 'acli api:applications:database-create':" >> "$SETTINGS_FILE"
                echo "$DB_CREATE_OUTPUT" >> "$SETTINGS_FILE"
                echo "// --- End of Acquia ODE Database Creation Output ---" >> "$SETTINGS_FILE"
                echo "Output appended to $SETTINGS_FILE."
            else
                echo "ERROR: Database '$DB_NAME' creation command failed with status $ACLI_DB_CREATE_STATUS."
                echo "Error details:"
                echo "$DB_CREATE_OUTPUT"
            fi
        else
            echo "WARNING: Could not parse new Environment UUID from ODE creation response using jq."
            echo "ODE Creation Response was: $ODE_CREATE_OUTPUT"
            echo "Skipping database creation. You may need to create the database manually once the ODE is provisioned and its UUID is known."
        fi
    else
        echo ""
        echo "WARNING: 'jq' command not found. 'jq' is required to automatically parse the new Environment UUID for database creation."
        echo "Skipping database creation. Please install 'jq' (e.g., 'sudo apt-get install jq' or 'brew install jq')"
        echo "or create the database manually once the ODE is provisioned and its UUID is known."
    fi
    # --- End of database creation attempt ---

    echo ""
    echo "You can check the ODE status in the Acquia Cloud UI or using 'acli api:environments:list $APP_UUID'."
else
    echo ""
    echo "ERROR: ODE creation command failed. Exit status: $ACLI_ODE_CREATE_STATUS"
    echo "Output:"
    echo "$ODE_CREATE_OUTPUT"
    echo "Ensure your Application UUID, Source Environment UUID, and Git Reference are correct and you have permissions."
    exit 1
fi

}

#CREATE THE DB IN ACQUIA USING(either of these): 
    #acli api:applications:database-create [--task-wait] [--] <applicationUuid> <name>
    #acli api:applications:database-create da1c0a8e-ff69-45db-88fc-acd6d2affbb7 "my_db_name"
    #acli api:applications:database-create myapp "my_db_name"
#CREATE THE SETTINGS.PHP AND ADD THE DB CONFIGURATION, IT SHOULD LOOK LIKE:
# if (file_exists('/var/www/site-php')) {
  #require '/var/www/site-php/millercoorsd8/newode-settings.inc';
#}\
#   $settings['install_profile'] = 'millercoors';

#$config_directories = array(
  ##CONFIG_SYNC_DIRECTORY => $app_root . '/../config/' . basename($site_path),
#);


#CREATE THE ODE:
function create_ode {
    echo "--- Starting ODE Creation ---"
    echo "Application UUID: $APP_UUID"
    echo "New ODE Name: $NEW_ODE_NAME"
    echo "Source Environment UUID: $SOURCE_ENV_UUID"
    echo "Git Reference (Branch/Tag): $GIT_REF"
    echo "Label: $LABEL"
    echo "-----------------------------"

    # Confirm before proceeding (optional, uncomment to enable)
    # read -p "Are you sure you want to create this ODE? (y/N): " confirmation
    # if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    #     echo "ODE creation cancelled by user."
    #     exit 0
    # fi

    echo "Attempting to create ODE..."

    # Execute the acli command for ODE creation and capture its output (stdout and stderr)
    # The command structure is: acli api:applications:environment-create [applicationUuid] [name] [sourceEnvironmentUuid] [gitRef] [label]
    ODE_CREATE_OUTPUT=$(acli api:applications:environment-create "$APP_UUID" "$NEW_ODE_NAME" "$SOURCE_ENV_UUID" "$GIT_REF" "$LABEL" 2>&1)
    ACLI_ODE_CREATE_STATUS=$?

    # Check the exit status of the ODE creation command
    if [ $ACLI_ODE_CREATE_STATUS -eq 0 ]; then
    echo ""
    echo "SUCCESS: ODE creation command sent successfully for '$NEW_ODE_NAME'."
    echo "ODE Creation Raw Response (for debugging, can be removed):"
    echo "$ODE_CREATE_OUTPUT"
    echo "It may take a few minutes for the ODE to become fully available."

    # --- Attempt to create database for the new ODE ---
    # Note: This requires 'jq' to parse the new environment UUID from the ODE creation response.
    # The 'environment-create' command is asynchronous; the environment might not be ready immediately for database operations.
    # This part assumes the ODE creation response (ODE_CREATE_OUTPUT) is JSON and contains the new environment's UUID.

}



create_folder
create_ode
create_db

/bin/bash