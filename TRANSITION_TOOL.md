# JIRA Ticket Transition Tool

A simple, lightweight script for directly transitioning JIRA tickets to "Done" status (or any other status) without using the interactive project manager interface.

## Features

- **Direct ticket transitions** - No interactive menus, just specify tickets and go
- **Multiple ticket support** - Transition many tickets at once
- **Status flexibility** - Transition to any available status, not just "Done"
- **Intelligent handling** - Detects if tickets are already in target status
- **Transition discovery** - List available transitions for any ticket
- **Rich output** - Clean, colored terminal output with progress indicators

## Quick Start

```bash
# Transition single ticket to Done
python transition_ticket.py SMS-123

# Transition multiple tickets to Done  
python transition_ticket.py SMS-123 SMS-124 SMS-125

# Transition to specific status
python transition_ticket.py SMS-123 "In Review"

# List available transitions for a ticket
python transition_ticket.py --list SMS-123
```

## Prerequisites

1. **JIRA Configuration**: Requires `.jira-config.yaml` file with your JIRA credentials
2. **Dependencies**: Uses the same dependencies as the main project manager:
   - `jira` - JIRA Python library
   - `rich` - Terminal formatting
   - `pyyaml` - YAML config parsing

## Configuration

The script uses the same `.jira-config.yaml` file as the project manager. It supports all authentication methods:

- **API Token** (recommended for Atlassian Cloud)
- **Personal Access Token** (newer server versions) 
- **Basic Auth** (server installations)

## Usage Examples

### Basic Operations
```bash
# Simple transition to Done
python transition_ticket.py SMS-27

# Transition to specific status
python transition_ticket.py SMS-27 "In Progress"

# Multiple tickets to Done
python transition_ticket.py SMS-27 SMS-28 SMS-29

# Multiple tickets to specific status  
python transition_ticket.py SMS-27 SMS-28 "In Review"
```

### Discovery and Debugging
```bash
# List what transitions are available
python transition_ticket.py --list SMS-27

# Use custom config file
python transition_ticket.py --config /path/to/config.yaml SMS-27

# Get help
python transition_ticket.py --help
```

## Key Components

The script extracts the essential JIRA functionality from the larger project manager:

### Authentication (`_connect_to_jira`)
- Loads credentials from `.jira-config.yaml`
- Supports multiple auth methods (API token, PAT, basic auth)
- Provides clear error messages on connection failure

### Ticket Transition (`transition_ticket`)  
- Fetches current ticket status
- Finds appropriate transition to target status
- Executes transition via JIRA API
- Handles edge cases (already in target status, invalid transitions)

### Batch Operations (`transition_multiple_tickets`)
- Processes multiple tickets in sequence
- Provides summary of successes/failures
- Continues processing even if some tickets fail

## Integration with Project Workflow

This tool complements the interactive project manager:

- **Project Manager**: Full workflow management, time tracking, git integration
- **Transition Tool**: Quick, scriptable ticket status updates

Use the transition tool when you need to:
- Bulk update ticket statuses
- Script ticket transitions in CI/CD pipelines
- Quickly mark work as complete without full session management

## Error Handling

The script provides clear feedback for common issues:

- **Missing config file**: Points to setup requirements
- **Authentication failures**: Suggests credential verification  
- **Invalid ticket keys**: Reports which tickets couldn't be found
- **Invalid transitions**: Lists available transitions for the ticket
- **Network issues**: Reports connection problems clearly

## Output Examples

### Successful Transition
```
✅ Successfully moved SMS-27 from 'In Progress' to 'Done'
```

### Already in Target Status
```
✅ SMS-27 is already in 'Done' status
```

### Invalid Transition
```
❌ Cannot transition SMS-27 to 'Invalid Status'. Available transitions: To Do, In Progress, In Review, Done
```

### Batch Operation Summary
```
🎯 Transitioning 3 tickets to 'Done'...
✅ Successfully moved SMS-27 from 'In Progress' to 'Done'
✅ Successfully moved SMS-28 from 'In Review' to 'Done'  
❌ Failed to transition SMS-29: Ticket not found

📊 Summary:
✅ Successfully transitioned: 2
❌ Failed to transition: 1

❌ Failed tickets: SMS-29
```

## Files

- `/Users/chaseeasterling/git/selene/transition_ticket.py` - Main transition script
- `/Users/chaseeasterling/git/selene/scripts/transition_examples.sh` - Usage examples and demo
- `/Users/chaseeasterling/git/selene/.jira-config.yaml` - JIRA configuration (credentials)