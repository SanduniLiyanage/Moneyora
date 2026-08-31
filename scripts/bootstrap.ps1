# -----------------------------------------------------------------------------
# Moneyora -- one-time project bootstrap
#
# Run ONCE, from the repo root, AFTER the Flutter SDK is installed:
#     .\scripts\bootstrap.ps1
#
# It is idempotent-ish: safe to re-run, but it will not overwrite lib/ files
# you have already written.
# -----------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

Write-Host "`n=== 0. Preflight ===" -ForegroundColor Cyan
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not on PATH. Install it first -- see docs/SETUP.md."
}
flutter --version
flutter doctor

Write-Host "`n=== 1. Generate platform folders (android/, ios/, main.dart) ===" -ForegroundColor Cyan
# NOTE: the SDD says `flutter create ... moneyora`, which nests the app in a
# subfolder. We create IN PLACE ('.') because this git repo IS the project root.
# --platforms limits scaffolding to the two targets the SRS actually requires.
flutter create --org com.moneyora --project-name moneyora --platforms android,ios .

Write-Host "`n=== 2. Runtime dependencies ===" -ForegroundColor Cyan
# `pub add` (not hand-pinned versions) so the resolver picks the newest release
# compatible with your Flutter SDK. The version numbers in SDD Sec 10.1 were
# written in mid-2026 and are already stale.
flutter pub add `
    flutter_riverpod `
    sqflite_sqlcipher `
    path_provider `
    path `
    google_mlkit_text_recognition `
    fl_chart `
    go_router `
    image_picker `
    local_auth `
    flutter_local_notifications `
    flutter_secure_storage `
    fpdart `
    intl `
    share_plus `
    http `
    equatable `
    connectivity_plus

Write-Host "`n=== 3. Dev dependencies ===" -ForegroundColor Cyan
flutter pub add --dev `
    flutter_lints `
    mockito `
    build_runner `
    very_good_analysis

Write-Host "`n=== 4. Localization + resolve ===" -ForegroundColor Cyan
flutter pub add flutter_localizations --sdk=flutter
flutter pub get

Write-Host "`n=== 5. Verify ===" -ForegroundColor Cyan
flutter analyze
flutter test

Write-Host "`nBootstrap complete. Commit pubspec.yaml AND pubspec.lock." -ForegroundColor Green
