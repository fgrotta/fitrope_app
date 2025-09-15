#!/bin/sh
set -e

echo "🔧 Setting up Flutter environment for Xcode Cloud..."

# Set Flutter environment
export FLUTTER_ROOT=/usr/local/bin
export PATH="$FLUTTER_ROOT/bin:$PATH"

# Verify Flutter installation
echo "📱 Flutter version:"
flutter --version

# Enable Flutter web support if needed
flutter config --enable-web

# Set Flutter build mode
export FLUTTER_BUILD_MODE=release

# Set additional Flutter environment variables
export FLUTTER_APPLICATION_PATH=$(pwd)
export FLUTTER_TARGET=lib/main.dart
export FLUTTER_BUILD_DIR=build

echo "✅ Flutter environment setup completed!"
