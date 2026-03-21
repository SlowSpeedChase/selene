#!/bin/bash

# Selene Chat - Build Script

set -e

echo "🔨 Building Selene Chat..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
swift package clean

# Resolve dependencies
echo "📦 Resolving dependencies..."
swift package resolve

# Build
echo "🏗️  Building..."
swift build -c release

echo "✅ Build complete!"
echo ""
echo "To run the app:"
echo "  swift run"
echo ""
echo "Or to open in Xcode:"
echo "  open Package.swift"
