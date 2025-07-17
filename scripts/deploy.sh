#!/bin/bash
# Deployment script for Selene updates

set -e

echo "🚀 Deploying Selene updates..."

# Configuration
PRODUCTION_DIR="${SELENE_PRODUCTION_DIR:-$HOME/selene-production}"
BACKUP_BEFORE_DEPLOY="${BACKUP_BEFORE_DEPLOY:-true}"

# Check if production directory exists
if [ ! -d "$PRODUCTION_DIR" ]; then
    echo "❌ Production directory not found: $PRODUCTION_DIR"
    echo "   Run scripts/production_setup.sh first"
    exit 1
fi

# Navigate to production directory
cd "$PRODUCTION_DIR"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Not a git repository: $PRODUCTION_DIR"
    exit 1
fi

# Backup before deployment
if [ "$BACKUP_BEFORE_DEPLOY" = "true" ]; then
    echo "💾 Creating backup before deployment..."
    ./backup.sh
fi

# Check current status
echo "📋 Current status:"
git status --porcelain
echo "📍 Current branch: $(git branch --show-current)"
echo "🏷️  Current commit: $(git rev-parse --short HEAD)"

# Stash any local changes
if [ -n "$(git status --porcelain)" ]; then
    echo "📦 Stashing local changes..."
    git stash
fi

# Pull latest changes
echo "⬇️  Pulling latest changes..."
git pull origin main

# Activate virtual environment
echo "🐍 Activating virtual environment..."
source venv/bin/activate

# Update dependencies
echo "📦 Updating dependencies..."
pip install --upgrade -r requirements.txt

# Run tests
echo "🧪 Running tests..."
python -m pytest tests/ -v || {
    echo "❌ Tests failed! Rolling back..."
    git reset --hard HEAD~1
    exit 1
}

# Restart services
echo "🔄 Restarting services..."

# Stop existing processes
pkill -f "python.*selene" || true
pkill -f "uvicorn.*selene" || true

# Wait for processes to stop
sleep 2

# Restart based on platform
if command -v systemctl &> /dev/null; then
    echo "🔧 Restarting systemd service..."
    sudo systemctl restart selene
    sudo systemctl status selene --no-pager
elif [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Restarting macOS LaunchAgent..."
    launchctl unload ~/Library/LaunchAgents/com.selene.web.plist 2>/dev/null || true
    launchctl load ~/Library/LaunchAgents/com.selene.web.plist
else
    echo "🚀 Starting web interface manually..."
    nohup python -m selene.main web --host 0.0.0.0 --port 8000 > logs/web.log 2>&1 &
fi

# Verify deployment
echo "✅ Verifying deployment..."
sleep 3

# Check if web interface is running
if curl -s http://localhost:8000/health > /dev/null; then
    echo "🌐 Web interface is running: http://localhost:8000"
else
    echo "⚠️  Web interface may not be running. Check logs/selene.log"
fi

# Show deployment summary
echo ""
echo "🎉 Deployment complete!"
echo "📍 Production directory: $PRODUCTION_DIR"
echo "🏷️  Deployed commit: $(git rev-parse --short HEAD)"
echo "📅 Deployed at: $(date)"
echo ""
echo "🔍 Check status:"
echo "  • Web interface: http://localhost:8000"
echo "  • Logs: tail -f logs/selene.log"
echo "  • Health check: curl http://localhost:8000/health"
echo ""
echo "🚀 Test batch import:"
echo "  python -m selene.main batch-import --source drafts --tag selene --dry-run"