#!/usr/bin/env python3
"""
JIRA Sync Script for Selene Project

This script syncs local project work with JIRA tickets automatically.
It can update ticket status, add work logs, and manage ticket transitions.
"""

import os
import sys
import yaml
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import argparse

from jira import JIRA
from loguru import logger
import git


class JIRASync:
    """Handles synchronization between local project and JIRA."""
    
    def __init__(self, config_path: str = ".jira-config.yaml"):
        """Initialize JIRA sync with configuration."""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.jira = self._connect_to_jira()
        self.repo = self._get_git_repo()
        
    def _load_config(self) -> Dict:
        """Load JIRA configuration from YAML file."""
        if not self.config_path.exists():
            raise FileNotFoundError(f"JIRA config file not found: {self.config_path}")
            
        with open(self.config_path, 'r') as f:
            config = yaml.safe_load(f)
            
        # Validate required fields
        required_fields = ['jira.instance.url', 'jira.auth']
        for field in required_fields:
            if not self._get_nested_value(config, field):
                raise ValueError(f"Missing required config field: {field}")
                
        return config
    
    def _get_nested_value(self, data: Dict, key_path: str):
        """Get nested dictionary value using dot notation."""
        keys = key_path.split('.')
        value = data
        for key in keys:
            if isinstance(value, dict) and key in value:
                value = value[key]
            else:
                return None
        return value
    
    def _connect_to_jira(self) -> JIRA:
        """Establish connection to JIRA instance."""
        jira_config = self.config['jira']
        server = jira_config['instance']['url']
        auth_config = jira_config['auth']
        
        try:
            # Try API token authentication first (recommended for Cloud)
            if 'email' in auth_config and 'api_token' in auth_config:
                logger.info("Connecting to JIRA using API token authentication")
                jira = JIRA(
                    server=server,
                    basic_auth=(auth_config['email'], auth_config['api_token'])
                )
            # Try Personal Access Token
            elif 'pat' in auth_config:
                logger.info("Connecting to JIRA using Personal Access Token")
                jira = JIRA(
                    server=server,
                    token_auth=auth_config['pat']
                )
            # Fall back to basic auth
            elif 'username' in auth_config and 'password' in auth_config:
                logger.info("Connecting to JIRA using basic authentication")
                jira = JIRA(
                    server=server,
                    basic_auth=(auth_config['username'], auth_config['password'])
                )
            else:
                raise ValueError("No valid authentication method found in config")
                
            logger.success(f"Successfully connected to JIRA: {server}")
            return jira
            
        except Exception as e:
            logger.error(f"Failed to connect to JIRA: {e}")
            raise
    
    def _get_git_repo(self) -> git.Repo:
        """Get the current git repository."""
        try:
            repo = git.Repo(search_parent_directories=True)
            logger.info(f"Found git repository: {repo.working_dir}")
            return repo
        except git.exc.InvalidGitRepositoryError:
            logger.warning("Not in a git repository - some features will be disabled")
            return None
    
    def get_changed_files(self, since_commit: str = "HEAD~1") -> List[str]:
        """Get list of files changed since specified commit."""
        if not self.repo:
            return []
            
        try:
            # Get changed files between commits
            changed_files = []
            for item in self.repo.index.diff(since_commit):
                changed_files.append(item.a_path)
            
            # Also get untracked files
            changed_files.extend(self.repo.untracked_files)
            
            return changed_files
        except Exception as e:
            logger.error(f"Error getting changed files: {e}")
            return []
    
    def map_files_to_tickets(self, files: List[str]) -> Dict[str, List[str]]:
        """Map changed files to JIRA tickets based on configuration."""
        ticket_mapping = {}
        project_mapping = self.config.get('project_mapping', {})
        
        for file_path in files:
            ticket_key = None
            
            # Find the most specific mapping
            for pattern, ticket in project_mapping.items():
                if file_path.startswith(pattern):
                    ticket_key = ticket
                    break
            
            if ticket_key:
                if ticket_key not in ticket_mapping:
                    ticket_mapping[ticket_key] = []
                ticket_mapping[ticket_key].append(file_path)
        
        return ticket_mapping
    
    def update_ticket_status(self, ticket_key: str, new_status: str) -> bool:
        """Update JIRA ticket status."""
        try:
            issue = self.jira.issue(ticket_key)
            
            # Get available transitions
            transitions = self.jira.transitions(issue)
            transition_id = None
            
            for transition in transitions:
                if transition['name'].lower() == new_status.lower():
                    transition_id = transition['id']
                    break
            
            if transition_id:
                self.jira.transition_issue(issue, transition_id)
                logger.success(f"Updated {ticket_key} status to: {new_status}")
                return True
            else:
                logger.warning(f"Status '{new_status}' not available for {ticket_key}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to update {ticket_key} status: {e}")
            return False
    
    def add_work_log(self, ticket_key: str, time_spent: str, comment: str = "") -> bool:
        """Add work log entry to JIRA ticket."""
        try:
            issue = self.jira.issue(ticket_key)
            
            # Add worklog
            self.jira.add_worklog(
                issue=issue,
                timeSpent=time_spent,
                comment=comment,
                started=datetime.now()
            )
            
            logger.success(f"Added work log to {ticket_key}: {time_spent}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add work log to {ticket_key}: {e}")
            return False
    
    def add_comment(self, ticket_key: str, comment: str) -> bool:
        """Add comment to JIRA ticket."""
        try:
            issue = self.jira.issue(ticket_key)
            self.jira.add_comment(issue, comment)
            logger.success(f"Added comment to {ticket_key}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to add comment to {ticket_key}: {e}")
            return False
    
    def sync_commit(self, commit_hash: str = "HEAD") -> bool:
        """Sync a specific commit with JIRA."""
        if not self.repo:
            logger.error("No git repository found")
            return False
        
        try:
            commit = self.repo.commit(commit_hash)
            
            # Get changed files in this commit
            changed_files = []
            if commit.parents:
                # Compare with parent commit
                for item in commit.diff(commit.parents[0]):
                    changed_files.append(item.a_path or item.b_path)
            else:
                # Initial commit - get all files
                changed_files = [item.path for item in commit.tree.traverse()]
            
            # Map files to tickets
            ticket_mapping = self.map_files_to_tickets(changed_files)
            
            if not ticket_mapping:
                logger.info("No JIRA tickets found for changed files")
                return True
            
            # Update each ticket
            for ticket_key, files in ticket_mapping.items():
                comment = f"Commit: {commit.hexsha[:8]}\n"
                comment += f"Message: {commit.message.strip()}\n"
                comment += f"Files changed: {', '.join(files)}"
                
                self.add_comment(ticket_key, comment)
                
                # Add work log if enabled
                if self.config.get('sync', {}).get('worklog', {}).get('enabled', False):
                    time_spent = self.config.get('sync', {}).get('worklog', {}).get('default_time_spent', '1h')
                    self.add_work_log(ticket_key, time_spent, f"Work on commit {commit.hexsha[:8]}")
            
            logger.success(f"Synced commit {commit.hexsha[:8]} with JIRA")
            return True
            
        except Exception as e:
            logger.error(f"Failed to sync commit: {e}")
            return False
    
    def sync_branch_status(self) -> bool:
        """Update ticket status based on current branch."""
        if not self.repo:
            logger.error("No git repository found")
            return False
        
        try:
            current_branch = self.repo.active_branch.name
            status_mapping = self.config.get('sync', {}).get('status_mapping', {})
            
            new_status = None
            for pattern, status in status_mapping.items():
                if pattern.endswith('*'):
                    # Wildcard pattern
                    prefix = pattern[:-1]
                    if current_branch.startswith(prefix):
                        new_status = status
                        break
                elif pattern == current_branch:
                    # Exact match
                    new_status = status
                    break
            
            if new_status:
                # Get all tickets for current project
                project_mapping = self.config.get('project_mapping', {})
                tickets = set(project_mapping.values())
                
                for ticket_key in tickets:
                    self.update_ticket_status(ticket_key, new_status)
                
                logger.success(f"Updated ticket statuses for branch '{current_branch}' to: {new_status}")
                return True
            else:
                logger.info(f"No status mapping found for branch: {current_branch}")
                return True
                
        except Exception as e:
            logger.error(f"Failed to sync branch status: {e}")
            return False


def main():
    """Main entry point for JIRA sync script."""
    parser = argparse.ArgumentParser(description="Sync local work with JIRA")
    parser.add_argument("--config", default=".jira-config.yaml", help="Path to JIRA config file")
    parser.add_argument("--commit", help="Sync specific commit (default: HEAD)")
    parser.add_argument("--branch-status", action="store_true", help="Update ticket status based on current branch")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done without making changes")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    
    args = parser.parse_args()
    
    # Configure logging
    log_level = "DEBUG" if args.verbose else "INFO"
    logger.remove()
    logger.add(sys.stderr, level=log_level, format="<green>{time:HH:mm:ss}</green> | <level>{level}</level> | {message}")
    
    try:
        # Initialize JIRA sync
        jira_sync = JIRASync(args.config)
        
        if args.dry_run:
            logger.info("DRY RUN MODE - No changes will be made")
        
        success = True
        
        if args.branch_status:
            if not args.dry_run:
                success &= jira_sync.sync_branch_status()
            else:
                logger.info("Would sync branch status")
        
        if args.commit:
            if not args.dry_run:
                success &= jira_sync.sync_commit(args.commit)
            else:
                logger.info(f"Would sync commit: {args.commit}")
        
        # Default action: sync latest commit
        if not args.branch_status and not args.commit:
            if not args.dry_run:
                success &= jira_sync.sync_commit()
            else:
                logger.info("Would sync latest commit")
        
        if success:
            logger.success("JIRA sync completed successfully")
            sys.exit(0)
        else:
            logger.error("JIRA sync completed with errors")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"JIRA sync failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()