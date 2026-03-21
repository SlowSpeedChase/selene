#!/bin/bash
#
# Setup whisper.cpp for Voice Memo transcription
#
# Installs whisper.cpp with Metal acceleration, downloads the medium model,
# creates output directories, and installs the launchd agent.
#
# Usage: ./scripts/setup-whisper.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

WHISPER_DIR="$HOME/.local/whisper.cpp"
MODEL_NAME="ggml-medium.bin"
MODEL_DIR="$WHISPER_DIR/models"
VOICE_MEMOS_DIR="$HOME/VoiceMemos"

echo "========================================"
echo "  Selene Voice Memo Transcription Setup"
echo "========================================"
echo ""

# Step 1: Check prerequisites
echo "Step 1: Checking prerequisites..."
echo "----------------------------------------"

# Check Apple Silicon
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo -e "  ${RED}ERROR: This script requires Apple Silicon (arm64). Detected: $ARCH${NC}"
    exit 1
fi
echo -e "  ${GREEN}OK${NC} Apple Silicon detected"

# Check Xcode CLI tools
if ! xcode-select -p &>/dev/null; then
    echo -e "  ${YELLOW}Installing Xcode Command Line Tools...${NC}"
    xcode-select --install
    echo "  Re-run this script after Xcode CLI tools finish installing."
    exit 1
fi
echo -e "  ${GREEN}OK${NC} Xcode CLI tools installed"

# Check cmake
if ! command -v cmake &>/dev/null; then
    if ! command -v brew &>/dev/null; then
        echo -e "  ${RED}ERROR: cmake not found and Homebrew not installed.${NC}"
        echo "  Install Homebrew from https://brew.sh, then: brew install cmake"
        exit 1
    fi
    echo -e "  ${YELLOW}cmake not found. Installing via Homebrew...${NC}"
    brew install cmake
fi
echo -e "  ${GREEN}OK${NC} cmake available"

# Check ffmpeg
if ! command -v ffmpeg &>/dev/null; then
    if ! command -v brew &>/dev/null; then
        echo -e "  ${RED}ERROR: ffmpeg not found and Homebrew not installed.${NC}"
        echo "  Install Homebrew from https://brew.sh, then: brew install ffmpeg"
        exit 1
    fi
    echo -e "  ${YELLOW}ffmpeg not found. Installing via Homebrew...${NC}"
    brew install ffmpeg
fi
echo -e "  ${GREEN}OK${NC} ffmpeg available"
echo ""

# Step 2: Install whisper.cpp
echo "Step 2: Installing whisper.cpp..."
echo "----------------------------------------"

if [ -f "$WHISPER_DIR/build/bin/whisper-cli" ]; then
    echo -e "  ${GREEN}OK${NC} whisper.cpp already installed at $WHISPER_DIR"
else
    mkdir -p "$HOME/.local"

    if [ -d "$WHISPER_DIR" ]; then
        echo "  Updating existing clone..."
        (cd "$WHISPER_DIR" && git pull)
    else
        echo "  Cloning whisper.cpp..."
        git clone https://github.com/ggerganov/whisper.cpp.git "$WHISPER_DIR"
    fi

    echo "  Building with Metal acceleration..."
    (
        cd "$WHISPER_DIR"
        cmake -B build -DWHISPER_METAL=ON
        cmake --build build -j$(sysctl -n hw.ncpu) --config Release
    )

    if [ -f "$WHISPER_DIR/build/bin/whisper-cli" ]; then
        echo -e "  ${GREEN}OK${NC} whisper.cpp built successfully"
    else
        echo -e "  ${RED}ERROR: Build failed. whisper-cli binary not found.${NC}"
        echo "  Check the build output above for errors."
        exit 1
    fi
fi
echo ""

# Step 3: Download model
echo "Step 3: Downloading model ($MODEL_NAME)..."
echo "----------------------------------------"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_DIR/$MODEL_NAME" ]; then
    echo -e "  ${GREEN}OK${NC} Model already downloaded"
else
    echo "  Downloading medium model (~1.5GB)..."
    (cd "$WHISPER_DIR" && bash models/download-ggml-model.sh medium)
    if [ ! -f "$MODEL_DIR/$MODEL_NAME" ]; then
        echo -e "  ${RED}ERROR: Model download failed. File not found at $MODEL_DIR/$MODEL_NAME${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}OK${NC} Model downloaded"
fi
echo ""

# Step 4: Create output directories
echo "Step 4: Creating output directories..."
echo "----------------------------------------"

mkdir -p "$VOICE_MEMOS_DIR/archive"
mkdir -p "$VOICE_MEMOS_DIR/transcripts"
mkdir -p "$PROJECT_DIR/logs"

if [ ! -f "$VOICE_MEMOS_DIR/.processed.json" ]; then
    echo '{"files":{}}' > "$VOICE_MEMOS_DIR/.processed.json"
    echo -e "  ${GREEN}OK${NC} Initialized .processed.json"
else
    echo -e "  ${GREEN}OK${NC} .processed.json already exists"
fi

echo -e "  ${GREEN}OK${NC} ~/VoiceMemos/archive/"
echo -e "  ${GREEN}OK${NC} ~/VoiceMemos/transcripts/"
echo ""

# Step 5: Install launchd agent
echo "Step 5: Installing launchd agent..."
echo "----------------------------------------"

PLIST_NAME="com.selene.transcribe-voice-memos.plist"
PLIST_SRC="$PROJECT_DIR/launchd/$PLIST_NAME"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

if [ ! -f "$PLIST_SRC" ]; then
    echo -e "  ${YELLOW}WARNING: Plist not found at $PLIST_SRC${NC}"
    echo "  The launchd agent has not been created yet."
    echo "  You can install it later with: ./scripts/install-launchd.sh"
else
    mkdir -p "$HOME/Library/LaunchAgents"

    # Unload if already loaded
    if [ -f "$PLIST_DST" ]; then
        launchctl unload "$PLIST_DST" 2>/dev/null || true
    fi

    cp "$PLIST_SRC" "$PLIST_DST"
    launchctl load "$PLIST_DST"
    echo -e "  ${GREEN}OK${NC} Agent installed and loaded"
fi
echo ""

# Step 6: Smoke test
echo "Step 6: Smoke test..."
echo "----------------------------------------"

TEMP_WAV=$(mktemp /tmp/whisper-test-XXXXXX.wav)
trap 'rm -f "$TEMP_WAV"' EXIT

# Generate a 1-second silent WAV file
ffmpeg -f lavfi -i anullsrc=r=16000:cl=mono -t 1 -c:a pcm_s16le "$TEMP_WAV" -y 2>/dev/null

echo "  Running whisper.cpp on silent audio..."
if "$WHISPER_DIR/build/bin/whisper-cli" \
    -m "$MODEL_DIR/$MODEL_NAME" \
    -f "$TEMP_WAV" \
    --no-timestamps \
    -t 4 2>/dev/null; then
    echo -e "  ${GREEN}OK${NC} Whisper transcription works"
else
    echo -e "  ${RED}ERROR: Whisper smoke test failed${NC}"
    exit 1
fi
echo ""

echo "========================================"
echo -e "  ${GREEN}Setup complete!${NC}"
echo "========================================"
echo ""
echo "Voice Memos will be automatically transcribed."
echo ""
echo "Output:"
echo "  Transcripts: ~/VoiceMemos/transcripts/"
echo "  Archives:    ~/VoiceMemos/archive/"
echo "  Manifest:    ~/VoiceMemos/.processed.json"
echo ""
echo "Logs:"
echo "  $PROJECT_DIR/logs/transcribe-voice-memos.log"
echo "  $PROJECT_DIR/logs/transcribe-voice-memos.error.log"
echo ""
