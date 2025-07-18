#!/bin/bash

# Selene Web Server Management Script
# Manage production and development web servers on different ports

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default configuration
PROD_PORT=8000
DEV_PORT=8080
HOST=0.0.0.0
IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')

show_help() {
    cat << EOF
Selene Web Server Management

Usage: $0 [COMMAND] [OPTIONS]

COMMANDS:
    start-prod      Start production server (port $PROD_PORT)
    start-dev       Start development server (port $DEV_PORT)
    start-both      Start both servers
    stop-all        Stop all Selene web servers
    status          Show running servers
    urls            Show access URLs

OPTIONS:
    --prod-port PORT    Production port (default: $PROD_PORT)
    --dev-port PORT     Development port (default: $DEV_PORT)
    --host HOST         Host to bind to (default: $HOST)

EXAMPLES:
    $0 start-both               # Start both servers
    $0 start-prod --prod-port 8001
    $0 stop-all
    $0 status
EOF
}

show_urls() {
    echo "🌐 Selene Web Interface URLs"
    echo "================================="
    echo "Production:  http://$IP:$PROD_PORT"
    echo "Development: http://$IP:$DEV_PORT"
    echo ""
    echo "API Documentation:"
    echo "Production:  http://$IP:$PROD_PORT/api/docs"
    echo "Development: http://$IP:$DEV_PORT/api/docs"
}

start_server() {
    local env=$1
    local port=$2
    local log_file="/tmp/selene-${env}.log"
    
    echo "🚀 Starting $env server on port $port..."
    cd "$PROJECT_DIR"
    nohup python3 -m selene.main web --host $HOST --port $port > "$log_file" 2>&1 &
    local pid=$!
    echo "   PID: $pid"
    echo "   Log: $log_file"
    echo "   URL: http://$IP:$port"
}

stop_servers() {
    echo "🛑 Stopping all Selene web servers..."
    pkill -f "selene.main web" && echo "   All servers stopped" || echo "   No servers running"
}

show_status() {
    echo "📊 Selene Web Server Status"
    echo "=========================="
    local processes=$(ps aux | grep "selene.main web" | grep -v grep)
    if [ -n "$processes" ]; then
        echo "$processes"
        echo ""
        echo "Active ports:"
        lsof -i :$PROD_PORT :$DEV_PORT 2>/dev/null | grep LISTEN || echo "   None found"
    else
        echo "No Selene web servers running"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --prod-port)
            PROD_PORT="$2"
            shift 2
            ;;
        --dev-port)
            DEV_PORT="$2"
            shift 2
            ;;
        --host)
            HOST="$2"
            shift 2
            ;;
        start-prod)
            start_server "production" "$PROD_PORT"
            show_urls
            exit 0
            ;;
        start-dev)
            start_server "development" "$DEV_PORT"
            show_urls
            exit 0
            ;;
        start-both)
            start_server "production" "$PROD_PORT"
            sleep 2
            start_server "development" "$DEV_PORT"
            echo ""
            show_urls
            exit 0
            ;;
        stop-all)
            stop_servers
            exit 0
            ;;
        status)
            show_status
            exit 0
            ;;
        urls)
            show_urls
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Default action
show_help