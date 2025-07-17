#!/bin/bash
# Production monitoring script for Selene

PRODUCTION_DIR="${SELENE_PRODUCTION_DIR:-$HOME/selene-production}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔍 Selene Production Monitor"
echo "=================================="

# Check if production directory exists
if [ ! -d "$PRODUCTION_DIR" ]; then
    echo -e "${RED}❌ Production directory not found: $PRODUCTION_DIR${NC}"
    exit 1
fi

cd "$PRODUCTION_DIR"

# System Status
echo -e "\n📊 ${GREEN}System Status${NC}"
echo "• Production directory: $PRODUCTION_DIR"
echo "• Current time: $(date)"
echo "• Uptime: $(uptime)"

# Git Status
echo -e "\n🔄 ${GREEN}Git Status${NC}"
echo "• Branch: $(git branch --show-current)"
echo "• Commit: $(git rev-parse --short HEAD) - $(git log -1 --pretty=format:'%s')"
echo "• Last pull: $(git log -1 --pretty=format:'%cd' --date=relative)"

# Service Status
echo -e "\n🚀 ${GREEN}Service Status${NC}"

# Check web interface
if curl -s http://localhost:8000/health > /dev/null; then
    echo -e "• Web interface: ${GREEN}✅ Running${NC} (http://localhost:8000)"
else
    echo -e "• Web interface: ${RED}❌ Not responding${NC}"
fi

# Check Ollama
if curl -s http://localhost:11434/api/tags > /dev/null; then
    echo -e "• Ollama service: ${GREEN}✅ Running${NC}"
    echo "• Available models: $(curl -s http://localhost:11434/api/tags | jq -r '.models[].name' | tr '\n' ' ')"
else
    echo -e "• Ollama service: ${RED}❌ Not running${NC}"
fi

# Check processes
SELENE_PROCESSES=$(pgrep -f "python.*selene" | wc -l)
if [ "$SELENE_PROCESSES" -gt 0 ]; then
    echo -e "• Selene processes: ${GREEN}✅ $SELENE_PROCESSES running${NC}"
else
    echo -e "• Selene processes: ${RED}❌ No processes found${NC}"
fi

# Resource Usage
echo -e "\n💻 ${GREEN}Resource Usage${NC}"
echo "• CPU: $(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/,//')% user"
echo "• Memory: $(ps aux | grep python | grep selene | awk '{sum += $6} END {print sum/1024 " MB"}')"
echo "• Disk: $(df -h . | tail -1 | awk '{print $5 " used (" $4 " free)"}')"

# Data Directory Status
echo -e "\n📁 ${GREEN}Data Directory Status${NC}"
if [ -d "data" ]; then
    echo "• Data directory: ✅ Exists"
    echo "• Vector database: $([ -d "data/chroma" ] && echo "✅ Exists" || echo "❌ Not found")"
    echo "• Chat memory: $([ -f "data/chat_memory.db" ] && echo "✅ Exists" || echo "❌ Not found")"
    echo "• Processed notes: $(find . -name "processed_notes_*" -type d | wc -l | tr -d ' ') directories"
else
    echo -e "• Data directory: ${YELLOW}⚠️ Not found${NC}"
fi

# Log Status
echo -e "\n📋 ${GREEN}Log Status${NC}"
if [ -f "logs/selene.log" ]; then
    echo "• Log file: ✅ Exists"
    echo "• Log size: $(du -h logs/selene.log | cut -f1)"
    echo "• Recent errors: $(tail -100 logs/selene.log | grep -i error | wc -l | tr -d ' ')"
    echo "• Last log entry: $(tail -1 logs/selene.log | cut -d'|' -f1)"
else
    echo -e "• Log file: ${YELLOW}⚠️ Not found${NC}"
fi

# Recent Activity
echo -e "\n📈 ${GREEN}Recent Activity${NC}"
if [ -f "logs/selene.log" ]; then
    echo "• Recent batch imports: $(tail -1000 logs/selene.log | grep -i "batch import" | wc -l | tr -d ' ')"
    echo "• Recent vector operations: $(tail -1000 logs/selene.log | grep -i "vector" | wc -l | tr -d ' ')"
    echo "• Recent chat sessions: $(tail -1000 logs/selene.log | grep -i "chat" | wc -l | tr -d ' ')"
fi

# Health Check
echo -e "\n🩺 ${GREEN}Health Check${NC}"

# Check database connections
if python -c "from selene.vector.chroma_store import ChromaStore; ChromaStore()" 2>/dev/null; then
    echo -e "• Vector database: ${GREEN}✅ Healthy${NC}"
else
    echo -e "• Vector database: ${RED}❌ Connection failed${NC}"
fi

# Check batch import
if python -m selene.main batch-import --help > /dev/null 2>&1; then
    echo -e "• Batch import: ${GREEN}✅ Available${NC}"
else
    echo -e "• Batch import: ${RED}❌ Command failed${NC}"
fi

# Quick Actions
echo -e "\n🔧 ${GREEN}Quick Actions${NC}"
echo "• View logs: tail -f logs/selene.log"
echo "• Restart service: ./deploy.sh"
echo "• Backup data: ./backup.sh"
echo "• Test batch import: python -m selene.main batch-import --source drafts --dry-run"
echo "• Web interface: open http://localhost:8000"

# Alerts
echo -e "\n🚨 ${GREEN}Alerts${NC}"
ALERTS_FOUND=false

# Check disk space
DISK_USAGE=$(df . | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    echo -e "• ${RED}⚠️ Disk space critical: ${DISK_USAGE}%${NC}"
    ALERTS_FOUND=true
fi

# Check log size
if [ -f "logs/selene.log" ]; then
    LOG_SIZE=$(du -m logs/selene.log | cut -f1)
    if [ "$LOG_SIZE" -gt 100 ]; then
        echo -e "• ${YELLOW}⚠️ Log file large: ${LOG_SIZE}MB${NC}"
        ALERTS_FOUND=true
    fi
fi

# Check for recent errors
if [ -f "logs/selene.log" ]; then
    RECENT_ERRORS=$(tail -100 logs/selene.log | grep -i error | wc -l | tr -d ' ')
    if [ "$RECENT_ERRORS" -gt 5 ]; then
        echo -e "• ${RED}⚠️ Recent errors: ${RECENT_ERRORS}${NC}"
        ALERTS_FOUND=true
    fi
fi

if [ "$ALERTS_FOUND" = false ]; then
    echo -e "• ${GREEN}✅ No alerts${NC}"
fi

echo ""
echo "🎉 Monitoring complete!"