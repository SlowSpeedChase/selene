"""
JIRA API client for authentication and basic operations.
"""

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml
from jira import JIRA
from jira.exceptions import JIRAError
from loguru import logger


@dataclass
class JiraConfig:
    """JIRA configuration data."""

    url: str
    email: str
    api_token: str
    project_key: str = "SMS"
    board_id: Optional[int] = None

    @classmethod
    def from_file(cls, config_path: str = ".jira-config.yaml") -> "JiraConfig":
        """Load configuration from YAML file."""
        config_file = Path(config_path)

        if not config_file.exists():
            raise FileNotFoundError(f"JIRA config file not found: {config_path}")

        with open(config_file, "r") as f:
            data = yaml.safe_load(f)

        jira_config = data.get("jira", {})
        instance_config = jira_config.get("instance", {})
        auth_config = jira_config.get("auth", {})
        current_work = data.get("current_work", {})

        return cls(
            url=instance_config.get("url", ""),
            email=auth_config.get("email", ""),
            api_token=auth_config.get("api_token", ""),
            project_key=current_work.get("epic", "SMS"),
            board_id=current_work.get("board_id"),
        )

    def validate(self) -> List[str]:
        """Validate configuration and return list of issues."""
        issues = []

        if not self.url or "your-company" in self.url:
            issues.append("JIRA URL not configured")

        if not self.email or "your-email" in self.email:
            issues.append("JIRA email not configured")

        if not self.api_token or "your-api-token" in self.api_token:
            issues.append("JIRA API token not configured")

        if not self.project_key:
            issues.append("Project key not configured")

        return issues


class JiraClient:
    """JIRA API client with authentication and basic operations."""

    def __init__(self, config: Optional[JiraConfig] = None):
        """
        Initialize JIRA client.

        Args:
            config: JIRA configuration. If None, loads from file.
        """
        self.config = config or JiraConfig.from_file()
        self.client: Optional[JIRA] = None
        self._authenticated = False

    async def authenticate(self) -> bool:
        """
        Authenticate with JIRA API.

        Returns:
            True if authentication successful, False otherwise.
        """
        # Validate configuration
        issues = self.config.validate()
        if issues:
            logger.error(f"JIRA configuration issues: {', '.join(issues)}")
            return False

        try:
            # Initialize JIRA client with basic auth
            self.client = JIRA(
                server=self.config.url,
                basic_auth=(self.config.email, self.config.api_token),
                options={"verify": True, "rest_api_version": "2"},
            )

            # Test connection by getting current user
            current_user = self.client.current_user()
            logger.info(f"Successfully authenticated as JIRA user: {current_user}")
            self._authenticated = True

            return True

        except JIRAError as e:
            logger.error(f"JIRA authentication failed: {e}")
            self._authenticated = False
            return False
        except Exception as e:
            logger.error(f"Unexpected error during JIRA authentication: {e}")
            self._authenticated = False
            return False

    def is_authenticated(self) -> bool:
        """Check if client is authenticated."""
        return self._authenticated and self.client is not None

    def get_project(self, project_key: Optional[str] = None) -> Optional[Any]:
        """
        Get JIRA project information.

        Args:
            project_key: Project key to retrieve. Uses config default if None.

        Returns:
            JIRA project object or None if not found.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return None

        key = project_key or self.config.project_key

        try:
            project = self.client.project(key)
            logger.info(f"Retrieved project: {project.name} ({project.key})")
            return project
        except JIRAError as e:
            logger.error(f"Failed to get project {key}: {e}")
            return None

    def get_issue(self, issue_key: str) -> Optional[Any]:
        """
        Get JIRA issue by key.

        Args:
            issue_key: Issue key (e.g., "SMS-13")

        Returns:
            JIRA issue object or None if not found.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return None

        try:
            issue = self.client.issue(issue_key)
            logger.info(f"Retrieved issue: {issue.key} - {issue.fields.summary}")
            return issue
        except JIRAError as e:
            logger.error(f"Failed to get issue {issue_key}: {e}")
            return None

    def create_issue(
        self,
        summary: str,
        description: str,
        issue_type: str = "Task",
        project_key: Optional[str] = None,
    ) -> Optional[Any]:
        """
        Create a new JIRA issue.

        Args:
            summary: Issue summary/title
            description: Issue description
            issue_type: Issue type (Task, Story, Bug, etc.)
            project_key: Project key. Uses config default if None.

        Returns:
            Created JIRA issue object or None if failed.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return None

        key = project_key or self.config.project_key

        try:
            issue_dict = {
                "project": {"key": key},
                "summary": summary,
                "description": description,
                "issuetype": {"name": issue_type},
            }

            new_issue = self.client.create_issue(fields=issue_dict)
            logger.info(f"Created issue: {new_issue.key} - {summary}")
            return new_issue

        except JIRAError as e:
            logger.error(f"Failed to create issue: {e}")
            return None

    def update_issue(self, issue_key: str, fields: Dict[str, Any]) -> bool:
        """
        Update JIRA issue fields.

        Args:
            issue_key: Issue key to update
            fields: Dictionary of fields to update

        Returns:
            True if successful, False otherwise.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return False

        try:
            issue = self.client.issue(issue_key)
            issue.update(fields=fields)
            logger.info(f"Updated issue {issue_key}")
            return True

        except JIRAError as e:
            logger.error(f"Failed to update issue {issue_key}: {e}")
            return False

    def transition_issue(self, issue_key: str, status: str) -> bool:
        """
        Transition issue to new status.

        Args:
            issue_key: Issue key to transition
            status: Target status name

        Returns:
            True if successful, False otherwise.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return False

        try:
            issue = self.client.issue(issue_key)
            transitions = self.client.transitions(issue)

            # Find transition that leads to target status
            target_transition = None
            for transition in transitions:
                if transition["to"]["name"].lower() == status.lower():
                    target_transition = transition
                    break

            if not target_transition:
                logger.error(
                    f"No transition found to status '{status}' for issue {issue_key}"
                )
                available_statuses = [t["to"]["name"] for t in transitions]
                logger.info(f"Available transitions: {', '.join(available_statuses)}")
                return False

            self.client.transition_issue(issue, target_transition["id"])
            logger.info(f"Transitioned issue {issue_key} to {status}")
            return True

        except JIRAError as e:
            logger.error(f"Failed to transition issue {issue_key}: {e}")
            return False

    def add_comment(self, issue_key: str, comment: str) -> bool:
        """
        Add comment to JIRA issue.

        Args:
            issue_key: Issue key
            comment: Comment text

        Returns:
            True if successful, False otherwise.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return False

        try:
            issue = self.client.issue(issue_key)
            self.client.add_comment(issue, comment)
            logger.info(f"Added comment to issue {issue_key}")
            return True

        except JIRAError as e:
            logger.error(f"Failed to add comment to issue {issue_key}: {e}")
            return False

    def search_issues(self, jql: str, max_results: int = 50) -> List[Any]:
        """
        Search for issues using JQL.

        Args:
            jql: JIRA Query Language string
            max_results: Maximum number of results

        Returns:
            List of JIRA issue objects.
        """
        if not self.is_authenticated():
            logger.error("JIRA client not authenticated")
            return []

        try:
            issues = self.client.search_issues(jql, maxResults=max_results)
            logger.info(f"Found {len(issues)} issues matching query: {jql}")
            return issues

        except JIRAError as e:
            logger.error(f"Failed to search issues: {e}")
            return []

    def get_connection_info(self) -> Dict[str, Any]:
        """Get JIRA connection information."""
        return {
            "url": self.config.url,
            "email": self.config.email,
            "project_key": self.config.project_key,
            "board_id": self.config.board_id,
            "authenticated": self.is_authenticated(),
        }
