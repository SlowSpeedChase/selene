# Production Deployment Guide

This guide covers deploying Selene to production and managing updates.

## 🚀 Quick Start

### 1. Initial Production Setup

```bash
# Clone the repository
git clone https://github.com/your-username/selene.git
cd selene

# Run production setup
./scripts/production_setup.sh
```

This creates:
- Production environment in `~/selene-production`
- Virtual environment with all dependencies
- System service (Linux) or LaunchAgent (macOS)
- Configuration files and scripts

### 2. Start Services

```bash
# Start Ollama
ollama serve

# Pull required models
ollama pull llama3.2:1b
ollama pull nomic-embed-text

# Start Selene web interface (automatically starts)
# Or manually: python -m selene.main web
```

### 3. Test Your Setup

```bash
# Test batch import
python -m selene.main batch-import --source drafts --tag selene --dry-run

# Test web interface
open http://localhost:8000
```

## 📦 Development to Production Workflow

### Recommended Git Workflow

```bash
# Development workflow
git checkout -b feature/new-feature
# ... make changes ...
git add -A
git commit -m "Add new feature"
git push origin feature/new-feature

# Merge to main
git checkout main
git merge feature/new-feature
git push origin main
```

### Deploy Updates

```bash
# On production machine
cd ~/selene-production
./deploy.sh
```

The deployment script:
1. Creates backup of current state
2. Pulls latest changes from main branch
3. Updates dependencies
4. Runs tests
5. Restarts services
6. Verifies deployment

### Rollback (if needed)

```bash
# Quick rollback
git reset --hard HEAD~1
./deploy.sh
```

## 🏠 Deployment Environments

### Option 1: Local Development Machine

**Best for**: Personal use, development, testing

```bash
# Setup
./scripts/production_setup.sh

# Set environment variables
export SELENE_PRODUCTION_DIR="$HOME/selene-production"
export SELENE_ENV="local"
```

**Pros**: Direct Drafts access, no network issues, easy debugging
**Cons**: Not always-on, single user

### Option 2: Home Server/NAS

**Best for**: Always-on processing, family use, local network access

**Recommended hardware**:
- Mac Mini M2 (excellent performance)
- Intel NUC or similar
- Raspberry Pi 4 (8GB RAM minimum)

**Setup**:
```bash
# On your home server
ssh your-server
git clone https://github.com/your-username/selene.git
cd selene
./scripts/production_setup.sh

# Configure for network access
export SELENE_WEB_HOST="0.0.0.0"
export SELENE_WEB_PORT="8000"
```

**Access**: `http://your-server-ip:8000`

### Option 3: Cloud VPS

**Best for**: Remote access, team collaboration, scalability

**Recommended providers**:
- DigitalOcean (good performance/price)
- Linode (developer-friendly)
- AWS EC2 (enterprise features)

**Minimum specs**: 4 CPU cores, 16GB RAM, 100GB SSD

**Setup**:
```bash
# On cloud server
ssh user@your-server
sudo apt update && sudo apt install -y git python3 python3-pip

# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Setup Selene
git clone https://github.com/your-username/selene.git
cd selene
./scripts/production_setup.sh
```

## 📊 Monitoring & Maintenance

### Production Monitoring

```bash
# Check system status
./scripts/monitor.sh

# View logs
tail -f logs/selene.log

# Check web interface
curl http://localhost:8000/health
```

### Automated Monitoring

Create cron job for regular checks:

```bash
# Add to crontab (crontab -e)
*/15 * * * * /path/to/selene-production/scripts/monitor.sh >> /tmp/selene-monitor.log 2>&1
```

### Log Management

```bash
# Rotate logs (add to crontab)
0 0 * * * find /path/to/selene-production/logs -name "*.log" -mtime +7 -delete
```

### Backup Strategy

```bash
# Manual backup
./backup.sh

# Automated backup (crontab)
0 2 * * * /path/to/selene-production/backup.sh
```

## 🔧 Configuration Management

### Environment Variables

Create `.env` file in production directory:

```bash
# Production configuration
SELENE_ENV=production
SELENE_DATA_DIR=/path/to/selene-production/data
SELENE_LOGS_DIR=/path/to/selene-production/logs

# Ollama settings
OLLAMA_HOST=http://localhost:11434
OLLAMA_PORT=11434
OLLAMA_TIMEOUT=120.0

# Web interface
SELENE_WEB_HOST=0.0.0.0
SELENE_WEB_PORT=8000

# Performance tuning
SELENE_BATCH_SIZE=5
SELENE_MAX_CONCURRENT=10
```

### Model Management

```bash
# Update models
ollama pull llama3.2:1b
ollama pull nomic-embed-text

# List available models
ollama list

# Remove old models
ollama rm old-model-name
```

## 🚨 Troubleshooting

### Common Issues

**1. Service won't start**
```bash
# Check logs
tail -f logs/selene.log

# Check port conflicts
lsof -i :8000

# Restart service
./deploy.sh
```

**2. Batch import fails**
```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Test with dry run
python -m selene.main batch-import --source drafts --dry-run

# Check Drafts database permissions
ls -la ~/Library/Application\ Support/Drafts/
```

**3. Web interface not accessible**
```bash
# Check if service is running
ps aux | grep selene

# Check firewall (if on server)
sudo ufw status
sudo ufw allow 8000

# Check binding
netstat -tlnp | grep :8000
```

**4. Memory issues**
```bash
# Reduce batch size
export SELENE_BATCH_SIZE=2

# Use smaller model
ollama pull llama3.2:1b

# Monitor memory usage
htop
```

### Performance Optimization

**For faster processing**:
```bash
# Increase batch size
export SELENE_BATCH_SIZE=10

# Use faster model
ollama pull llama3.2:1b

# Increase concurrent processing
export SELENE_MAX_CONCURRENT=15
```

**For lower resource usage**:
```bash
# Reduce batch size
export SELENE_BATCH_SIZE=2

# Use smaller model
ollama pull llama3.2:1b

# Limit concurrent operations
export SELENE_MAX_CONCURRENT=3
```

## 🔄 Update Process

### Regular Updates

```bash
# Weekly update routine
cd ~/selene-production
./backup.sh           # Backup first
git pull origin main   # Get latest changes
./deploy.sh           # Deploy updates
./scripts/monitor.sh  # Check status
```

### Major Updates

```bash
# For major version updates
./backup.sh                    # Full backup
git pull origin main           # Get updates
pip install -r requirements.txt  # Update dependencies
./deploy.sh                    # Deploy
# Test functionality thoroughly
```

### Emergency Rollback

```bash
# Quick rollback to previous version
git reset --hard HEAD~1
./deploy.sh

# Restore from backup if needed
cp -r backup_directory/data ./
```

## 📱 Mobile & Remote Access

### Tailscale (Recommended)

```bash
# Install Tailscale on server and devices
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# Access from anywhere: http://tailscale-ip:8000
```

### SSH Tunnel

```bash
# Create tunnel from your device
ssh -L 8000:localhost:8000 user@your-server

# Access: http://localhost:8000
```

### VPN Setup

Configure your router's VPN or use cloud VPN service for secure remote access.

## 📈 Scaling

### Single User → Multiple Users

```bash
# Configure for multiple users
export SELENE_WEB_HOST="0.0.0.0"
export SELENE_WEB_PORT="8000"

# Add authentication (future feature)
# Set up user management
```

### Performance Scaling

```bash
# Use more powerful hardware
# Increase batch processing
export SELENE_BATCH_SIZE=20

# Use multiple models
ollama pull llama3.2
ollama pull mistral

# Consider distributed processing (future feature)
```

## 🔐 Security

### Basic Security

```bash
# Firewall configuration
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 8000

# Keep system updated
sudo apt update && sudo apt upgrade

# Regular backups
./backup.sh
```

### Advanced Security

```bash
# Use reverse proxy (nginx)
sudo apt install nginx

# SSL certificates (Let's Encrypt)
sudo apt install certbot

# Access controls
# Configure IP restrictions
# Set up authentication
```

## 🎯 Production Checklist

**Before going live**:
- [ ] Production setup completed
- [ ] Ollama installed and models pulled
- [ ] Web interface accessible
- [ ] Batch import tested with dry run
- [ ] Backup script tested
- [ ] Monitoring script configured
- [ ] Logs properly configured
- [ ] Firewall configured (if needed)
- [ ] Regular update schedule planned

**Regular maintenance**:
- [ ] Weekly: Check logs and run monitor script
- [ ] Monthly: Update dependencies and models
- [ ] Quarterly: Full backup and disaster recovery test
- [ ] As needed: Deploy new features

## 📞 Support

**Logs**: Check `logs/selene.log` for detailed error information
**Health check**: Run `./scripts/monitor.sh`
**Community**: Create issues on GitHub repository
**Documentation**: See `docs/` directory for detailed guides

Your production Selene system is now ready for daily note processing! 🚀