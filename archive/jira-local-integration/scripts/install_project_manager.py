#!/usr/bin/env python3
"""
Project Manager Installation Script

Sets up the project manager as a daily development companion with:
- Desktop shortcuts/aliases
- Git hooks for automatic updates
- Shell integration
"""

import os
import sys
import subprocess
from pathlib import Path
from rich.console import Console
from rich.prompt import Confirm
from rich.panel import Panel

console = Console()


def create_shell_alias():
    """Create shell alias for easy access."""
    project_root = Path.cwd()
    pm_script = project_root / "project-manager.py"
    
    # Detect shell
    shell = os.environ.get('SHELL', '/bin/bash')
    
    if 'zsh' in shell:
        rc_file = Path.home() / '.zshrc'
    elif 'bash' in shell:
        rc_file = Path.home() / '.bashrc'
        if not rc_file.exists():
            rc_file = Path.home() / '.bash_profile'
    else:
        console.print("⚠️  Unknown shell, skipping alias creation", style="yellow")
        return False
    
    alias_line = f'alias pm="cd {project_root} && source venv/bin/activate && python {pm_script}"'
    
    # Check if alias already exists
    if rc_file.exists():
        with open(rc_file, 'r') as f:
            content = f.read()
            if 'alias pm=' in content:
                console.print("✅ Shell alias 'pm' already exists", style="green")
                return True
    
    # Add alias
    try:
        with open(rc_file, 'a') as f:
            f.write(f'\n# Selene Project Manager\n{alias_line}\n')
        
        console.print(f"✅ Added 'pm' alias to {rc_file}", style="green")
        console.print("💡 Restart your terminal or run: source ~/.zshrc", style="dim")
        return True
        
    except Exception as e:
        console.print(f"❌ Failed to create alias: {e}", style="red")
        return False


def setup_git_hooks():
    """Set up git hooks for automatic JIRA updates."""
    project_root = Path.cwd()
    hooks_dir = project_root / '.git' / 'hooks'
    
    if not hooks_dir.exists():
        console.print("⚠️  Not in a git repository, skipping git hooks", style="yellow")
        return False
    
    # Post-commit hook
    post_commit_hook = hooks_dir / 'post-commit'
    hook_content = f'''#!/bin/bash
# Auto-sync with JIRA after commit
cd {project_root}
source venv/bin/activate 2>/dev/null || true
python scripts/jira_sync.py --commit HEAD 2>/dev/null || true
'''
    
    try:
        with open(post_commit_hook, 'w') as f:
            f.write(hook_content)
        
        # Make executable
        os.chmod(post_commit_hook, 0o755)
        
        console.print("✅ Created post-commit git hook", style="green")
        return True
        
    except Exception as e:
        console.print(f"❌ Failed to create git hook: {e}", style="red")
        return False


def create_desktop_shortcut():
    """Create desktop shortcut (macOS/Linux)."""
    if sys.platform == 'darwin':  # macOS
        return _create_macos_shortcut()
    elif sys.platform.startswith('linux'):
        return _create_linux_shortcut()
    else:
        console.print("⚠️  Desktop shortcut not supported on this platform", style="yellow")
        return False


def _create_macos_shortcut():
    """Create macOS application shortcut."""
    project_root = Path.cwd()
    app_name = "Selene Project Manager"
    
    # Create Automator app script
    script_content = f'''
tell application "Terminal"
    do script "cd {project_root} && source venv/bin/activate && python project-manager.py start"
    activate
end tell
'''
    
    try:
        # Use osascript to create the app
        subprocess.run([
            'osascript', '-e',
            f'tell application "Script Editor" to make new document with properties {{text:"{script_content}"}}'
        ])
        
        console.print("💡 Manual step: Save the script as an Application in Script Editor", style="dim")
        return True
        
    except Exception as e:
        console.print(f"❌ Failed to create macOS shortcut: {e}", style="red")
        return False


def _create_linux_shortcut():
    """Create Linux desktop entry."""
    project_root = Path.cwd()
    desktop_file = Path.home() / 'Desktop' / 'selene-pm.desktop'
    
    desktop_content = f'''[Desktop Entry]
Version=1.0
Type=Application
Name=Selene Project Manager
Comment=Daily Development Companion
Exec=gnome-terminal -- bash -c "cd {project_root} && source venv/bin/activate && python project-manager.py start; exec bash"
Icon=utilities-terminal
Terminal=false
Categories=Development;
'''
    
    try:
        with open(desktop_file, 'w') as f:
            f.write(desktop_content)
        
        # Make executable
        os.chmod(desktop_file, 0o755)
        
        console.print(f"✅ Created desktop shortcut: {desktop_file}", style="green")
        return True
        
    except Exception as e:
        console.print(f"❌ Failed to create Linux shortcut: {e}", style="red")
        return False


def install_dependencies():
    """Install additional dependencies for project manager."""
    try:
        subprocess.run([
            sys.executable, '-m', 'pip', 'install', 'gitpython'
        ], check=True, capture_output=True)
        
        console.print("✅ Installed GitPython dependency", style="green")
        return True
        
    except subprocess.CalledProcessError as e:
        console.print(f"❌ Failed to install dependencies: {e}", style="red")
        return False


def main():
    """Main installation function."""
    console.print(Panel.fit(
        "🚀 Selene Project Manager Setup\n"
        "This will set up your daily development companion with:\n"
        "• Shell alias 'pm' for quick access\n"
        "• Git hooks for automatic JIRA sync\n"
        "• Desktop shortcut (optional)\n"
        "• Required dependencies",
        title="Project Manager Installation",
        border_style="blue"
    ))
    
    if not Confirm.ask("Continue with installation?", default=True):
        console.print("❌ Installation cancelled", style="yellow")
        return
    
    success_count = 0
    
    # Install dependencies
    console.print("\n📦 Installing dependencies...")
    if install_dependencies():
        success_count += 1
    
    # Create shell alias
    console.print("\n🔗 Creating shell alias...")
    if create_shell_alias():
        success_count += 1
    
    # Set up git hooks
    console.print("\n🪝 Setting up git hooks...")
    if setup_git_hooks():
        success_count += 1
    
    # Create desktop shortcut
    console.print("\n🖥️  Creating desktop shortcut...")
    if Confirm.ask("Create desktop shortcut?", default=False):
        if create_desktop_shortcut():
            success_count += 1
    
    # Summary
    console.print(f"\n🎉 Installation completed! ({success_count} items configured)")
    
    console.print(Panel.fit(
        "🎯 [bold]Quick Start:[/bold]\n"
        "• Run: pm start (or python project-manager.py start)\n"
        "• Check status: pm status\n"
        "• Finish work: pm finish\n"
        "• List tickets: pm tickets\n\n"
        "💡 [bold]Tips:[/bold]\n"
        "• Configure JIRA first: python scripts/setup_jira.py\n"
        "• The project manager tracks time automatically\n"
        "• Git commits will auto-sync with JIRA\n"
        "• Use 'pm status' to see current work session",
        title="Ready to Use!",
        border_style="green"
    ))


if __name__ == "__main__":
    main()