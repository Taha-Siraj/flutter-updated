# 🔧 Build Verification Script for Smart Attendance
# Run this script to verify Android and iOS builds

Write-Host "🚀 Starting Build Verification..." -ForegroundColor Cyan
Write-Host ""

# Step 1: Clean
Write-Host "🧹 Step 1: Cleaning build cache..." -ForegroundColor Yellow
flutter clean
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Flutter clean failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Clean complete" -ForegroundColor Green
Write-Host ""

# Step 2: Get dependencies
Write-Host "📦 Step 2: Getting dependencies..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Pub get failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Dependencies resolved" -ForegroundColor Green
Write-Host ""

# Step 3: Analyze code
Write-Host "🔍 Step 3: Running static analysis..." -ForegroundColor Yellow
flutter analyze --no-pub
if ($LASTEXITCODE -ne 0) {
    Write-Host "⚠️ Analysis found issues (check above)" -ForegroundColor Yellow
} else {
    Write-Host "✅ No analysis issues" -ForegroundColor Green
}
Write-Host ""

# Step 4: Build Android APK (Release)
Write-Host "🤖 Step 4: Building Android APK (Release)..." -ForegroundColor Yellow
flutter build apk --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Android build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Android APK built successfully" -ForegroundColor Green
Write-Host "   📱 APK location: android\app\build\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan
Write-Host ""

# Step 5: Build iOS (if on macOS)
if ($IsMacOS) {
    Write-Host "🍎 Step 5: Building iOS (Release, no codesign)..." -ForegroundColor Yellow
    flutter build ios --release --no-codesign
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ iOS build failed!" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ iOS build successful" -ForegroundColor Green
} else {
    Write-Host "⏭️ Step 5: Skipping iOS build (not on macOS)" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "🎉 BUILD VERIFICATION COMPLETE!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""
Write-Host "✅ Android APK: android\app\build\outputs\flutter-apk\app-release.apk" -ForegroundColor Green

if ($IsMacOS) {
    Write-Host "✅ iOS Build: Successful" -ForegroundColor Green
}

Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Install APK on Android device: adb install -r android\app\build\outputs\flutter-apk\app-release.apk" -ForegroundColor White
Write-Host "   2. Follow testing instructions in BACKGROUND_TESTING_NOTES.md" -ForegroundColor White
Write-Host ""

