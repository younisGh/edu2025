@echo off
echo Getting Android Debug SHA-256 Fingerprint...
echo.

REM Check if keytool exists
where keytool >nul 2>nul
if %errorlevel% neq 0 (
    echo Error: keytool not found. Please make sure Java JDK is installed and in PATH.
    echo You can download it from: https://www.oracle.com/java/technologies/downloads/
    pause
    exit /b 1
)

REM Check if debug keystore exists
if not exist "%USERPROFILE%\.android\debug.keystore" (
    echo Error: Debug keystore not found at %USERPROFILE%\.android\debug.keystore
    echo Please run 'flutter doctor' to generate it or create an Android project first.
    pause
    exit /b 1
)

echo Debug keystore found. Getting SHA-256 fingerprint...
echo.

keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android | findstr "SHA256"

echo.
echo Copy the SHA256 fingerprint (without "SHA256:") and add it to your Firebase project:
echo 1. Go to Firebase Console
echo 2. Project Settings ^> General
echo 3. Your apps ^> Android app
echo 4. Add fingerprint
echo.
pause
