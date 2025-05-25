import unittest
from unittest.mock import patch, mock_open
import os
import yaml # For YAMLError
import json # For JSONDecodeError

# Attempt to import utils relative to the package structure
# This assumes tests might be run from the project root or within the package dir
try:
    from . import utils
except ImportError:
    import utils # Fallback for running script directly in the package dir for testing

class TestGetHomeDir(unittest.TestCase):
    @patch('os.path.expanduser')
    def test_get_home_dir(self, mock_expanduser):
        """Test that get_home_dir returns the expected path from os.path.expanduser."""
        expected_path = "/dummy/home/user"
        mock_expanduser.return_value = expected_path
        self.assertEqual(utils.get_home_dir(), expected_path)
        mock_expanduser.assert_called_once_with("~")

class TestCheckPathExists(unittest.TestCase):
    @patch('os.path.exists')
    def test_check_path_exists_true(self, mock_os_exists):
        """Test check_path_exists when os.path.exists returns True."""
        mock_os_exists.return_value = True
        self.assertTrue(utils.check_path_exists("/some/valid/path"))
        mock_os_exists.assert_called_once_with("/some/valid/path")

    @patch('os.path.exists')
    def test_check_path_exists_false(self, mock_os_exists):
        """Test check_path_exists when os.path.exists returns False."""
        mock_os_exists.return_value = False
        self.assertFalse(utils.check_path_exists("/some/invalid/path"))
        mock_os_exists.assert_called_once_with("/some/invalid/path")

    def test_check_path_exists_none(self):
        """Test check_path_exists with None as path_string."""
        self.assertFalse(utils.check_path_exists(None))

    def test_check_path_exists_empty_string(self):
        """Test check_path_exists with an empty string as path_string."""
        self.assertFalse(utils.check_path_exists(""))

class TestReadDdevGlobalConfig(unittest.TestCase):
    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', new_callable=mock_open)
    @patch('yaml.safe_load')
    def test_read_ddev_global_config_valid(self, mock_safe_load, mock_file_open, mock_get_home):
        """Test reading a valid DDEV global config file."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        config_path = os.path.join(dummy_home, '.ddev', 'global_config.yaml')
        
        expected_config = {'acquia_api_key': 'test_key', 'acquia_api_secret': 'test_secret', 'other_key': 'value'}
        mock_safe_load.return_value = expected_config
        mock_file_open.return_value.read.return_value = "some yaml content" # Ensure read() returns non-empty

        result = utils.read_ddev_global_config()
        self.assertEqual(result, expected_config)
        mock_file_open.assert_called_once_with(config_path, 'r')
        mock_safe_load.assert_called_once_with("some yaml content")

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', side_effect=FileNotFoundError)
    def test_read_ddev_global_config_file_not_found(self, mock_file_open, mock_get_home):
        """Test DDEV global config reading when file is not found."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        config_path = os.path.join(dummy_home, '.ddev', 'global_config.yaml')

        result = utils.read_ddev_global_config()
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get('error'), 'DDEV_GLOBAL_CONFIG_NOT_FOUND') # Matches utils.py
        self.assertEqual(result.get('path'), config_path)
        self.assertIn("file not found", result.get('message', '').lower())
        mock_file_open.assert_called_once_with(config_path, 'r')

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', new_callable=mock_open)
    @patch('yaml.safe_load', side_effect=yaml.YAMLError("Malformed YAML"))
    def test_read_ddev_global_config_yaml_error(self, mock_safe_load, mock_file_open, mock_get_home):
        """Test DDEV global config reading with malformed YAML."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        config_path = os.path.join(dummy_home, '.ddev', 'global_config.yaml')
        mock_file_open.return_value.read.return_value = "malformed: yaml:"

        result = utils.read_ddev_global_config()
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get('error'), 'DDEV_GLOBAL_CONFIG_INVALID_YAML') # Matches utils.py
        self.assertEqual(result.get('path'), config_path)
        self.assertIn("Malformed YAML", result.get('details', ''))
        self.assertIn("invalid yaml", result.get('message', '').lower())
        mock_file_open.assert_called_once_with(config_path, 'r')
        mock_safe_load.assert_called_once_with("malformed: yaml:")

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', new_callable=mock_open)
    # No need to mock yaml.safe_load if content.strip() is false, as it won't be called.
    def test_read_ddev_global_config_empty_file_content(self, mock_file_open, mock_get_home):
        """Test DDEV global config reading when file is empty (read returns empty string)."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        config_path = os.path.join(dummy_home, '.ddev', 'global_config.yaml')
        mock_file_open.return_value.read.return_value = "" # Simulate empty file content
        
        result = utils.read_ddev_global_config()
        # utils.py returns None if content.strip() is false (empty file)
        self.assertIsNone(result) 
        mock_file_open.assert_called_once_with(config_path, 'r')

    # Note: Testing for missing required keys (e.g., ACQUIA_API_KEY) in the YAML content
    # is not done by `read_ddev_global_config` itself. That function just parses and returns.
    # Key validation happens in `main.py` where the config is consumed.
    # Therefore, such a test is out of scope for `test_utils.py` for this function.

    # Test for other generic exceptions during file read
    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', side_effect=IOError("Disk full"))
    def test_read_ddev_global_config_io_error(self, mock_file_open, mock_get_home):
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        config_path = os.path.join(dummy_home, '.ddev', 'global_config.yaml')
        result = utils.read_ddev_global_config()
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get('error'), 'DDEV_GLOBAL_CONFIG_READ_ERROR')
        self.assertEqual(result.get('path'), config_path)
        self.assertIn("Disk full", result.get('details', ''))
        mock_file_open.assert_called_once_with(config_path, 'r')


    # Note: The subtask asked for testing "Missing required keys".
    # The current implementation of `read_ddev_global_config` does not perform key validation;
    # it simply returns the parsed dictionary. Key validation is done in `main.py`.
    # Therefore, a test for missing keys within `test_utils.py` for `read_ddev_global_config`
    # would just test that it returns whatever `yaml.safe_load` returns, which is already covered.
    # If key validation were moved to `utils.py`, such a test would belong here.

class TestReadAcquiaProjectsJson(unittest.TestCase):
    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', new_callable=mock_open)
    @patch('json.loads') # Patch json.loads as utils.py uses it after reading content
    def test_read_acquia_projects_json_valid(self, mock_json_loads, mock_file_open, mock_get_home):
        """Test reading a valid acquia-projects.json file."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        json_path = os.path.join(dummy_home, '.ddev', 'acquia-projects.json')
        
        expected_data = {"projects": [{"name": "proj1", "path": "/path/to/proj1"}]}
        mock_json_loads.return_value = expected_data
        mock_file_open.return_value.read.return_value = '{"projects": []}' # Ensure read returns non-empty for loads

        result = utils.read_acquia_projects_json()
        self.assertEqual(result, expected_data)
        mock_file_open.assert_called_once_with(json_path, 'r')
        mock_json_loads.assert_called_once_with('{"projects": []}')

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', side_effect=FileNotFoundError)
    def test_read_acquia_projects_json_file_not_found(self, mock_file_open, mock_get_home):
        """Test acquia-projects.json reading when file is not found."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        json_path = os.path.join(dummy_home, '.ddev', 'acquia-projects.json')

        result = utils.read_acquia_projects_json()
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get('error'), 'ACQUIA_PROJECTS_JSON_NOT_FOUND') # Matches utils.py
        self.assertEqual(result.get('path'), json_path)
        self.assertIn("file not found", result.get('message', '').lower())
        mock_file_open.assert_called_once_with(json_path, 'r')

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', new_callable=mock_open)
    @patch('json.loads', side_effect=json.JSONDecodeError("Expecting value", "doc", 0))
    def test_read_acquia_projects_json_decode_error(self, mock_json_loads, mock_file_open, mock_get_home):
        """Test acquia-projects.json reading with malformed JSON."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        json_path = os.path.join(dummy_home, '.ddev', 'acquia-projects.json')
        malformed_json_string = "not a valid json"
        mock_file_open.return_value.read.return_value = malformed_json_string

        result = utils.read_acquia_projects_json()
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get('error'), 'ACQUIA_PROJECTS_JSON_INVALID_JSON') # Matches utils.py
        self.assertEqual(result.get('path'), json_path)
        self.assertIn("Expecting value", result.get('details', ''))
        self.assertIn("invalid json", result.get('message', '').lower())
        mock_file_open.assert_called_once_with(json_path, 'r')
        mock_json_loads.assert_called_once_with(malformed_json_string)

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', new_callable=mock_open)
    # No need to mock json.loads if content.strip() is false, as it won't be called.
    def test_read_acquia_projects_json_empty_file_content(self, mock_file_open, mock_get_home):
        """Test acquia-projects.json reading when file content is empty."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        json_path = os.path.join(dummy_home, '.ddev', 'acquia-projects.json')
        mock_file_open.return_value.read.return_value = "" # Empty content
        
        result = utils.read_acquia_projects_json()
        # utils.py returns None if content.strip() is false (empty file)
        self.assertIsNone(result) 
        mock_file_open.assert_called_once_with(json_path, 'r')

    @patch('acquia_ddev_dashboard.utils.get_home_dir')
    @patch('builtins.open', side_effect=IOError("Disk full"))
    def test_read_acquia_projects_json_io_error(self, mock_file_open, mock_get_home):
        """Test acquia-projects.json reading with a generic IOError."""
        dummy_home = "/dummy/home"
        mock_get_home.return_value = dummy_home
        json_path = os.path.join(dummy_home, '.ddev', 'acquia-projects.json')
        result = utils.read_acquia_projects_json()
        self.assertIsInstance(result, dict)
        self.assertEqual(result.get('error'), 'ACQUIA_PROJECTS_JSON_READ_ERROR')
        self.assertEqual(result.get('path'), json_path)
        self.assertIn("Disk full", result.get('details', ''))
        mock_file_open.assert_called_once_with(json_path, 'r')


if __name__ == '__main__':
    unittest.main()
