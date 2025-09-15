#!/bin/sh
set -e

# This is the main entry point for Xcode Cloud CI scripts
echo "🚀 Starting Xcode Cloud CI for Flutter app..."

# Make scripts executable
chmod +x ci_scripts/ci_pre_xcodebuild.sh
chmod +x ci_scripts/ci_post_clone.sh
chmod +x ci_scripts/ci_post_xcodebuild.sh

# Run post-clone script
echo "🔧 Running post-clone setup..."
./ci_scripts/ci_post_clone.sh

# Run pre-build script
echo "🏗️ Running pre-build setup..."
./ci_scripts/ci_pre_xcodebuild.sh

echo "✅ Xcode Cloud CI setup completed!"
