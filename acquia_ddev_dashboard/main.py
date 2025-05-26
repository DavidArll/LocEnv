import webview # For creating a native desktop window
from flask import Flask, render_template, jsonify # Flask for the web server backend
import threading # To run Flask in a separate thread from pywebview
import subprocess # For running DDEV commands
import os # For path operations
import json # For JSON parsing
import logging # For application logging
#from . import utils # Utility functions for DDEV interactions
import utils


# Configure basic logging for the application
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(module)s - %(message)s')

app = Flask(__name__)

# --- Context Processor for Global Config ---
@app.context_processor
def inject_global_config_status():
    """
    Injects the status of Acquia configuration into templates.
    Checks if Acquia API key and secret are present in the DDEV global config.
    This is used to display a warning in the UI if credentials are missing.
    """
    acquia_config_missing = True
    ddev_global_config = utils.read_ddev_global_config() # Reads $HOME/.ddev/global_config.yaml
    
    if ddev_global_config and isinstance(ddev_global_config, dict) and 'error' in ddev_global_config:
        # Log the error details if the config file couldn't be read or parsed.
        logging.warning(f"Context Processor: Error reading DDEV global config: {ddev_global_config.get('details', ddev_global_config['error'])}. Path: {ddev_global_config.get('path', 'N/A')}")
        # For UI purposes, if the config is errored, assume keys are missing.
        acquia_config_missing = True 
    elif ddev_global_config: # Config was read successfully
        # Check for specific Acquia API credentials.
        api_key = ddev_global_config.get('acquia_api_key')
        api_secret = ddev_global_config.get('acquia_api_secret')
        if api_key and api_secret:
            acquia_config_missing = False # Credentials found.
    else: # Config file might be empty or not contain expected structure, but no direct read error.
        acquia_config_missing = True # Assume missing if config is empty or unreadable.
        
    return dict(acquia_config_missing=acquia_config_missing)

@app.route('/')
def index():
    """Serves the main dashboard page."""
    return render_template('index.html')

@app.route('/api/environments')
def get_environments():
    """
    API endpoint to list Acquia environments.
    Reads from `$HOME/.ddev/acquia-projects.json`.
    Augments data with local cloned status.
    """
    data = utils.read_acquia_projects_json() # Reads $HOME/.ddev/acquia-projects.json
    
    # Handle cases where reading acquia-projects.json failed or returned error data.
    if not data or (isinstance(data, dict) and 'error' in data):
        user_message = "Acquia projects JSON file ($HOME/.ddev/acquia-projects.json) not found or is invalid."
        log_message = user_message # Base log message
        if isinstance(data, dict) and 'error' in data:
            # More specific message if utils.py provided error details.
            user_message = f"Error with acquia-projects.json: {data.get('details', data['error'])}. Path: {data.get('path', 'N/A')}"
            if data['error'] == 'ACQUIA_PROJECTS_JSON_NOT_FOUND':
                user_message += " Please run 'ddev acquia-sync-envs' to generate it."
            log_message = f"Error reading acquia-projects.json: {data.get('details', data['error'])}. Path: {data.get('path', 'N/A')}"
        logging.error(f"[API /api/environments] {log_message}")
        return jsonify({'status': 'error', 'message': user_message, 'environments': []}), 500

    # Ensure data['projects'] exists; an empty file might result in data being None or an empty dict.
    acquia_projects_list = data.get('projects', []) if isinstance(data, dict) else []
    
    environments_data = []
    for project in acquia_projects_list:
        project_path = project.get('project_path')
        environments_data.append({
            **project, # Include all original project data from the JSON file.
            'local_path': project_path, # The path where the project is (or would be) cloned.
            'cloned_status': utils.check_path_exists(project_path) # True if directory exists.
        })
        
    return jsonify({'environments': environments_data})

@app.route('/api/sync-environments', methods=['POST'])
def sync_environments():
    """
    API endpoint to trigger `ddev acquia-sync-envs`.
    This command updates `$HOME/.ddev/acquia-projects.json`.
    """
    if not utils.find_ddev(): # Check if 'ddev' command is available.
        logging.error("[API /api/sync-environments] DDEV command not found.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found. Please ensure DDEV is installed and in your PATH.'}), 500

    ddev_command = ['ddev', 'acquia-sync-envs']
    logging.info(f"[API /api/sync-environments] Executing command: {' '.join(ddev_command)}")
    try:
        # Execute the DDEV command.
        process = subprocess.run(ddev_command, capture_output=True, text=True, check=False)
        
        if process.returncode == 0: # Command was successful.
            logging.info(f"[API /api/sync-environments] Command '{' '.join(ddev_command)}' successful. Output: {process.stdout[:200]}...") # Log snippet of output
            return jsonify({
                'status': 'success', 
                'message': 'Environments synced successfully with Acquia Cloud.', 
                'output': process.stdout or "Sync command executed successfully."
            })
        else: # Command failed.
            logging.error(f"[API /api/sync-environments] Command '{' '.join(ddev_command)}' failed. Exit Code: {process.returncode}. Stderr: {process.stderr}. Stdout: {process.stdout}")
            return jsonify({
                'status': 'error',
                'message': f"Sync command ('ddev acquia-sync-envs') failed with exit code {process.returncode}.",
                'output': process.stderr or "No standard error output from command.", 
                'stdout': process.stdout or "No standard output from command."
            }), 500 # 500 for server-side command failure
    except FileNotFoundError: # DDEV command itself not found during execution attempt
        logging.error(f"[API /api/sync-environments] DDEV command not found when trying to execute: {' '.join(ddev_command)}.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found. Please ensure DDEV is installed and in your PATH.'}), 500
    except Exception as e: # Catch any other unexpected errors during subprocess execution.
        logging.error(f"[API /api/sync-environments] An exception occurred during '{' '.join(ddev_command)}': {str(e)}")
        return jsonify({'status': 'error', 'message': f"An unexpected error occurred: {str(e)}", 'output': str(e)}), 500

def start_flask():
    """Starts the Flask web server."""
    # debug=False is important for pywebview to work correctly with Flask's reloader.
    # Use a specific host and port for consistency.
    app.run(host='127.0.0.1', port=5000, debug=False)

def get_project_details(app_name, env_type):
    """
    Helper function to retrieve specific project details from `acquia-projects.json`.
    
    Args:
        app_name (str): The application name (e.g., 'projectname').
        env_type (str): The environment type (e.g., 'dev', 'test').
        
    Returns:
        dict: The project's details if found, or an error dictionary if not found/error.
              Returns None if acquia-projects.json itself is missing/invalid at a higher level.
    """
    projects_data = utils.read_acquia_projects_json()
    
    # Handle if acquia-projects.json itself is missing or invalid.
    if not projects_data or (isinstance(projects_data, dict) and 'error' in projects_data):
        # Log this specific issue if it's an error dictionary from utils
        if isinstance(projects_data, dict) and 'error' in projects_data:
             logging.error(f"[Helper get_project_details] Failed to read acquia-projects.json: {projects_data.get('details', projects_data['error'])}")
        return projects_data # Return the error dict or None as is
        
    all_projects = projects_data.get('projects', [])
    for project in all_projects:
        # Match project by application name and environment type.
        if project.get('app_name') == app_name and project.get('environment_type') == env_type:
            return project # Return the found project's dictionary.
            
    # If no matching project is found.
    logging.warning(f"[Helper get_project_details] Project {app_name}/{env_type} not found in acquia-projects.json.")
    return {'error': 'PROJECT_NOT_FOUND_IN_JSON', 'app_name': app_name, 'env_type': env_type}

@app.route('/project/<app_name>/<env_type>/sites')
def project_sites_view(app_name, env_type):
    """
    Serves the page for managing individual sites within a cloned project environment.
    Validates project existence and path before rendering.
    """
    project_details = get_project_details(app_name, env_type)
    
    # Handle if project details could not be fetched or indicate an error (e.g., acquia-projects.json missing).
    if not project_details or (isinstance(project_details, dict) and 'error' in project_details):
        error_message = f"Project {app_name} ({env_type}) not found or configuration is invalid."
        if isinstance(project_details, dict) and 'error' in project_details:
            error_message = f"Failed to get project details for {app_name} ({env_type}): {project_details.get('details', project_details.get('error', 'Unknown error'))}"
        logging.error(f"[View /project/.../sites] {error_message}")
        # TODO: Future: Render a user-friendly error page template instead of a simple string.
        return f"Error displaying site management: {error_message}", 404 # 404 indicates resource not found.
    
    project_path = project_details.get('project_path')
    # Check if the project's local directory exists.
    if not project_path or not utils.check_path_exists(project_path):
        error_message = f"Project path '{project_path}' for {app_name} ({env_type}) does not exist locally. Please clone the environment first."
        logging.error(f"[View /project/.../sites] {error_message}")
        return f"Error displaying site management: {error_message}", 404

    return render_template('project_sites.html',
                           app_name=app_name,
                           env_type=env_type,
                           project_path=project_path,
                           # Use 'environment_id' if present, otherwise fallback to 'env_type' for ddev acquia-get-sites.
                           environment_id=project_details.get('environment_id', env_type))

@app.route('/api/project/<app_name>/<env_type>/list-sites')
def api_list_project_sites(app_name, env_type):
    """
    API endpoint to list sites for a specific project environment.
    Combines remote sites (from `ddev acquia-get-sites`) and local site status.
    """
    project_details = get_project_details(app_name, env_type)
    
    # Handle error if project details cannot be loaded (e.g. acquia-projects.json error).
    if not project_details or (isinstance(project_details, dict) and 'error' in project_details):
        error_message = f"Project {app_name} ({env_type}) details not found or config error."
        if isinstance(project_details, dict) and 'error' in project_details:
             error_message = f"Failed to get project details for {app_name} ({env_type}): {project_details.get('details', project_details['error'])}"
        logging.error(f"[API /api/.../list-sites] {error_message}")
        return jsonify({'status': 'error', 'message': error_message}), 404

    project_path = project_details.get('project_path')
    environment_id = project_details.get('environment_id', env_type) # Fallback to env_type for env ID.

    # Ensure the local project path exists.
    if not project_path or not utils.check_path_exists(project_path):
        logging.error(f"[API /api/.../list-sites] Project path '{project_path}' not found for {app_name}/{env_type}.")
        return jsonify({'status': 'error', 'message': f"Project path '{project_path}' not found. Ensure the environment is cloned."}), 404

    if not utils.find_ddev(): # Check for DDEV.
        logging.error("[API /api/.../list-sites] DDEV command not found.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500

    # --- Step 1: Get remote sites using `ddev acquia-get-sites` ---
    remote_sites_list = []
    ddev_get_sites_command = ['ddev', 'acquia-get-sites', environment_id]
    logging.info(f"[API /api/.../list-sites] Executing: {' '.join(ddev_get_sites_command)} in {project_path}")
    try:
        process = subprocess.run(ddev_get_sites_command, cwd=project_path, capture_output=True, text=True, check=False)
        if process.returncode == 0: # Command successful.
            raw_output = process.stdout.strip()
            if raw_output:
                try:
                    parsed_sites = json.loads(raw_output)
                    if isinstance(parsed_sites, list): # Expected: list of site strings.
                        remote_sites_list = [str(site) for site in parsed_sites]
                    else:
                        logging.warning(f"[API /api/.../list-sites] Unexpected JSON format from {' '.join(ddev_get_sites_command)}: {raw_output}")
                except json.JSONDecodeError as e:
                    logging.error(f"[API /api/.../list-sites] JSONDecodeError from {' '.join(ddev_get_sites_command)} for {app_name}/{env_type}: {e}. Output: {raw_output}")
                    # Return error as this step is crucial for listing sites accurately.
                    return jsonify({'status': 'error', 'message': f"Could not parse site list from 'ddev acquia-get-sites': Invalid JSON response. Output: {raw_output}", 'output': raw_output}), 500
            logging.info(f"[API /api/.../list-sites] 'ddev acquia-get-sites' successful. Remote sites: {len(remote_sites_list)}")
        else: # `ddev acquia-get-sites` command failed.
            logging.error(f"[API /api/.../list-sites] Command '{' '.join(ddev_get_sites_command)}' failed. Exit: {process.returncode}. Stderr: {process.stderr}, Stdout: {process.stdout}")
            return jsonify({
                'status': 'error',
                'message': f"Failed to fetch remote sites using 'ddev acquia-get-sites {environment_id}'. The command failed.",
                'output': process.stderr or "No standard error output.",
                'stdout': process.stdout or "No standard output."
            }), 500
    except FileNotFoundError:
        logging.error(f"[API /api/.../list-sites] DDEV command not found during execution: {' '.join(ddev_get_sites_command)}.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500
    except Exception as e:
        logging.error(f"[API /api/.../list-sites] Exception running {' '.join(ddev_get_sites_command)}: {e}")
        return jsonify({'status': 'error', 'message': f"An unexpected error occurred while fetching remote sites: {str(e)}", 'output': str(e)}), 500

    # --- Step 2: Get local site information ---
    # Databases listed as cloned in acquia-projects.json for this specific project.
    local_cloned_databases = set(project_details.get('databases', []))
    
    # Directories existing under `<project_path>/docroot/sites/`
    local_site_directories = set()
    docroot_sites_path = os.path.join(project_path, 'docroot', 'sites')
    if utils.check_path_exists(docroot_sites_path):
        try:
            for item_name in os.listdir(docroot_sites_path):
                item_full_path = os.path.join(docroot_sites_path, item_name)
                # Consider only directories and exclude common non-site Drupal directories.
                if os.path.isdir(item_full_path) and item_name not in ['default', 'all', 'example.sites.php']:
                    local_site_directories.add(item_name)
        except OSError as e: # Handle potential permission errors or other OS issues.
            logging.error(f"[API /api/.../list-sites] Error listing site directories in {docroot_sites_path}: {e}")
            # Depending on desired behavior, could return error or proceed with empty local_site_directories.

    # --- Step 3: Consolidate and return site list ---
    # Combine all unique site names from remote, cloned DBs, and local directories.
    all_discovered_site_names = set(remote_sites_list) | local_cloned_databases | local_site_directories
    
    consolidated_site_list = []
    for site_name in sorted(list(all_discovered_site_names)):
        is_remote = site_name in remote_sites_list
        db_cloned = site_name in local_cloned_databases
        files_exist = site_name in local_site_directories
        
        # A site is considered "fully local" if both its database is marked as cloned
        # AND its specific site directory exists.
        is_fully_local = db_cloned and files_exist

        consolidated_site_list.append({
            'site_name': site_name,
            'is_remote': is_remote,
            'is_local': is_fully_local, # True if both DB and files are confirmed local.
            'status_db': 'Cloned' if db_cloned else 'Not Cloned',
            'status_files': 'Exists' if files_exist else 'Not Present'
        })
        
    return jsonify({'sites': consolidated_site_list})

@app.route('/api/project/<app_name>/<env_type>/clone-site/<site_name>', methods=['POST'])
def api_clone_project_site(app_name, env_type, site_name):
    """
    API endpoint to clone a specific site (database and files) for a project environment
    using `ddev acquia-clone-site <site_name>`.
    """
    project_details = get_project_details(app_name, env_type)
    project_details = get_project_details(app_name, env_type)
    # Validate project details and path.
    if not project_details or (isinstance(project_details, dict) and 'error' in project_details):
        error_message = f"Project {app_name} ({env_type}) details error for clone-site."
        if isinstance(project_details, dict): error_message += f" Details: {project_details.get('details', project_details['error'])}"
        logging.error(f"[API /.../clone-site] {error_message}")
        return jsonify({'status': 'error', 'message': error_message}), 404

    project_path = project_details.get('project_path')
    if not project_path or not utils.check_path_exists(project_path):
        logging.error(f"[API /.../clone-site] Project path '{project_path}' not found for {app_name}/{env_type}.")
        return jsonify({'status': 'error', 'message': f"Project path for {app_name} ({env_type}) not found or invalid: {project_path}"}), 404

    if not utils.find_ddev(): # Check for DDEV.
        logging.error("[API /.../clone-site] DDEV command not found.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500

    if not site_name: # Ensure site_name is provided.
        return jsonify({'status': 'error', 'message': 'Site name parameter is required.'}), 400

    ddev_command = ['ddev', 'acquia-clone-site', site_name]
    logging.info(f"[API /.../clone-site] Executing: {' '.join(ddev_command)} in {project_path} for site {site_name}")
    try:
        process = subprocess.run(ddev_command, cwd=project_path, capture_output=True, text=True, check=False)
        if process.returncode == 0: # Command successful.
            logging.info(f"[API /.../clone-site] Command '{' '.join(ddev_command)}' successful for {site_name}. Output: {process.stdout[:200]}...")
            return jsonify({
                'status': 'success', 
                'message': f"Site '{site_name}' cloned/updated successfully.", 
                'output': process.stdout or f"Site '{site_name}' processed."
            })
        else: # Command failed.
            logging.error(f"[API /.../clone-site] Command '{' '.join(ddev_command)}' failed for {site_name}. Exit: {process.returncode}. Stderr: {process.stderr}, Stdout: {process.stdout}")
            return jsonify({
                'status': 'error',
                'message': f"Failed to clone/update site '{site_name}'. DDEV command exited with code {process.returncode}.",
                'output': process.stderr or "No standard error output.",
                'stdout': process.stdout or "No standard output."
            }), 500
    except FileNotFoundError:
        logging.error(f"[API /.../clone-site] DDEV command not found during execution: {' '.join(ddev_command)}.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500
    except Exception as e:
        logging.error(f"[API /.../clone-site] Exception during '{' '.join(ddev_command)}' for {site_name}: {str(e)}")
        return jsonify({'status': 'error', 'message': f"An unexpected error occurred: {str(e)}", 'output': str(e)}), 500

@app.route('/api/project/<app_name>/<env_type>/resync-site/<site_name>', methods=['POST'])
def api_resync_project_site(app_name, env_type, site_name):
    """
    API endpoint to re-sync a specific site. This typically re-runs the
    `ddev acquia-clone-site <site_name>` command, which should handle
    prompts for already cloned sites.
    """
    project_details = get_project_details(app_name, env_type)
    # Validate project details and path.
    if not project_details or (isinstance(project_details, dict) and 'error' in project_details):
        error_message = f"Project {app_name} ({env_type}) details error for re-sync."
        if isinstance(project_details, dict): error_message += f" Details: {project_details.get('details', project_details['error'])}"
        logging.error(f"[API /.../resync-site] {error_message}")
        return jsonify({'status': 'error', 'message': error_message}), 404

    project_path = project_details.get('project_path')
    if not project_path or not utils.check_path_exists(project_path):
        logging.error(f"[API /.../resync-site] Project path '{project_path}' not found for {app_name}/{env_type}.")
        return jsonify({'status': 'error', 'message': f"Project path for {app_name} ({env_type}) not found or invalid: {project_path}"}), 404

    if not utils.find_ddev(): # Check for DDEV.
        logging.error("[API /.../resync-site] DDEV command not found.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500

    if not site_name: # Ensure site_name is provided.
        return jsonify({'status': 'error', 'message': 'Site name parameter is required.'}), 400

    ddev_command = ['ddev', 'acquia-clone-site', site_name] # Same command for re-sync.
    logging.info(f"[API /.../resync-site] Executing for re-sync: {' '.join(ddev_command)} in {project_path} for site {site_name}")
    try:
        process = subprocess.run(ddev_command, cwd=project_path, capture_output=True, text=True, check=False)
        
        # The `acquia-clone-site` script might exit 0 on success or non-0 if user aborts a prompt.
        # Output is key here.
        if process.returncode == 0:
            logging.info(f"[API /.../resync-site] Re-sync command '{' '.join(ddev_command)}' successful for {site_name}. Output: {process.stdout[:200]}...")
            return jsonify({
                'status': 'success',
                'message': f"Re-sync process for '{site_name}' seems to have completed successfully. Review output for details.",
                'output': process.stdout or f"Re-sync for '{site_name}' completed."
            })
        else: # Non-zero exit code. Could be an error or user cancellation during prompts.
            logging.warning(f"[API /.../resync-site] Re-sync command '{' '.join(ddev_command)}' for {site_name} exited with code {process.returncode}. Output: {(process.stderr or process.stdout)[:200]}...")
            return jsonify({
                'status': 'success_with_prompts', # Frontend should display output prominently.
                'message': f"Re-sync process for '{site_name}' completed with interactions or potential issues (exit code {process.returncode}). Please review the output.",
                'output': process.stdout or process.stderr or "No output from command.", # Prioritize stdout for prompts.
                'stdout': process.stdout,
                'stderr': process.stderr 
            })
    except FileNotFoundError:
        logging.error(f"[API /.../resync-site] DDEV command not found during execution: {' '.join(ddev_command)}.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500
    except Exception as e:
        logging.error(f"[API /.../resync-site] Exception during re-sync '{' '.join(ddev_command)}' for {site_name}: {str(e)}")
        return jsonify({'status': 'error', 'message': f"An unexpected error occurred during re-sync: {str(e)}", 'output': str(e)}), 500

@app.route('/api/clone-environment/<env_name>', methods=['POST'])
def clone_environment(env_name):
    """
    API endpoint to clone an entire Acquia environment locally
    using `ddev acquia-clone <env_name>`.
    """
    if not utils.find_ddev(): # Check for DDEV.
        logging.error("[API /api/clone-environment] DDEV command not found.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found.'}), 500

    if not env_name: # Ensure environment name is provided.
        return jsonify({'status': 'error', 'message': 'Environment name parameter is required.'}), 400

    # Validate DDEV global configuration for Acquia credentials before proceeding.
    global_config = utils.read_ddev_global_config()
    if not global_config or (isinstance(global_config, dict) and 'error' in global_config):
        error_message = "DDEV global configuration ($HOME/.ddev/global_config.yaml) is missing or invalid."
        if isinstance(global_config, dict) and 'error' in global_config:
            error_message = f"Error with DDEV global config: {global_config.get('details', global_config['error'])}. Path: {global_config.get('path', 'N/A')}"
            if global_config['error'] == 'DDEV_GLOBAL_CONFIG_NOT_FOUND':
                 error_message += " This file is required for Acquia API credentials."
        logging.error(f"clone_environment: {error_message}")
        return jsonify({'status': 'error', 'message': error_message}), 500 # 500 as it's a server-side config prerequisite

    # Also check if the necessary Acquia keys are present in the loaded config
    if not (global_config.get('acquia_api_key') and global_config.get('acquia_api_secret')):
        error_message = "Acquia API Key or Secret is missing from DDEV global configuration ($HOME/.ddev/global_config.yaml). Cannot proceed with 'ddev acquia-clone'."
        logging.error(f"clone_environment: {error_message}")
        return jsonify({'status': 'error', 'message': error_message}), 400 # 400 as it's a client/user config issue preventing action

    command = ['ddev', 'acquia-clone', env_name]
    logging.info(f"Executing command: {' '.join(command)}")
    try:
        process = subprocess.run(command, capture_output=True, text=True, check=False)
        if process.returncode == 0:
            logging.info(f"Command '{' '.join(command)}' successful. Output: {process.stdout}")
            return jsonify({'status': 'success', 'message': f"Environment '{env_name}' processed successfully.", 'output': process.stdout or f"Environment '{env_name}' processed successfully."})
        else:
            logging.error(f"Command '{' '.join(command)}' failed. Exit code: {process.returncode}. Stderr: {process.stderr}, Stdout: {process.stdout}")
            return jsonify({
                'status': 'error',
                'message': f"Failed to process environment '{env_name}'. Exit code: {process.returncode}.",
                'output': process.stderr or "No standard error output.",
                'stdout': process.stdout or "No standard output."
            }), 500
    except FileNotFoundError:
        logging.error(f"DDEV command not found when trying to execute: {' '.join(command)}.")
        return jsonify({'status': 'error', 'message': 'DDEV command not found. Please ensure DDEV is installed and in your PATH.'}), 500
    except Exception as e:
        logging.error(f"An exception occurred during '{' '.join(command)}': {str(e)}")
        return jsonify({'status': 'error', 'message': f"An exception occurred: {str(e)}", 'output': str(e)}), 500

if __name__ == '__main__':
    flask_thread = threading.Thread(target=start_flask)
    flask_thread.daemon = True
    flask_thread.start()

    webview.create_window('Acquia DDEV Dashboard', 'http://127.0.0.1:5000')
    webview.start()
