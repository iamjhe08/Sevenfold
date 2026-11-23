#!/usr/bin/env bash
# Builds Sevenfold and makes two packages:
#   rootless (Dopamine etc.)  -> iphoneos-arm64,  files under /var/jb
#   RootHide                  -> iphoneos-arm64e, files at jbroot paths
#
# Usage:  THEOS=~/theos ./packaging/build-packages.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(grep -m1 -A1 CFBundleShortVersionString "$ROOT/app/Resources/Info.plist" | tail -1 | sed 's/.*<string>\(.*\)<\/string>.*/\1/')}"
OUT="$ROOT/packages"
: "${THEOS:?Set THEOS to your Theos folder, e.g. export THEOS=~/theos}"

echo "==> Building background service"
make -C "$ROOT/daemon" FINALPACKAGE=1 >/dev/null
BUILD="$(date +%Y%m%d.%H%M)"
echo "==> Building app (build $BUILD)"
touch "$ROOT/iOS/Sevenfold/SFSettingsViewController.m"
make -C "$ROOT/app" FINALPACKAGE=1 SF_BUILD="$BUILD" >/dev/null

APP="$ROOT/app/.theos/obj/Sevenfold.app"
[ -d "$APP" ] || APP="$ROOT/app/.theos/obj/debug/Sevenfold.app"
DAEMON="$ROOT/daemon/.theos/obj/sevenfoldd"
[ -f "$DAEMON" ] || DAEMON="$ROOT/daemon/.theos/obj/debug/sevenfoldd"
[ -d "$APP" ] && [ -f "$DAEMON" ] || { echo "Build output not found"; exit 1; }

mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fill() { # file prefix arch predepends
	sed -e "s#@PREFIX@#$2#g" -e "s#@ARCH@#$3#g" -e "s#@VERSION@#$VERSION#g" -e "s#@PREDEPENDS@#$4#g" "$1"
}

make_package() { # name prefix arch predepends roothide
	local name="$1" prefix="$2" arch="$3" predepends="$4" roothide="$5"
	local stage="$WORK/$name"
	local base="$stage$prefix"
	mkdir -p "$stage/DEBIAN" "$base/Applications" "$base/usr/libexec" "$base/Library/LaunchDaemons"
	cp -R "$APP" "$base/Applications/"
	cp "$DAEMON" "$base/usr/libexec/sevenfoldd"
	chmod 0755 "$base/usr/libexec/sevenfoldd" "$base/Applications/Sevenfold.app/Sevenfold"
	fill "$ROOT/packaging/com.t4mag0.sevenfoldd.plist" "$prefix" "$arch" "" > "$base/Library/LaunchDaemons/com.t4mag0.sevenfoldd.plist"
	fill "$ROOT/packaging/control" "$prefix" "$arch" "$predepends" > "$stage/DEBIAN/control"
	fill "$ROOT/packaging/postinst" "$prefix" "$arch" "" > "$stage/DEBIAN/postinst"
	fill "$ROOT/packaging/prerm" "$prefix" "$arch" "" > "$stage/DEBIAN/prerm"
	chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm"
	if [ "$roothide" = 1 ]; then
		# RootHide rewrites jailbreak paths at runtime through these markers.
		ln -s /usr/lib/DynamicPatches/AutoPatches.dylib "$base/Applications/Sevenfold.app/Sevenfold.roothidepatch"
		ln -s /usr/lib/DynamicPatches/AutoPatches.dylib "$base/usr/libexec/sevenfoldd.roothidepatch"
	fi
	find "$stage" -name '.DS_Store' -delete
	local deb="$OUT/com.t4mag0.sevenfold_${VERSION}_${arch}.deb"
	dpkg-deb -Zxz --root-owner-group -b "$stage" "$deb" >/dev/null
	echo "==> $deb"
}

make_package rootless /var/jb iphoneos-arm64 "" 0
make_package roothide "" iphoneos-arm64e "Pre-Depends: rootless-compat(>= 0.9)\n" 1
