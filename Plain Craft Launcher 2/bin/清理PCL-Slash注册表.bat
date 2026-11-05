@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
rem Copyright (C) 2026 PCL-Slash contributors
rem SPDX-License-Identifier: GPL-3.0-only
title 清理 PCL-Slash 注册表

echo 将删除当前 Windows 用户的以下注册表项及其全部内容：
echo   HKEY_CURRENT_USER\Software\PCL-Slash
echo.
echo 请先关闭 PCL-Slash，避免启动器重新写入设置。
echo 注册表中的设置和登录缓存会被清除。
echo PCL2 的注册表、PCL\Setup.ini 和游戏文件不会被删除。
echo.
"%SystemRoot%\System32\choice.exe" /C YN /N /M "确认清理？[Y/N]: "
if errorlevel 3 goto failed
if errorlevel 2 goto cancelled
if errorlevel 1 goto clean
goto cancelled

:clean
"%SystemRoot%\System32\reg.exe" query "HKCU\Software\PCL-Slash" >nul 2>&1
if errorlevel 1 goto unreadable
"%SystemRoot%\System32\reg.exe" delete "HKCU\Software\PCL-Slash" /f
if errorlevel 1 goto failed
echo.
echo PCL-Slash 注册表已清理，重新打开启动器后会按需重新生成。
pause
exit /b 0

:cancelled
echo.
echo 已取消，未执行清理。
pause
exit /b 0

:unreadable
echo.
echo 未找到该注册表项或无法读取，本次未执行清理。
pause
exit /b 1

:failed
echo.
echo 清理未完成，请查看上方错误信息。
pause
exit /b 1
