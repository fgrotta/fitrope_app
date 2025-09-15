#!/bin/sh
set -e

echo "🚀 Starting Flutter pre-build setup..."

# Set Flutter environment
export FLUTTER_ROOT=/usr/local/bin
export PATH="$FLUTTER_ROOT/bin:$PATH"

# Verify Flutter installation
echo "📱 Flutter version:"
flutter --version

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get Flutter dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Generate Flutter files
echo "🔧 Generating Flutter files..."
flutter packages pub run build_runner build --delete-conflicting-outputs || echo "⚠️ Build runner failed, continuing..."

# Pre-build Flutter for iOS to generate Generated.xcconfig
echo "🏗️ Pre-building Flutter for iOS..."
flutter build ios --no-codesign --simulator || echo "⚠️ Flutter build failed, continuing..."

# Install iOS dependencies
echo "🍎 Installing iOS dependencies..."
cd ios
pod install --repo-update
cd ..

# Verify Generated.xcconfig exists, create if not
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "✅ Generated.xcconfig exists"
else
    echo "❌ Generated.xcconfig not found, creating manually..."
    cat > ios/Flutter/Generated.xcconfig << EOF
FLUTTER_ROOT=/usr/local/bin
FLUTTER_APPLICATION_PATH=$(pwd)
FLUTTER_TARGET=lib/main.dart
FLUTTER_BUILD_DIR=build
FLUTTER_BUILD_NAME=1.0.0
FLUTTER_BUILD_NUMBER=8
EOF
    echo "✅ Generated.xcconfig created successfully"
fi

# Verify Pods files exist
if [ -f "ios/Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig" ]; then
    echo "✅ Pods configuration files exist"
else
    echo "❌ Pods configuration files missing, reinstalling..."
    cd ios
    pod install --repo-update
    cd ..
fi

echo "✅ Flutter pre-build setup completed!"
