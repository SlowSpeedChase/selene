#!/bin/bash
# Production setup script for Selene

set -e

echo "🚀 Setting up Selene for production..."

# Configuration
SELENE_HOME="${SELENE_HOME:-$HOME/selene-production}"
SELENE_DATA="${SELENE_DATA:-$SELENE_HOME/data}"
SELENE_LOGS="${SELENE_LOGS:-$SELENE_HOME/logs}"

# Create directories
mkdir -p "$SELENE_HOME"
mkdir -p "$SELENE_DATA"
mkdir -p "$SELENE_LOGS"

echo "📂 Production directory: $SELENE_HOME"
echo "💾 Data directory: $SELENE_DATA"
echo "📋 Logs directory: $SELENE_LOGS"

# Check if we're in the right directory
if [ ! -f "selene/main.py" ]; then
    echo "❌ Error: Run this script from the Selene project root"
    exit 1
fi

# Create production virtual environment
echo "🐍 Creating Python virtual environment..."
python3 -m venv "$SELENE_HOME/venv"
source "$SELENE_HOME/venv/bin/activate"

# Install dependencies
echo "📦 Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Copy project files
echo "📁 Copying project files..."
rsync -av --exclude='venv' --exclude='*.pyc' --exclude='__pycache__' \
    --exclude='.git' --exclude='logs' . "$SELENE_HOME/"

# Create production configuration
echo "⚙️ Creating production configuration..."
cat > "$SELENE_HOME/.env" << EOF
# Selene Production Configuration
SELENE_ENV=production
SELENE_DATA_DIR=$SELENE_DATA
SELENE_LOGS_DIR=$SELENE_LOGS

# Ollama Configuration
OLLAMA_HOST=http://localhost:11434
OLLAMA_PORT=11434
OLLAMA_TIMEOUT=120.0

# Vector Database
CHROMA_PERSIST_DIR=$SELENE_DATA/chroma

# Web Interface
SELENE_WEB_HOST=0.0.0.0
SELENE_WEB_PORT=8000

# Chat Configuration
CHAT_MEMORY_DB=$SELENE_DATA/chat_memory.db
EOF

# Create systemd service file (Linux only)
if command -v systemctl &> /dev/null; then
    echo "🔧 Creating systemd service..."
    sudo tee /etc/systemd/system/selene.service > /dev/null << EOF
[Unit]
Description=Selene Second Brain Processing System
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$SELENE_HOME
Environment=PATH=$SELENE_HOME/venv/bin
ExecStart=$SELENE_HOME/venv/bin/python -m selene.main web --host 0.0.0.0 --port 8000
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable selene
    echo "✅ Systemd service created and enabled"
fi

# Create macOS LaunchAgent (macOS only)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Creating macOS LaunchAgent..."
    mkdir -p ~/Library/LaunchAgents
    cat > ~/Library/LaunchAgents/com.selene.web.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.selene.web</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SELENE_HOME/venv/bin/python</string>
        <string>-m</string>
        <string>selene.main</string>
        <string>web</string>
        <string>--host</string>
        <string>0.0.0.0</string>
        <string>--port</string>
        <string>8000</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SELENE_HOME</string>
    <key>StandardOutPath</key>
    <string>$SELENE_LOGS/selene.log</string>
    <key>StandardErrorPath</key>
    <string>$SELENE_LOGS/selene.error.log</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF
    
    launchctl load ~/Library/LaunchAgents/com.selene.web.plist
    echo "✅ LaunchAgent created and loaded"
fi

# Create deployment script
cat > "$SELENE_HOME/deploy.sh" << 'EOF'
#!/bin/bash
# Deployment script for Selene updates

set -e

echo "🔄 Deploying Selene updates..."

# Navigate to production directory
cd "$(dirname "$0")"

# Activate virtual environment
source venv/bin/activate

# Pull latest changes
git pull origin main

# Install/update dependencies
pip install --upgrade -r requirements.txt

# Restart services
if command -v systemctl &> /dev/null; then
    sudo systemctl restart selene
    echo "✅ Systemd service restarted"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    launchctl unload ~/Library/LaunchAgents/com.selene.web.plist
    launchctl load ~/Library/LaunchAgents/com.selene.web.plist
    echo "✅ LaunchAgent restarted"
fi

echo "🎉 Deployment complete!"
EOF

chmod +x "$SELENE_HOME/deploy.sh"

# Create backup script
cat > "$SELENE_HOME/backup.sh" << 'EOF'
#!/bin/bash
# Backup script for Selene data

BACKUP_DIR="$HOME/selene-backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "💾 Creating backup in $BACKUP_DIR..."

# Backup data directory
if [ -d "data" ]; then
    cp -r data "$BACKUP_DIR/"
    echo "✅ Data backed up"
fi

# Backup configuration
cp .env "$BACKUP_DIR/" 2>/dev/null || true
cp -r prompt_templates "$BACKUP_DIR/" 2>/dev/null || true

echo "🎉 Backup complete!"
EOF

chmod +x "$SELENE_HOME/backup.sh"

echo ""
echo "🎉 Production setup complete!"
echo ""
echo "📍 Production directory: $SELENE_HOME"
echo "🌐 Web interface will be available at: http://localhost:8000"
echo ""
echo "Next steps:"
echo "1. cd $SELENE_HOME"
echo "2. source venv/bin/activate"
echo "3. Start Ollama: ollama serve"
echo "4. Pull models: ollama pull llama3.2:1b && ollama pull nomic-embed-text"
echo "5. Test batch import: ./venv/bin/python -m selene.main batch-import --help"
echo ""
echo "Deployment: Run ./deploy.sh to update from git"
echo "Backup: Run ./backup.sh to backup data"