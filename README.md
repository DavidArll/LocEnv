# Acquia DDEV Dashboard

## Overview

The Acquia DDEV Dashboard is a graphical desktop application designed to simplify interactions with custom DDEV commands tailored for Acquia Cloud projects. It provides a user-friendly interface for common development tasks such as synchronizing environments, cloning projects, listing multisite instances, and managing individual sites.

The application is built using Python, Flask (for the web server backend), and Pywebview (to render the Flask app in a native desktop window).

## Features

-   **List Acquia Environments:** Displays a list of Acquia environments/projects defined in `$HOME/.ddev/acquia-projects.json`.
-   **Sync Environments List:** Fetches the latest list of applications from Acquia Cloud using `ddev acquia-sync-envs`.
-   **Clone/Update Full Environments:** Clones or updates entire Acquia project environments locally using `ddev acquia-clone <env_name>`.
-   **Manage Individual Sites (Multisite):**
    -   Lists individual sites within a cloned project environment, combining information from `ddev acquia-get-sites <env_id>` and local filesystem/configuration.
    -   **Clone Site:** Clones a specific remote site (database and files) into the local DDEV project using `ddev acquia-clone-site <site_name>`.
    -   **Re-sync Site:** Re-runs `ddev acquia-clone-site <site_name>` for an already cloned site, allowing users to respond to script prompts for pulling database/files.
-   **Real-time Feedback:** Shows command output (stdout/stderr) directly in the UI.
-   **Error Handling:** Provides informative error messages for configuration issues or command failures.

## Prerequisites

1.  **DDEV:**
    -   Must be installed and accessible in your system's PATH.
    -   Ensure DDEV is up-to-date.
2.  **Acquia API Credentials:**
    -   Your Acquia API Key and Secret must be configured in DDEV's global configuration file: `$HOME/.ddev/global_config.yaml`.
    -   The required keys are:
        -   `acquia_api_key: YOUR_KEY_HERE`
        -   `acquia_api_secret: YOUR_SECRET_HERE`
    -   *(Note: While `ACQUIA_PROJECT_ID` is often used with Acquia CLI, this dashboard typically works at an account level for listing projects initially, and then project-specifically once cloned. The `acquia-sync-envs` command handles project discovery.)*
3.  **Custom DDEV Commands:**
    -   The following custom DDEV host commands (shell scripts) must be installed and functional within your DDEV environment (e.g., in `.ddev/host_commands` or your DDEV global commands directory):
        -   `ddev acquia-sync-envs`: Synchronizes the list of your Acquia applications and environments, creating/updating `$HOME/.ddev/acquia-projects.json`.
        -   `ddev acquia-clone <env_name>`: Clones an entire Acquia application environment (code, database, files for default site).
        -   `ddev acquia-get-sites <env_id>`: Lists all site (database) names for a given Acquia environment ID (e.g., "dev", "test", "prod").
            -   **Important:** For best results with the dashboard, this script should output a simple JSON array of strings, e.g., `["site1", "site2"]`.
        -   `ddev acquia-clone-site <site_name>`: Clones a specific site (database and files) from Acquia Cloud into the current DDEV project. This script is also used for re-syncing, where it typically prompts the user to confirm database and/or file sync.
    -   **Script Interactivity Note:**
        -   The `acquia-get-sites` command, if interactive, might not work as expected with the dashboard. It should ideally be non-interactive for listing sites.
        -   The `acquia-clone-site` command (when used for re-syncing) is expected to be interactive (prompting for DB/files sync). The dashboard will display this script's output, including any prompts, allowing the user to see what's required. For a fully automated experience, these scripts would need to support non-interactive flags, which the dashboard could then utilize (this is a potential future enhancement).

## Installation and Setup (Running from Source)

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/your-username/acquia-ddev-dashboard.git # Replace with actual URL
    cd acquia-ddev-dashboard
    ```
2.  **Create and activate a virtual environment:**
    ```bash
    python3 -m venv venv
    # On macOS/Linux:
    source venv/bin/activate
    # On Windows:
    # venv\Scripts\activate
    ```
3.  **Install dependencies:**
    ```bash
    pip install -r acquia_ddev_dashboard/requirements.txt
    ```
4.  **Run the application:**
    ```bash
    python acquia_ddev_dashboard/main.py
    ```

## Building from Source (Creating a Desktop Application)

You can package the Acquia DDEV Dashboard into a standalone desktop application using PyInstaller.

1.  **Ensure all dependencies, including `pyinstaller`, are installed:**
    ```bash
    pip install -r acquia_ddev_dashboard/requirements.txt 
    ```
    *(If you haven't added `pyinstaller` to `requirements.txt` yet, do so or run `pip install pyinstaller`)*.

2.  **Navigate to the root directory of the project** (where `acquia_ddev_dashboard.spec` is located).

3.  **Run PyInstaller with the spec file:**
    ```bash
    pyinstaller acquia_ddev_dashboard.spec
    ```

4.  **Find the packaged application:**
    -   The bundled application will be located in the `dist/acquia_ddev_dashboard_dist` directory (or `dist/acquia_ddev_dashboard` on some OS if `COLLECT` name is just `acquia_ddev_dashboard`).

## How to Use

1.  **Main Environments View:**
    -   On launch, the dashboard attempts to load environments from `$HOME/.ddev/acquia-projects.json`.
    -   **Refresh Environments List:** Click this to update the list from `acquia-projects.json`.
    -   **Sync Acquia Environments with Cloud:** Click this to run `ddev acquia-sync-envs`. This updates `acquia-projects.json` with the latest from your Acquia Cloud account. The list will refresh automatically after this operation.
    -   For each environment:
        -   **Status:** Shows if the project directory exists locally ("Cloned" or "Not Cloned").
        -   **Clone/Update Environment:**
            -   If "Not Cloned," click "Clone Environment" to run `ddev acquia-clone <env_name>`.
            -   If "Cloned," click "Update Environment" to re-run `ddev acquia-clone <env_name>` (which typically handles updates or re-sync prompts).
        -   **Manage Sites:** If "Cloned," click this to navigate to the site management view for that environment.

2.  **Manage Sites View:**
    -   Accessed by clicking "Manage Sites" for a cloned environment.
    -   Displays the project context (app name, environment type).
    -   **Refresh Sites List:** Click to re-fetch site information.
    -   The table lists sites with their status:
        -   **Remote Status:** Whether the site (database name) is reported by `ddev acquia-get-sites`.
        -   **Local DB Status:** Whether the site's database is listed as cloned in `acquia-projects.json`.
        -   **Local Files Status:** Whether the site's directory (`docroot/sites/<site_name>`) exists.
    -   For each site:
        -   **Clone Site:** If the site is remote but not fully local, click to run `ddev acquia-clone-site <site_name>` to pull its database and files.
        -   **Re-sync Site:** If the site is remote and already local, click to re-run `ddev acquia-clone-site <site_name>`. This is useful for pulling fresh copies of the database or files. The output from the script, including any prompts, will be shown.

**Status Messages and Output:**
-   Most operations will display status messages at the top of the relevant section.
-   Command output (stdout/stderr) from DDEV commands is often shown in a `<pre>` block within these messages, providing context on what occurred. For re-sync operations, this output is crucial for responding to script prompts.
-   Check for error messages if operations fail. They may guide you on missing configurations or issues with the DDEV commands.

## Running Tests

Unit tests for utility functions can be run from the project's root directory:

```bash
python -m unittest acquia_ddev_dashboard/test_utils.py
```
Or, if you are in the `acquia_ddev_dashboard` directory:
```bash
python -m unittest test_utils.py
```
