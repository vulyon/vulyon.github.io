@echo off
echo Performing Git operations...

rem 获取脚本所在目录的绝对路径
set "script_dir=%~dp0"

rem 切换到脚本所在目录
cd /d "%script_dir%"

rem Add all changes
git add .

rem Commit changes with an empty message
git commit -m "Automated commit"

rem Push changes to remote repository
git push

echo Git operations completed.
pause
