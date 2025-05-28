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

# 📌 Variables
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

# Execute the acli command
# The command structure is: acli api:applications:environment-create [applicationUuid] [name] [sourceEnvironmentUuid] [gitRef] [label]
acli api:applications:environment-create "$APP_UUID" "$NEW_ODE_NAME" "$SOURCE_ENV_UUID" "$GIT_REF" "$LABEL"

# Check the exit status of the acli command
if [ $? -eq 0 ]; then
    echo ""
    echo "SUCCESS: ODE creation command sent successfully for '$NEW_ODE_NAME'."
    echo "It may take a few minutes for the ODE to become fully available."
    echo "You can check the status in the Acquia Cloud UI or using 'acli api:environments:list $APP_UUID'."
else
    echo ""
    echo "ERROR: ODE creation command failed. Please check the output above for details."
    echo "Ensure your Application UUID, Source Environment UUID, and Git Reference are correct and you have permissions."
    exit 1
fi

echo "--- ODE Creation Process Initiated ---"

exit 0