#!/usr/bin/env python3
"""
Simple JIRA Ticket Transition Tool

A lightweight script to directly transition specific JIRA tickets to "Done" status
without the interactive project manager interface.

Usage:
    python transition_ticket.py SMS-123                    # Transition single ticket to Done
    python transition_ticket.py SMS-123 "In Review"       # Transition to specific status
    python transition_ticket.py SMS-123 SMS-124 SMS-125   # Transition multiple tickets to Done
    python transition_ticket.py --list SMS-123            # List available transitions for ticket
    python transition_ticket.py --help                    # Show help
"""

import sys
import yaml
import argparse
from pathlib import Path
from typing import List, Optional
from jira import JIRA
from rich.console import Console
from rich.table import Table


class JIRATicketTransitioner:
    """Simple JIRA client for transitioning tickets."""
    
    def __init__(self, config_path: str = ".jira-config.yaml"):
        self.console = Console()
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.jira = self._connect_to_jira()
    
    def _load_config(self) -> dict:
        """Load JIRA configuration from yaml file."""
        if not self.config_path.exists():
            self.console.print(f"❌ JIRA config not found: {self.config_path}", style="red")
            self.console.print("Expected config file with JIRA connection details.", style="yellow")
            sys.exit(1)
            
        with open(self.config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def _connect_to_jira(self) -> JIRA:
        """Connect to JIRA instance using config credentials."""
        jira_config = self.config['jira']
        server = jira_config['instance']['url']
        auth_config = jira_config['auth']
        
        try:
            # Try different authentication methods based on config
            if 'email' in auth_config and 'api_token' in auth_config:
                return JIRA(
                    server=server,
                    basic_auth=(auth_config['email'], auth_config['api_token'])
                )
            elif 'pat' in auth_config:
                return JIRA(server=server, token_auth=auth_config['pat'])
            elif 'username' in auth_config and 'password' in auth_config:
                return JIRA(
                    server=server,
                    basic_auth=(auth_config['username'], auth_config['password'])
                )
            else:
                raise ValueError("No valid authentication method found in config")
                
        except Exception as e:
            self.console.print(f"❌ Failed to connect to JIRA: {e}", style="red")
            self.console.print("Check your credentials in .jira-config.yaml", style="yellow")
            sys.exit(1)
    
    def get_available_transitions(self, ticket_key: str) -> List[dict]:
        """Get all available transitions for a ticket."""
        try:
            issue = self.jira.issue(ticket_key)
            transitions = self.jira.transitions(issue)
            return transitions
        except Exception as e:
            self.console.print(f"❌ Failed to get transitions for {ticket_key}: {e}", style="red")
            return []
    
    def list_transitions(self, ticket_key: str) -> None:
        """Display available transitions for a ticket."""
        try:
            issue = self.jira.issue(ticket_key)
            transitions = self.get_available_transitions(ticket_key)
            
            self.console.print(f"\n📋 [bold]{ticket_key}[/bold]: {issue.fields.summary}")
            self.console.print(f"Current Status: [blue]{issue.fields.status.name}[/blue]")
            
            if not transitions:
                self.console.print("No transitions available", style="yellow")
                return
            
            table = Table(title="Available Transitions")
            table.add_column("ID", style="cyan")
            table.add_column("Transition", style="green")
            table.add_column("To Status", style="blue")
            
            for transition in transitions:
                table.add_row(
                    transition['id'],
                    transition['name'],
                    transition.get('to', {}).get('name', 'Unknown')
                )
            
            self.console.print(table)
            
        except Exception as e:
            self.console.print(f"❌ Failed to fetch ticket {ticket_key}: {e}", style="red")
    
    def transition_ticket(self, ticket_key: str, target_status: str = "Done") -> bool:
        """Transition a ticket to the specified status."""
        try:
            issue = self.jira.issue(ticket_key)
            current_status = issue.fields.status.name
            
            # Check if already in target status
            if current_status.lower() == target_status.lower():
                self.console.print(f"✅ {ticket_key} is already in '{target_status}' status", style="green")
                return True
            
            # Get available transitions
            transitions = self.jira.transitions(issue)
            
            # Find matching transition
            transition_id = None
            for transition in transitions:
                if transition['name'].lower() == target_status.lower():
                    transition_id = transition['id']
                    break
                # Also check if the transition leads to the target status
                elif transition.get('to', {}).get('name', '').lower() == target_status.lower():
                    transition_id = transition['id']
                    break
            
            if transition_id:
                self.jira.transition_issue(issue, transition_id)
                self.console.print(
                    f"✅ Successfully moved {ticket_key} from '{current_status}' to '{target_status}'", 
                    style="green"
                )
                return True
            else:
                available = [t['name'] for t in transitions]
                self.console.print(
                    f"❌ Cannot transition {ticket_key} to '{target_status}'. "
                    f"Available transitions: {', '.join(available)}", 
                    style="red"
                )
                return False
                
        except Exception as e:
            self.console.print(f"❌ Failed to transition {ticket_key}: {e}", style="red")
            return False
    
    def transition_multiple_tickets(self, ticket_keys: List[str], target_status: str = "Done") -> dict:
        """Transition multiple tickets to the specified status."""
        results = {"success": [], "failed": []}
        
        self.console.print(f"\n🎯 Transitioning {len(ticket_keys)} tickets to '{target_status}'...")
        
        for ticket_key in ticket_keys:
            if self.transition_ticket(ticket_key, target_status):
                results["success"].append(ticket_key)
            else:
                results["failed"].append(ticket_key)
        
        # Summary
        self.console.print(f"\n📊 [bold]Summary:[/bold]")
        self.console.print(f"✅ Successfully transitioned: {len(results['success'])}")
        self.console.print(f"❌ Failed to transition: {len(results['failed'])}")
        
        if results["failed"]:
            self.console.print(f"\n❌ Failed tickets: {', '.join(results['failed'])}", style="red")
        
        return results


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Simple JIRA Ticket Transition Tool",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python transition_ticket.py SMS-123                    # Move SMS-123 to Done
  python transition_ticket.py SMS-123 "In Review"       # Move SMS-123 to In Review  
  python transition_ticket.py SMS-123 SMS-124           # Move multiple tickets to Done
  python transition_ticket.py --list SMS-123            # List available transitions
        """
    )
    
    parser.add_argument(
        "tickets", 
        nargs='*', 
        help="JIRA ticket keys (e.g., SMS-123, SMS-124)"
    )
    parser.add_argument(
        "status", 
        nargs='?', 
        default="Done",
        help="Target status (default: Done)"
    )
    parser.add_argument(
        "--list", "-l",
        metavar="TICKET",
        help="List available transitions for a specific ticket"
    )
    parser.add_argument(
        "--config", 
        default=".jira-config.yaml",
        help="JIRA config file path (default: .jira-config.yaml)"
    )
    
    args = parser.parse_args()
    
    # Handle --list option
    if args.list:
        transitioner = JIRATicketTransitioner(args.config)
        transitioner.list_transitions(args.list)
        return
    
    # Validate arguments for transition
    if not args.tickets:
        parser.print_help()
        sys.exit(1)
    
    # Check if last argument is a status (not a ticket key)
    tickets = args.tickets
    target_status = args.status
    
    # If there are multiple arguments and the last one doesn't look like a ticket key,
    # treat it as the target status
    if len(tickets) > 1 and not tickets[-1].upper().startswith(('SMS-', 'PROJ-', 'TASK-')):
        target_status = tickets[-1]
        tickets = tickets[:-1]
    
    try:
        transitioner = JIRATicketTransitioner(args.config)
        
        if len(tickets) == 1:
            transitioner.transition_ticket(tickets[0], target_status)
        else:
            transitioner.transition_multiple_tickets(tickets, target_status)
            
    except KeyboardInterrupt:
        print("\n👋 Operation cancelled")
        sys.exit(0)
    except Exception as e:
        console = Console()
        console.print(f"❌ Unexpected error: {e}", style="red")
        sys.exit(1)


if __name__ == "__main__":
    main()