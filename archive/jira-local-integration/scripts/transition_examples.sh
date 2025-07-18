#!/bin/bash

# JIRA Ticket Transition Examples
# 
# This script demonstrates various ways to use the transition_ticket.py tool

echo "🎯 JIRA Ticket Transition Tool Examples"
echo "======================================="
echo

# Check if the transition script exists
if [ ! -f "transition_ticket.py" ]; then
    echo "❌ transition_ticket.py not found. Make sure you're in the selene directory."
    exit 1
fi

echo "📋 Available commands:"
echo

echo "1. List available transitions for a ticket:"
echo "   python transition_ticket.py --list SMS-27"
echo

echo "2. Transition single ticket to Done:"
echo "   python transition_ticket.py SMS-27"
echo

echo "3. Transition single ticket to specific status:"
echo "   python transition_ticket.py SMS-27 \"In Progress\""
echo

echo "4. Transition multiple tickets to Done:"
echo "   python transition_ticket.py SMS-27 SMS-28 SMS-29"
echo

echo "5. Transition multiple tickets to specific status:"
echo "   python transition_ticket.py SMS-27 SMS-28 \"In Review\""
echo

echo "6. Use custom config file:"
echo "   python transition_ticket.py --config custom-jira.yaml SMS-27"
echo

echo "📚 For full help:"
echo "   python transition_ticket.py --help"
echo

echo "🔍 Test with SMS-27 (currently in 'To Do' status):"
read -p "Would you like to list transitions for SMS-27? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    python transition_ticket.py --list SMS-27
fi

echo
echo "✅ Ready to transition tickets!"