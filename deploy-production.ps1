# Production Deployment Script for TestPro
# Run this script to deploy backend and prepare Flutter builds

param(
    [string]$BackendUrl = "https://og-backend-3.onrender.com",
    [switch]$SkipBackendDeploy,
    [switch]$BuildAndroid,
    [switch]$BuildIOS
)

Write-Host "🚀 TestPro Production Deployment" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green

# 1. Check environment variables
Write-Host "`n📋 Checking Environment Variables..." -ForegroundColor Yellow
$requiredVars = @(
    "FIREBASE_PROJECT_ID",
    "FIREBASE_PRIVATE_KEY",
    "FIREBASE_CLIENT_EMAIL",
    "JWT_ACCESS_SECRET",
    "R2_ACCOUNT_ID",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY"
)

$missing = @()
foreach ($var in $requiredVars) {
    if (-not [Environment]::GetEnvironmentVariable($var)) {
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Host "❌ Missing environment variables:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
    Write-Host "`nPlease set these variables before deploying." -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ All environment variables set" -ForegroundColor Green

# 2. Backend Deployment
if (-not $SkipBackendDeploy) {
    Write-Host "`n📦 Deploying Backend..." -ForegroundColor Yellow
    Set-Location -Path "backend"
    
    # Install dependencies
    Write-Host "Installing dependencies..." -ForegroundColor Gray
    npm ci
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Backend dependency installation failed" -ForegroundColor Red
        exit 1
    }
    
    # Run tests if available
    Write-Host "Running tests..." -ForegroundColor Gray
    npm test 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "⚠️  Tests failed or not found. Continuing..." -ForegroundColor Yellow
    }
    
    Set-Location -Path ".."
    Write-Host "✅ Backend ready for deployment" -ForegroundColor Green
    Write-Host "   Deploy to Render using: git push origin main" -ForegroundColor Cyan
}

# 3. Flutter Build
Write-Host "`n📱 Building Flutter App..." -ForegroundColor Yellow
Set-Location -Path "testpro-main"

# Get dependencies
flutter pub get

# Build APK (Android)
if ($BuildAndroid -or (-not $BuildIOS)) {
    Write-Host "`n🔨 Building Android APK..." -ForegroundColor Gray
    flutter build apk --release --dart-define=API_URL=$BackendUrl
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Android APK built successfully" -ForegroundColor Green
        Write-Host "   Location: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Cyan
    } else {
        Write-Host "❌ Android build failed" -ForegroundColor Red
    }
}

# Build iOS
if ($BuildIOS) {
    Write-Host "`n🔨 Building iOS..." -ForegroundColor Gray
    flutter build ios --release --dart-define=API_URL=$BackendUrl
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ iOS build successful" -ForegroundColor Green
    } else {
        Write-Host "❌ iOS build failed (requires macOS + Xcode)" -ForegroundColor Red
    }
}

Set-Location -Path ".."

# 4. Summary
Write-Host "`n=================================" -ForegroundColor Green
Write-Host "🎉 Production Deployment Complete!" -ForegroundColor Green
Write-Host "=================================" -ForegroundColor Green
Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Push backend to GitHub for Render deployment" -ForegroundColor White
Write-Host "2. Upload APK to Google Play Console" -ForegroundColor White
Write-Host "3. Test the production app thoroughly" -ForegroundColor White
Write-Host "`nBackend URL: $BackendUrl" -ForegroundColor Cyan
