#!/usr/bin/env python3
"""
Bulk update JIRA tickets to reflect actual implementation status.
Updates SMS-13 through SMS-38 to "Done" status based on local codebase analysis.
"""

import sys
import os
import subprocess

# Add current directory to path for project_manager import
current_dir = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, current_dir)

# Import after path setup
try:
    from project_manager import ProjectManager
except ImportError as e:
    print(f"❌ Error importing ProjectManager: {e}")
    print("   Make sure you're running this from the selene directory")
    sys.exit(1)

def bulk_update_sms_tickets():
    """Update SMS-13 through SMS-38 tickets to Done status."""
    
    # Initialize project manager
    pm = ProjectManager()
    
    # Define ticket range based on actual implementation
    completed_tickets = [
        "SMS-13",  # Project Foundation & CLI Framework
        "SMS-14",  # Local AI Note Processing Pipeline
        "SMS-15",  # Local Vector Database (ChromaDB)
        "SMS-16",  # JIRA Integration and Project Tracking
        "SMS-17",  # File Monitoring System
        "SMS-18",  # Web UI (FastAPI + Modern Dashboard)
        "SMS-19",  # Advanced AI Features
        "SMS-20",  # Mobile Interface (PWA)
        "SMS-23",  # Note Formatter
        "SMS-24",  # Vault Organization
        "SMS-27",  # Batch Import System
        "SMS-32",  # Ollama Connection Manager
        "SMS-33",  # Prompt Template System
        "SMS-36",  # Chatbot Foundation
        "SMS-37",  # Enhanced NLP Processing
        "SMS-38",  # Advanced Chat Features
    ]
    
    print(f"🔄 Updating {len(completed_tickets)} completed tickets to 'Done' status...")
    print(f"Tickets: {', '.join(completed_tickets)}")
    
    successful = []
    failed = []
    
    for ticket_key in completed_tickets:
        print(f"Processing {ticket_key}...")
        try:
            if pm.transition_ticket(ticket_key, "Done"):
                successful.append(ticket_key)
                print(f"  ✅ {ticket_key} → Done")
            else:
                failed.append(ticket_key)
                print(f"  ❌ {ticket_key} → Failed")
        except Exception as e:
            failed.append(ticket_key)
            print(f"  ❌ {ticket_key} → Error: {e}")
    
    print(f"\n📊 RESULTS:")
    print(f"✅ Successfully updated: {len(successful)} tickets")
    print(f"   {successful}")
    
    if failed:
        print(f"❌ Failed to update: {len(failed)} tickets")
        print(f"   {failed}")
    else:
        print("🎉 All tickets updated successfully!")

if __name__ == "__main__":
    bulk_update_sms_tickets()