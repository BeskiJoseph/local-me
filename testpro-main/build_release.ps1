# ============================================================
# Production Release Build Script
# ============================================================
# Usage:  .\build_release.ps1
# Output: build\app\outputs\flutter-apk\app-release.apk
#
# Flags:
#   --obfuscate           Obfuscates Dart code symbols
#   --split-debug-info    Exports debug symbols for Crashlytics
#                         (Required for readable stack traces in Firebase Console)
# ============================================================

Write-Host "🔨 Building Production APK with obfuscation..." -ForegroundColor Cyan

# Create debug symbols directory if it doesn't exist
if (-not (Test-Path "build/debug-info")) {
    New-Item -ItemType Directory -Path "build/debug-info" -Force | Out-Null
}

flutter build apk `
    --release `
    --obfuscate `
    --split-debug-info=build/debug-info

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Release APK built successfully!" -ForegroundColor Green
    Write-Host "📦 APK:          build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Yellow
    Write-Host "🔑 Debug Symbols: build\debug-info\" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "⚠️  IMPORTANT: Upload debug symbols to Firebase for readable crash reports:" -ForegroundColor Red
    Write-Host "   firebase crashlytics:symbols:upload --app=YOUR_APP_ID build/debug-info" -ForegroundColor White
} else {
    Write-Host "❌ Build failed. Check errors above." -ForegroundColor Red
}
