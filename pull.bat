@echo off
echo Performing Git operations...

rem 获取脚本所在目录的绝对路径
set "script_dir=%~dp0"

rem 切换到脚本所在目录
cd /d "%script_dir%"


rem Pull changes from remote repository
git pull

echo Git operations completed.
pause
