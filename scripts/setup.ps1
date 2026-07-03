# Bhromon — Local Development Setup Script (Windows PowerShell)
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "   Setting up Bhromon Development Environment   " -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# 1. Check Flutter
Write-Host "`n[1/4] Checking Flutter installation..." -ForegroundColor Yellow
if (Get-Command flutter -ErrorAction SilentlyContinue) {
    $flutterVersion = flutter --version
    Write-Host "Flutter is installed: $flutterVersion" -ForegroundColor Green
} else {
    Write-Error "Flutter SDK is not found. Please install Flutter and add it to your PATH."
    Exit 1
}

# 2. Install Melos
Write-Host "`n[2/4] Installing/updating Melos globally..." -ForegroundColor Yellow
dart pub global activate melos 2>&1 | Write-Host

# 3. Bootstrap workspace
Write-Host "`n[3/4] Running Melos bootstrap..." -ForegroundColor Yellow
& "$env:USERPROFILE\AppData\Local\Pub\Cache\bin\melos" bootstrap

# 4. Generate generated files
Write-Host "`n[4/4] Running code generator..." -ForegroundColor Yellow
& "$env:USERPROFILE\AppData\Local\Pub\Cache\bin\melos" run build_runner

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host "  Setup completed successfully!" -ForegroundColor Green
Write-Host "  Run 'flutter run' to start the application." -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
