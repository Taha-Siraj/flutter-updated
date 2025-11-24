#!/bin/bash
# 🔧 Build Verification Script for Smart Attendance (macOS/Linux)
# Run this script to verify Android and iOS builds

echo "🚀 Starting Build Verification..."
echo ""

# Step 1: Clean
echo "🧹 Step 1: Cleaning build cache..."
flutter clean
if [ $? -ne 0 ]; then
    echo "❌ Flutter clean failed!"
    exit 1
fi
echo "✅ Clean complete"
echo ""

# Step 2: Get dependencies
echo "📦 Step 2: Getting dependencies..."
flutter pub get
if [ $? -ne 0 ]; then
    echo "❌ Pub get failed!"
    exit 1
fi
echo "✅ Dependencies resolved"
echo ""

# Step 3: Analyze code
echo "🔍 Step 3: Running static analysis..."
flutter analyze --no-pub
if [ $? -ne 0 ]; then
    echo "⚠️ Analysis found issues (check above)"
else
    echo "✅ No analysis issues"
fi
echo ""

# Step 4: Build Android APK (Release)
echo "🤖 Step 4: Building Android APK (Release)..."
flutter build apk --release
if [ $? -ne 0 ]; then
    echo "❌ Android build failed!"
    exit 1
fi
echo "✅ Android APK built successfully"
echo "   📱 APK location: android/app/build/outputs/flutter-apk/app-release.apk"
echo ""

# Step 5: Build iOS (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Step 5: Building iOS (Release, no codesign)..."
    flutter build ios --release --no-codesign
    if [ $? -ne 0 ]; then
        echo "❌ iOS build failed!"
        exit 1
    fi
    echo "✅ iOS build successful"
else
    echo "⏭️ Step 5: Skipping iOS build (not on macOS)"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 BUILD VERIFICATION COMPLETE!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Android APK: android/app/build/outputs/flutter-apk/app-release.apk"

if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "✅ iOS Build: Successful"
fi

echo ""
echo "📋 Next Steps:"
echo "   1. Install APK on Android device: adb install -r android/app/build/outputs/flutter-apk/app-release.apk"
echo "   2. Follow testing instructions in BACKGROUND_TESTING_NOTES.md"
echo ""

