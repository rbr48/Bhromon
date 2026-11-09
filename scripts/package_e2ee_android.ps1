# Packages precompiled libe2ee_olm.so binaries into android/app/src/main/jniLibs
# for Android APK and AAB packaging (E2EE_DESIGN.md, Milestone M4).

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path "$PSScriptRoot\.."
$srcDir = Join-Path $repoRoot "native\e2ee_olm\dist\android"
$destDir = Join-Path $repoRoot "android\app\src\main\jniLibs"

if (-not (Test-Path $srcDir)) {
    Write-Error "Source directory $srcDir does not exist. Build the native libraries first."
    exit 1
}

$abis = @("arm64-v8a", "armeabi-v7a", "x86_64")

foreach ($abi in $abis) {
    $srcFile = Join-Path $srcDir "$abi\libe2ee_olm.so"
    $targetAbiDir = Join-Path $destDir $abi
    if (Test-Path $srcFile) {
        if (-not (Test-Path $targetAbiDir)) {
            New-Item -ItemType Directory -Force -Path $targetAbiDir | Out-Null
        }
        Copy-Item -Force $srcFile (Join-Path $targetAbiDir "libe2ee_olm.so")
        Write-Host "Copied $srcFile -> $targetAbiDir"
    } else {
        Write-Warning "$srcFile not found."
    }
}

Write-Host "Successfully packaged E2EE native libraries into $destDir"
