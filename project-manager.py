#!/usr/bin/env python3
"""
Project Manager - Daily Development Companion

A comprehensive JIRA-integrated development workflow manager that handles:
- Sprint management and ticket selection
- Automatic git branch creation and management
- Time tracking and work logging
- Progress updates and status transitions
- Full development workflow automation

Usage:
    python project-manager.py start    # Start daily workflow
    python project-manager.py status   # Check current work status
    python project-manager.py finish   # Finish current work session
    python project-manager.py tickets  # List available tickets
"""

import os
import sys
import json
import yaml
import time
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
import argparse

import git
from jira import JIRA
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.prompt import Prompt, Confirm, IntPrompt
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.layout import Layout
from rich.live import Live
from rich.text import Text
from rich.syntax import Syntax
from loguru import logger


class WorkSession:
    """Tracks current work session state."""
    
    def __init__(self, session_file: str = ".work-session.json"):
        self.session_file = Path(session_file)
        self.data = self._load_session()
    
    def _load_session(self) -> Dict:
        """Load existing work session or create new one."""
        if self.session_file.exists():
            with open(self.session_file, 'r') as f:
                return json.load(f)
        return {}
    
    def save(self):
        """Save current session state."""
        with open(self.session_file, 'w') as f:
            json.dump(self.data, f, indent=2, default=str)
    
    def start_work(self, ticket_key: str, branch_name: str):
        """Start working on a ticket."""
        self.data.update({
            'current_ticket': ticket_key,
            'current_branch': branch_name,
            'start_time': datetime.now().isoformat(),
            'time_entries': self.data.get('time_entries', [])
        })
        self.save()
    
    def stop_work(self, work_description: str = ""):
        """Stop current work session."""
        if 'start_time' in self.data:
            start_time = datetime.fromisoformat(self.data['start_time'])
            duration = datetime.now() - start_time
            
            self.data['time_entries'].append({
                'start': self.data['start_time'],
                'end': datetime.now().isoformat(),
                'duration_minutes': int(duration.total_seconds() / 60),
                'description': work_description,
                'ticket': self.data.get('current_ticket')
            })
            
            # Clear current work
            self.data.pop('start_time', None)
            self.save()
            
            return duration
        return None
    
    def get_total_time(self, ticket_key: str = None) -> int:
        """Get total time spent (in minutes) for ticket or all work."""
        entries = self.data.get('time_entries', [])
        if ticket_key:
            entries = [e for e in entries if e.get('ticket') == ticket_key]
        return sum(e.get('duration_minutes', 0) for e in entries)
    
    def is_working(self) -> bool:
        """Check if currently in a work session."""
        return 'start_time' in self.data and 'current_ticket' in self.data
    
    def current_ticket(self) -> Optional[str]:
        """Get current ticket being worked on."""
        return self.data.get('current_ticket')
    
    def current_duration(self) -> Optional[timedelta]:
        """Get duration of current work session."""
        if 'start_time' in self.data:
            start_time = datetime.fromisoformat(self.data['start_time'])
            return datetime.now() - start_time
        return None


class ProjectManager:
    """Main project management class with JIRA integration."""
    
    def __init__(self, config_path: str = ".jira-config.yaml"):
        self.console = Console()
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.jira = self._connect_to_jira()
        self.repo = self._get_git_repo()
        self.session = WorkSession()
        
        # Configure logging
        logger.remove()
        logger.add(
            "logs/project-manager.log",
            rotation="1 day",
            retention="30 days",
            level="INFO"
        )
    
    def _load_config(self) -> Dict:
        """Load JIRA configuration."""
        if not self.config_path.exists():
            self.console.print(f"❌ JIRA config not found: {self.config_path}", style="red")
            self.console.print("Run: python scripts/setup_jira.py", style="yellow")
            sys.exit(1)
            
        with open(self.config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def _connect_to_jira(self) -> JIRA:
        """Connect to JIRA instance."""
        jira_config = self.config['jira']
        server = jira_config['instance']['url']
        auth_config = jira_config['auth']
        
        try:
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
                raise ValueError("No valid authentication method found")
        except Exception as e:
            self.console.print(f"❌ Failed to connect to JIRA: {e}", style="red")
            sys.exit(1)
    
    def _get_git_repo(self) -> git.Repo:
        """Get current git repository."""
        try:
            return git.Repo(search_parent_directories=True)
        except git.exc.InvalidGitRepositoryError:
            self.console.print("❌ Not in a git repository", style="red")
            sys.exit(1)
    
    def get_current_sprint_tickets(self) -> List[Any]:
        """Get tickets from current sprint or fallback to project tickets."""
        try:
            current_work = self.config.get('current_work', {})
            board_id = current_work.get('board_id')
            epic_prefix = current_work.get('epic', 'SMS')
            
            if board_id:
                try:
                    # Try to get active sprint
                    sprints = self.jira.sprints(board_id, state='active')
                    if sprints:
                        sprint = sprints[0]
                        jql = f'sprint = {sprint.id} AND assignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC'
                    else:
                        self.console.print("⚠️  No active sprint found, using project search", style="yellow")
                        jql = f'project = {epic_prefix} AND assignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC'
                except Exception as sprint_error:
                    # Board doesn't support sprints, use project search
                    self.console.print("⚠️  Board doesn't support sprints, using project search", style="yellow")
                    jql = f'project = {epic_prefix} AND assignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC'
            else:
                # Fallback: search by epic or assignee
                jql = f'project = {epic_prefix} AND assignee = currentUser() AND resolution = Unresolved ORDER BY priority DESC'
            
            tickets = self.jira.search_issues(jql, maxResults=50)
            return tickets
            
        except Exception as e:
            logger.error(f"Failed to get tickets: {e}")
            self.console.print(f"❌ Error fetching tickets: {e}", style="red")
            return []
    
    def display_tickets(self, tickets: List[Any]) -> None:
        """Display tickets in a formatted table."""
        if not tickets:
            self.console.print("📭 No tickets found in current sprint", style="yellow")
            return
        
        table = Table(title="🎯 Available Tickets")
        table.add_column("#", style="cyan", no_wrap=True)
        table.add_column("Key", style="magenta", no_wrap=True)
        table.add_column("Summary", style="green")
        table.add_column("Status", style="blue")
        table.add_column("Priority", style="red")
        table.add_column("Estimate", style="yellow")
        
        for i, ticket in enumerate(tickets, 1):
            # Get story points if available
            story_points_field = self.config.get('custom_fields', {}).get('story_points')
            estimate = "?"
            if story_points_field and hasattr(ticket.fields, story_points_field.replace('customfield_', '')):
                points = getattr(ticket.fields, story_points_field.replace('customfield_', ''), None)
                estimate = f"{points}pts" if points else "?"
            
            table.add_row(
                str(i),
                ticket.key,
                ticket.fields.summary[:60] + "..." if len(ticket.fields.summary) > 60 else ticket.fields.summary,
                ticket.fields.status.name,
                ticket.fields.priority.name if ticket.fields.priority else "Medium",
                estimate
            )
        
        self.console.print(table)
    
    def select_ticket(self, tickets: List[Any]) -> Optional[Any]:
        """Let user select a ticket to work on."""
        if not tickets:
            return None
        
        while True:
            try:
                choice = IntPrompt.ask(
                    "Select ticket number (0 to cancel)",
                    default=0,
                    show_default=True
                )
                
                if choice == 0:
                    return None
                
                if 1 <= choice <= len(tickets):
                    return tickets[choice - 1]
                else:
                    self.console.print("❌ Invalid selection", style="red")
            except KeyboardInterrupt:
                return None
    
    def create_branch(self, ticket_key: str) -> str:
        """Create git branch for ticket."""
        # Clean ticket key for branch name
        branch_name = f"feature/{ticket_key.lower()}"
        
        try:
            # Ensure we're on main/master branch
            main_branch = "main" if "main" in [ref.name for ref in self.repo.refs] else "master"
            self.repo.git.checkout(main_branch)
            self.repo.git.pull()
            
            # Create new branch
            self.repo.git.checkout('-b', branch_name)
            
            self.console.print(f"✅ Created branch: {branch_name}", style="green")
            logger.info(f"Created branch {branch_name} for ticket {ticket_key}")
            return branch_name
            
        except git.exc.GitCommandError as e:
            if "already exists" in str(e):
                # Branch exists, just switch to it
                self.repo.git.checkout(branch_name)
                self.console.print(f"🔄 Switched to existing branch: {branch_name}", style="yellow")
                return branch_name
            else:
                self.console.print(f"❌ Git error: {e}", style="red")
                return None
    
    def transition_ticket(self, ticket_key: str, new_status: str) -> bool:
        """Transition ticket to new status."""
        try:
            issue = self.jira.issue(ticket_key)
            transitions = self.jira.transitions(issue)
            
            # Find matching transition
            transition_id = None
            for transition in transitions:
                if transition['name'].lower() == new_status.lower():
                    transition_id = transition['id']
                    break
            
            if transition_id:
                self.jira.transition_issue(issue, transition_id)
                self.console.print(f"✅ Moved {ticket_key} to: {new_status}", style="green")
                logger.info(f"Transitioned {ticket_key} to {new_status}")
                return True
            else:
                available = [t['name'] for t in transitions]
                self.console.print(f"⚠️  Status '{new_status}' not available. Available: {available}", style="yellow")
                return False
                
        except Exception as e:
            self.console.print(f"❌ Failed to transition ticket: {e}", style="red")
            logger.error(f"Failed to transition {ticket_key}: {e}")
            return False
    
    def log_work(self, ticket_key: str, time_spent: str, description: str = "") -> bool:
        """Log work time to JIRA ticket."""
        try:
            issue = self.jira.issue(ticket_key)
            self.jira.add_worklog(
                issue=issue,
                timeSpent=time_spent,
                comment=description,
                started=datetime.now()
            )
            
            self.console.print(f"✅ Logged {time_spent} to {ticket_key}", style="green")
            logger.info(f"Logged work {time_spent} to {ticket_key}: {description}")
            return True
            
        except Exception as e:
            self.console.print(f"❌ Failed to log work: {e}", style="red")
            logger.error(f"Failed to log work to {ticket_key}: {e}")
            return False
    
    def start_work_session(self) -> bool:
        """Start a new work session."""
        if self.session.is_working():
            current = self.session.current_ticket()
            duration = self.session.current_duration()
            hours, remainder = divmod(int(duration.total_seconds()), 3600)
            minutes, _ = divmod(remainder, 60)
            
            self.console.print(
                f"⚠️  Already working on {current} for {hours:02d}:{minutes:02d}",
                style="yellow"
            )
            
            if not Confirm.ask("Stop current session and start new one?"):
                return False
            
            self.finish_work_session()
        
        # Get available tickets
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=self.console
        ) as progress:
            task = progress.add_task("Fetching tickets from JIRA...", total=None)
            tickets = self.get_current_sprint_tickets()
        
        if not tickets:
            return False
        
        # Display and select ticket
        self.display_tickets(tickets)
        selected_ticket = self.select_ticket(tickets)
        
        if not selected_ticket:
            self.console.print("❌ No ticket selected", style="red")
            return False
        
        # Create git branch
        branch_name = self.create_branch(selected_ticket.key)
        if not branch_name:
            return False
        
        # Transition ticket to "In Progress"
        self.transition_ticket(selected_ticket.key, "In Progress")
        
        # Start work session
        self.session.start_work(selected_ticket.key, branch_name)
        
        # Display work session info
        self.console.print(Panel.fit(
            f"🚀 Started working on: [bold]{selected_ticket.key}[/bold]\n"
            f"📝 {selected_ticket.fields.summary}\n"
            f"🌿 Branch: {branch_name}\n"
            f"⏰ Started: {datetime.now().strftime('%H:%M:%S')}",
            title="Work Session Started",
            border_style="green"
        ))
        
        logger.info(f"Started work session on {selected_ticket.key}")
        return True
    
    def finish_work_session(self) -> bool:
        """Finish current work session."""
        if not self.session.is_working():
            self.console.print("❌ No active work session", style="red")
            return False
        
        ticket_key = self.session.current_ticket()
        duration = self.session.current_duration()
        
        # Get work description
        description = Prompt.ask(
            "Describe work completed (optional)",
            default=""
        )
        
        # Stop session and get duration
        session_duration = self.session.stop_work(description)
        
        if session_duration:
            hours, remainder = divmod(int(session_duration.total_seconds()), 3600)
            minutes, _ = divmod(remainder, 60)
            
            # Format time for JIRA (e.g., "2h 30m")
            time_parts = []
            if hours > 0:
                time_parts.append(f"{hours}h")
            if minutes > 0:
                time_parts.append(f"{minutes}m")
            time_spent = " ".join(time_parts) or "1m"
            
            # Log work to JIRA
            if Confirm.ask(f"Log {time_spent} to JIRA?", default=True):
                self.log_work(ticket_key, time_spent, description)
            
            self.console.print(Panel.fit(
                f"⏹️  Finished working on: [bold]{ticket_key}[/bold]\n"
                f"⏱️  Time spent: {hours:02d}:{minutes:02d}\n"
                f"📝 Description: {description or 'No description'}",
                title="Work Session Completed",
                border_style="blue"
            ))
        
        # Ask about next steps
        self._suggest_next_steps(ticket_key)
        
        logger.info(f"Finished work session on {ticket_key}")
        return True
    
    def _suggest_next_steps(self, ticket_key: str):
        """Suggest next steps after finishing work."""
        self.console.print("\n🎯 [bold]Next Steps:[/bold]")
        
        options = [
            "1. Continue working (start new session)",
            "2. Commit and push changes",
            "3. Create pull request",
            "4. Move ticket to 'In Review'",
            "5. Take a break",
            "0. Exit"
        ]
        
        for option in options:
            self.console.print(f"  {option}")
        
        choice = IntPrompt.ask("What would you like to do?", default=0)
        
        if choice == 1:
            self.start_work_session()
        elif choice == 2:
            self._commit_and_push()
        elif choice == 3:
            self._create_pull_request()
        elif choice == 4:
            self.transition_ticket(ticket_key, "In Review")
        elif choice == 5:
            self.console.print("☕ Enjoy your break!", style="green")
        else:
            self.console.print("👋 See you later!", style="blue")
    
    def _commit_and_push(self):
        """Helper to commit and push changes."""
        try:
            # Check for changes
            if not self.repo.is_dirty(untracked_files=True):
                self.console.print("📭 No changes to commit", style="yellow")
                return
            
            # Show status
            self.console.print("📊 [bold]Git Status:[/bold]")
            status_output = self.repo.git.status('--porcelain')
            for line in status_output.split('\n'):
                if line.strip():
                    self.console.print(f"  {line}")
            
            # Get commit message
            commit_msg = Prompt.ask("Commit message", default="Work in progress")
            
            # Commit changes
            self.repo.git.add('.')
            self.repo.git.commit('-m', commit_msg)
            
            # Push changes
            if Confirm.ask("Push to remote?", default=True):
                current_branch = self.repo.active_branch.name
                self.repo.git.push('--set-upstream', 'origin', current_branch)
                self.console.print("✅ Changes committed and pushed", style="green")
            else:
                self.console.print("✅ Changes committed locally", style="green")
                
        except Exception as e:
            self.console.print(f"❌ Git operation failed: {e}", style="red")
    
    def _create_pull_request(self):
        """Helper to create pull request."""
        # This would integrate with GitHub CLI or similar
        self.console.print("🔗 Creating pull request...", style="blue")
        self.console.print("💡 Use: gh pr create --title 'Your Title' --body 'Description'", style="dim")
    
    def show_status(self) -> None:
        """Show current work session status."""
        if not self.session.is_working():
            self.console.print("📭 No active work session", style="yellow")
            
            # Show recent work
            recent_entries = self.session.data.get('time_entries', [])[-5:]
            if recent_entries:
                self.console.print("\n📊 [bold]Recent Work:[/bold]")
                for entry in recent_entries:
                    start_time = datetime.fromisoformat(entry['start'])
                    duration_hrs = entry['duration_minutes'] / 60
                    self.console.print(
                        f"  {entry['ticket']} - {start_time.strftime('%m/%d %H:%M')} "
                        f"({duration_hrs:.1f}h) - {entry.get('description', 'No description')}"
                    )
            return
        
        ticket_key = self.session.current_ticket()
        duration = self.session.current_duration()
        branch = self.session.data.get('current_branch', 'unknown')
        
        hours, remainder = divmod(int(duration.total_seconds()), 3600)
        minutes, _ = divmod(remainder, 60)
        
        # Get ticket details
        try:
            ticket = self.jira.issue(ticket_key)
            summary = ticket.fields.summary
            status = ticket.fields.status.name
        except:
            summary = "Unable to fetch details"
            status = "Unknown"
        
        self.console.print(Panel.fit(
            f"🎯 Working on: [bold]{ticket_key}[/bold]\n"
            f"📝 {summary}\n"
            f"📊 Status: {status}\n"
            f"🌿 Branch: {branch}\n"
            f"⏱️  Duration: {hours:02d}:{minutes:02d}\n"
            f"🕐 Started: {datetime.fromisoformat(self.session.data['start_time']).strftime('%H:%M:%S')}",
            title="Current Work Session",
            border_style="green"
        ))
        
        # Show total time for this ticket
        total_time = self.session.get_total_time(ticket_key)
        if total_time > 0:
            total_hours = total_time / 60
            self.console.print(f"📈 Total time on {ticket_key}: {total_hours:.1f}h")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Project Manager - Daily Development Companion")
    parser.add_argument("command", nargs='?', choices=['start', 'status', 'finish', 'tickets'], 
                       default='start', help="Command to execute")
    parser.add_argument("--config", default=".jira-config.yaml", help="JIRA config file path")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    try:
        pm = ProjectManager(args.config)
        
        if args.command == 'start':
            pm.start_work_session()
        elif args.command == 'status':
            pm.show_status()
        elif args.command == 'finish':
            pm.finish_work_session()
        elif args.command == 'tickets':
            tickets = pm.get_current_sprint_tickets()
            pm.display_tickets(tickets)
        else:
            pm.console.print(f"❌ Unknown command: {args.command}", style="red")
            
    except KeyboardInterrupt:
        print("\n👋 Goodbye!")
        sys.exit(0)
    except Exception as e:
        console = Console()
        console.print(f"❌ Error: {e}", style="red")
        if args.verbose:
            console.print_exception()
        sys.exit(1)


if __name__ == "__main__":
    main()