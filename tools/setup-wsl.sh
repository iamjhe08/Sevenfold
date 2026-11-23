#!/usr/bin/env bash
# One-time setup of the Sevenfold build tools on Ubuntu (WSL on Windows, or Linux).
#
#   ./tools/setup-wsl.sh            installs into ~/sevenfold-tools
#   SEVENFOLD_TOOLS=/path ./tools/setup-wsl.sh
#
# Installs: Theos, the iOS 16.5 SDK, ldid, and clang/lld 18 wrappers.
set -euo pipefail

TOOLS="${SEVENFOLD_TOOLS:-$HOME/sevenfold-tools}"
SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

echo "==> Installing packages (asks for your Ubuntu password)"
$SUDO apt-get update -y
$SUDO apt-get install -y git make perl rsync fakeroot xz-utils dpkg-dev build-essential pkg-config \
	clang-18 lld-18 llvm-18 libplist-dev libplist++-dev libssl-dev

mkdir -p "$TOOLS"
cd "$TOOLS"

if [ ! -d theos ]; then
	echo "==> Downloading Theos"
	git clone --recursive https://github.com/theos/theos.git theos
fi

if [ ! -d sdks/iPhoneOS16.5.sdk ]; then
	echo "==> Downloading the iOS 16.5 SDK"
	rm -rf sdks
	git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git sdks
	git -C sdks sparse-checkout set iPhoneOS16.5.sdk
fi
mkdir -p theos/sdks
ln -sfn "$TOOLS/sdks/iPhoneOS16.5.sdk" theos/sdks/iPhoneOS16.5.sdk

if [ ! -x ldid/ldid ]; then
	echo "==> Building ldid"
	rm -rf ldid
	git clone https://github.com/ProcursusTeam/ldid.git ldid
	make -C ldid
fi

echo "==> Setting up the iOS toolchain wrappers"
BIN="theos/toolchain/linux/iphone/bin"
mkdir -p "$BIN"
cat > "$BIN/clang" <<'WRAP'
#!/bin/sh
exec /usr/bin/clang-18 -mlinker-version=711 -fuse-ld="$(dirname "$0")/ld" -Wno-unused-command-line-argument "$@"
WRAP
cat > "$BIN/clang++" <<'WRAP'
#!/bin/sh
exec /usr/bin/clang++-18 -mlinker-version=711 -fuse-ld="$(dirname "$0")/ld" -Wno-unused-command-line-argument "$@"
WRAP
# ld64.lld picks its mode from its name, so call it through a wrapper.
cat > "$BIN/ld" <<'WRAP'
#!/bin/sh
exec /usr/bin/ld64.lld-18 "$@"
WRAP
chmod +x "$BIN/clang" "$BIN/clang++" "$BIN/ld"
ln -sfn /usr/bin/ld64.lld-18 "$BIN/ld64.lld"
ln -sfn /usr/bin/llvm-ar-18 "$BIN/ar"
ln -sfn /usr/bin/llvm-libtool-darwin-18 "$BIN/libtool"
ln -sfn /usr/bin/llvm-lipo-18 "$BIN/lipo"
ln -sfn /usr/bin/llvm-nm-18 "$BIN/nm"
ln -sfn /usr/bin/llvm-otool-18 "$BIN/otool"
ln -sfn /usr/bin/llvm-strip-18 "$BIN/strip"
ln -sfn "$TOOLS/ldid/ldid" "$BIN/ldid"

LINE="export THEOS=\"$TOOLS/theos\""
grep -qxF "$LINE" "$HOME/.bashrc" 2>/dev/null || echo "$LINE" >> "$HOME/.bashrc"

echo
echo "Done. Build tools are in $TOOLS"
echo "Open a new terminal (or run: $LINE), then build with:"
echo "  ./packaging/build-packages.sh"
