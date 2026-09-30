@echo off
setlocal
rem JDK 17 and the Android SDK: set JAVA_HOME and ANDROID_HOME, or edit the defaults below.
if not defined JAVA_HOME set "JAVA_HOME=C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"
if not defined ANDROID_HOME set "ANDROID_HOME=C:\android_sdk"
cd /d "%~dp0"

if exist keystore.properties (
    echo Signing with the key from keystore.properties.
) else (
    echo ERROR: keystore.properties not found. A release build needs the signing key.
    echo See the top of app\build.gradle.kts.
    pause
    exit /b 1
)
echo.

rem "clean" fails when a background process keeps an old build file open. The adb server keeps
rem app-debug.apk open after an install, and Gradle daemons can keep other files open.
"%ANDROID_HOME%\platform-tools\adb.exe" kill-server >nul 2>&1
call gradlew.bat --stop >nul 2>&1

call gradlew.bat clean assembleRelease --console=plain
if errorlevel 1 (
    echo.
    echo BUILD FAILED. If the error was "Unable to delete directory", run: gradlew.bat --stop
    pause
    exit /b 1
)

echo.
echo Release APK: app\build\outputs\apk\release\app-release.apk
pause
