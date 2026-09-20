@echo off
rem Kimi Code NVIDIA shim - remove o prompt_cache_key que a NVIDIA NIM rejeita (HTTP 400)
rem Apague este arquivo para nao iniciar junto com o Windows.
set "PYW=C:\Program Files\Python313\pythonw.exe"
if not exist "%PYW%" set "PYW=pythonw.exe"
start "" "%PYW%" "%USERPROFILE%\.kimi-code\proxy\nvidia_shim.py"
