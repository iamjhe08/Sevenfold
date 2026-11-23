@echo off
rem Builds the Sevenfold packages inside WSL and copies them to this folder's "packages" directory.
rem Double-click this file, or run it from Command Prompt.
setlocal
set "HERE=%~dp0"
for /f "delims=" %%i in ('wsl wslpath -a "%HERE%."') do set "WSLHERE=%%i"
echo Building Sevenfold in WSL...
wsl bash -lc "set -e; rm -rf ~/sevenfold-build && mkdir -p ~/sevenfold-build && cp -r '%WSLHERE%/.' ~/sevenfold-build/ && cd ~/sevenfold-build && find . -name '*.sh' -exec sed -i 's/\r$//' {} + && sed -i 's/\r$//' packaging/postinst packaging/prerm packaging/control && ([ -d ~/sevenfold-tools/theos/sdks/iPhoneOS16.5.sdk ] || ./tools/setup-wsl.sh) && export THEOS=~/sevenfold-tools/theos && ./packaging/build-packages.sh && mkdir -p '%WSLHERE%/packages' && cp packages/*.deb '%WSLHERE%/packages/'"
if errorlevel 1 (
  echo.
  echo Build failed. See the messages above.
) else (
  echo.
  echo Done. Your packages are in "%HERE%packages".
)
pause
