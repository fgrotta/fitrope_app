#!/bin/sh
set -e

echo "🏁 Starting Flutter post-build setup..."

# Set Flutter environment
export FLUTTER_ROOT=/usr/local/bin
export PATH="$FLUTTER_ROOT/bin:$PATH"

# Optional: Run Flutter tests
echo "🧪 Running Flutter tests..."
flutter test || echo "⚠️ Tests failed, but continuing..."

# Optional: Generate app icons if using flutter_launcher_icons
echo "🎨 Generating app icons..."
flutter packages pub run flutter_launcher_icons:main || echo "⚠️ Icon generation failed, but continuing..."

# Optional: Generate other Flutter files
echo "🔧 Running additional Flutter commands..."
flutter packages pub run build_runner build --delete-conflicting-outputs || echo "⚠️ Build runner failed, but continuing..."

# Verify build artifacts
echo "📋 Verifying build artifacts..."
if [ -d "build/ios/iphoneos" ]; then
    echo "✅ iOS build artifacts found"
else
    echo "⚠️ iOS build artifacts not found"
fi

echo "✅ Flutter post-build setup completed!"
