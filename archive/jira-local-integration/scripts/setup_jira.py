#!/usr/bin/env python3
"""
JIRA Setup Helper Script

This script helps configure JIRA integration for the Selene project.
It guides users through the setup process and validates the configuration.
"""

import os
import sys
import yaml
from pathlib import Path
from typing import Dict, Optional
import getpass

from rich.console import Console
from rich.prompt import Prompt, Confirm
from rich.panel import Panel
from rich.syntax import Syntax


console = Console()


def create_jira_config() -> Dict:
    """Interactive setup of JIRA configuration."""
    console.print(Panel.fit("🎯 JIRA Configuration Setup", style="bold blue"))
    
    config = {
        'jira': {
            'instance': {},
            'auth': {}
        },
        'current_work': {},
        'project_mapping': {},
        'sync': {
            'auto_sync': {},
            'worklog': {},
            'status_mapping': {}
        },
        'notifications': {},
        'custom_fields': {}
    }
    
    # JIRA Instance Configuration
    console.print("\n📍 [bold]JIRA Instance Configuration[/bold]")
    jira_url = Prompt.ask("JIRA URL (e.g., https://company.atlassian.net)")
    config['jira']['instance']['url'] = jira_url
    
    # Authentication
    console.print("\n🔐 [bold]Authentication Setup[/bold]")
    auth_methods = [
        "1. API Token (recommended for Atlassian Cloud)",
        "2. Personal Access Token (for Server/Data Center)",
        "3. Basic Authentication (username/password)"
    ]
    
    for method in auth_methods:
        console.print(f"  {method}")
    
    auth_choice = Prompt.ask("Choose authentication method", choices=["1", "2", "3"], default="1")
    
    if auth_choice == "1":
        email = Prompt.ask("Email address")
        api_token = getpass.getpass("API Token (input hidden): ")
        config['jira']['auth']['email'] = email
        config['jira']['auth']['api_token'] = api_token
        
        console.print("💡 [dim]To create an API token, visit: https://id.atlassian.com/manage-profile/security/api-tokens[/dim]")
        
    elif auth_choice == "2":
        pat = getpass.getpass("Personal Access Token (input hidden): ")
        config['jira']['auth']['pat'] = pat
        
    else:
        username = Prompt.ask("Username")
        password = getpass.getpass("Password (input hidden): ")
        config['jira']['auth']['username'] = username
        config['jira']['auth']['password'] = password
    
    # Current Work Configuration
    console.print("\n🎯 [bold]Current Work Configuration[/bold]")
    epic_prefix = Prompt.ask("Epic prefix (e.g., SMS for Second Brain Management System)", default="SMS")
    sprint_name = Prompt.ask("Current sprint name", default="Sprint 1")
    board_id = Prompt.ask("JIRA Board ID (found in board URL)", default="123")
    
    config['current_work']['epic'] = epic_prefix
    config['current_work']['sprint'] = sprint_name
    try:
        config['current_work']['board_id'] = int(board_id)
    except ValueError:
        config['current_work']['board_id'] = 123
    
    # Project Mapping
    console.print("\n📁 [bold]Project Structure Mapping[/bold]")
    console.print("Map your project directories to JIRA tickets:")
    
    # Default mappings
    default_mappings = {
        "selene/": f"{epic_prefix}-13",
        "tests/": f"{epic_prefix}-13",
        "requirements.txt": f"{epic_prefix}-13",
        "README.md": f"{epic_prefix}-13"
    }
    
    config['project_mapping'] = default_mappings
    
    if Confirm.ask("Would you like to add custom directory mappings?"):
        while True:
            directory = Prompt.ask("Directory/file pattern (or 'done' to finish)")
            if directory.lower() == 'done':
                break
            ticket = Prompt.ask(f"JIRA ticket for '{directory}'")
            config['project_mapping'][directory] = ticket
    
    # Sync Configuration
    console.print("\n🔄 [bold]Sync Configuration[/bold]")
    config['sync']['auto_sync']['enabled'] = Confirm.ask("Enable automatic sync?", default=True)
    config['sync']['auto_sync']['on_commit'] = Confirm.ask("Sync on git commit?", default=True)
    config['sync']['auto_sync']['on_push'] = Confirm.ask("Sync on git push?", default=True)
    
    config['sync']['worklog']['enabled'] = Confirm.ask("Enable automatic work logging?", default=True)
    config['sync']['worklog']['auto_track_time'] = Confirm.ask("Auto-track time spent?", default=True)
    default_time = Prompt.ask("Default time spent per commit", default="1h")
    config['sync']['worklog']['default_time_spent'] = default_time
    
    # Status mapping
    status_mappings = {
        "feature/*": "In Progress",
        "epic*/*": "In Progress",
        "bugfix/*": "In Progress",
        "main": "Done",
        "develop": "In Review"
    }
    config['sync']['status_mapping'] = status_mappings
    
    # Custom fields (common defaults)
    config['custom_fields'] = {
        'story_points': 'customfield_10016',
        'epic_link': 'customfield_10014',
        'sprint_field': 'customfield_10020'
    }
    
    return config


def save_config(config: Dict, filepath: str = ".jira-config.yaml") -> bool:
    """Save configuration to YAML file."""
    try:
        with open(filepath, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, indent=2)
        return True
    except Exception as e:
        console.print(f"❌ Error saving config: {e}", style="red")
        return False


def test_connection(config_path: str = ".jira-config.yaml") -> bool:
    """Test JIRA connection with the provided configuration."""
    try:
        # Import here to avoid dependency issues during setup
        from jira import JIRA
        
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        
        jira_config = config['jira']
        server = jira_config['instance']['url']
        auth_config = jira_config['auth']
        
        console.print("🔍 Testing JIRA connection...")
        
        # Try to connect based on auth method
        if 'email' in auth_config and 'api_token' in auth_config:
            jira = JIRA(
                server=server,
                basic_auth=(auth_config['email'], auth_config['api_token'])
            )
        elif 'pat' in auth_config:
            jira = JIRA(
                server=server,
                token_auth=auth_config['pat']
            )
        elif 'username' in auth_config and 'password' in auth_config:
            jira = JIRA(
                server=server,
                basic_auth=(auth_config['username'], auth_config['password'])
            )
        else:
            console.print("❌ No valid authentication method found", style="red")
            return False
        
        # Test basic operations
        user = jira.current_user()
        console.print(f"✅ Connected to JIRA as: {user}", style="green")
        
        # Test project access
        try:
            projects = jira.projects()
            console.print(f"✅ Found {len(projects)} accessible projects", style="green")
        except Exception as e:
            console.print(f"⚠️  Limited project access: {e}", style="yellow")
        
        return True
        
    except ImportError:
        console.print("❌ JIRA library not installed. Run: pip install jira", style="red")
        return False
    except Exception as e:
        console.print(f"❌ Connection failed: {e}", style="red")
        return False


def show_usage_examples():
    """Display usage examples for the JIRA sync script."""
    console.print(Panel.fit("📋 Usage Examples", style="bold green"))
    
    examples = [
        "# Sync latest commit with JIRA",
        "python scripts/jira_sync.py",
        "",
        "# Sync specific commit",
        "python scripts/jira_sync.py --commit abc123",
        "",
        "# Update ticket status based on current branch",
        "python scripts/jira_sync.py --branch-status",
        "",
        "# Dry run to see what would happen",
        "python scripts/jira_sync.py --dry-run",
        "",
        "# Verbose output",
        "python scripts/jira_sync.py --verbose",
        "",
        "# Use custom config file",
        "python scripts/jira_sync.py --config my-jira-config.yaml"
    ]
    
    syntax = Syntax("\n".join(examples), "bash", theme="monokai", line_numbers=False)
    console.print(syntax)


def main():
    """Main setup function."""
    console.print("🚀 [bold blue]Selene JIRA Integration Setup[/bold blue]")
    
    config_path = ".jira-config.yaml"
    
    if Path(config_path).exists():
        if not Confirm.ask(f"Config file {config_path} already exists. Overwrite?"):
            console.print("Setup cancelled.", style="yellow")
            return
    
    # Create configuration
    config = create_jira_config()
    
    # Save configuration
    console.print(f"\n💾 Saving configuration to {config_path}...")
    if save_config(config, config_path):
        console.print(f"✅ Configuration saved to {config_path}", style="green")
    else:
        console.print("❌ Failed to save configuration", style="red")
        return
    
    # Test connection
    if Confirm.ask("Test JIRA connection now?", default=True):
        if test_connection(config_path):
            console.print("🎉 JIRA integration setup complete!", style="bold green")
        else:
            console.print("⚠️  Setup complete but connection test failed. Please check your configuration.", style="yellow")
    
    # Show usage examples
    if Confirm.ask("Show usage examples?", default=True):
        show_usage_examples()
    
    console.print("\n📝 [bold]Next Steps:[/bold]")
    console.print("1. Install dependencies: pip install jira pyyaml")
    console.print("2. Test the sync: python scripts/jira_sync.py --dry-run")
    console.print("3. Set up git hooks for automatic sync (optional)")
    console.print(f"4. Keep {config_path} secure and don't commit it to version control")


if __name__ == "__main__":
    main()