@echo off
setlocal
cd /d "%~dp0"

if not exist ".git" (
    echo [INFO] Khoi tao Git repository lan dau...
    git init
    if errorlevel 1 (
        echo [ERROR] git init that bai.
        pause
        exit /b 1
    )
    git branch -M main
)

for /f "delims=" %%A in ('git remote get-url origin 2^>nul') do set "REMOTE_URL=%%A"
if "%REMOTE_URL%"=="" (
    set /p "REMOTE_URL=Nhap Git Remote URL (vi du: https://github.com/username/export_image_nfc.git): "
    if "%REMOTE_URL%"=="" (
        echo [ERROR] Git remote URL khong duoc de trong.
        pause
        exit /b 1
    )
    git remote add origin "%REMOTE_URL%"
    if errorlevel 1 (
        echo [ERROR] Them remote that bai.
        pause
        exit /b 1
    )
)

for /f "delims=" %%A in ('git config user.name 2^>nul') do set "GIT_NAME=%%A"
if "%GIT_NAME%"=="" (
    set /p "GIT_NAME=Nhap Git User Name: "
    if "%GIT_NAME%"=="" (
        echo [ERROR] Git name khong duoc de trong.
        pause
        exit /b 1
    )
    git config user.name "%GIT_NAME%"
)

for /f "delims=" %%A in ('git config user.email 2^>nul') do set "GIT_EMAIL=%%A"
if "%GIT_EMAIL%"=="" (
    set /p "GIT_EMAIL=Nhap Git Email: "
    if "%GIT_EMAIL%"=="" (
        echo [ERROR] Git email khong duoc de trong.
        pause
        exit /b 1
    )
    git config user.email "%GIT_EMAIL%"
)

echo.
echo ========================================================
echo        CCCD NFC EXPORT - COMMIT & BUILD GITHUB DEB
echo ========================================================
set /p "MESSAGE=Nhap noi dung commit: "

if "%MESSAGE%"=="" (
    echo [ERROR] Noi dung commit khong duoc de trong.
    pause
    exit /b 1
)

echo.
echo [1/3] git add .
git add .
if errorlevel 1 (
    echo git add that bai.
    pause
    exit /b 1
)

git diff --cached --quiet
if not errorlevel 1 (
    echo Khong co thay doi de commit.
    pause
    exit /b 0
)

echo [2/3] git commit
git commit -m "%MESSAGE%"
if errorlevel 1 (
    echo git commit that bai.
    pause
    exit /b 1
)

echo [3/3] git push origin main
git push origin main
if errorlevel 1 (
    echo git push that bai.
    pause
    exit /b 1
)

echo.
echo ========================================================
echo   Push thanh cong! GitHub Actions dang build file .deb
echo   Ban co the vao tab Actions tren GitHub de tai file ve.
echo ========================================================
pause
