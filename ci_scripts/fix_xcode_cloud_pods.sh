#!/bin/sh
set -e

echo "🔧 Fixing Xcode Cloud Pods issues..."

cd ios

# Ensure Pods directory exists
if [ ! -d "Pods" ]; then
    echo "❌ Pods directory not found, installing..."
    pod install --repo-update
fi

# Verify and recreate file lists if needed
PODS_TARGET_DIR="Pods/Target Support Files/Pods-Runner"

if [ ! -f "$PODS_TARGET_DIR/Pods-Runner-frameworks-Release-input-files.xcfilelist" ]; then
    echo "❌ Release input files missing, recreating..."
    pod install --repo-update
fi

if [ ! -f "$PODS_TARGET_DIR/Pods-Runner-frameworks-Release-output-files.xcfilelist" ]; then
    echo "❌ Release output files missing, recreating..."
    pod install --repo-update
fi

# Verify file contents
if [ -s "$PODS_TARGET_DIR/Pods-Runner-frameworks-Release-input-files.xcfilelist" ]; then
    echo "✅ Release input files exist and have content"
else
    echo "❌ Release input files empty, recreating..."
    pod install --repo-update
fi

if [ -s "$PODS_TARGET_DIR/Pods-Runner-frameworks-Release-output-files.xcfilelist" ]; then
    echo "✅ Release output files exist and have content"
else
    echo "❌ Release output files empty, recreating..."
    pod install --repo-update
fi

# Fix permissions
chmod -R 755 "$PODS_TARGET_DIR" || echo "⚠️ Permission fix failed, continuing..."

echo "✅ Xcode Cloud Pods issues fixed!"

cd ..
