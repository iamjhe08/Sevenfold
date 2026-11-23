TARGET := iphone:clang:16.5:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

TOOL_NAME = sevenfoldd
sevenfoldd_USE_MODULES = 0
sevenfoldd_FILES = ../Shared/Daemon/main.mm ../Shared/Daemon/SFDaemonListener.m
sevenfoldd_CFLAGS = -Wno-error -fobjc-arc -include ../Shared/Daemon/Prefix.pch -I../Shared/Daemon -Wno-deprecated-declarations
sevenfoldd_FRAMEWORKS = Foundation CoreFoundation IOKit
sevenfoldd_LDFLAGS = ../Shared/Daemon/lib/AssertionServices.tbd ../Shared/Daemon/lib/BackBoardServices.tbd ../Shared/Daemon/lib/SpringBoardServices.tbd
sevenfoldd_CODESIGN_FLAGS = -S../Shared/Daemon/entitlements.plist
sevenfoldd_INSTALL_PATH = /usr/libexec
include $(THEOS_MAKE_PATH)/tool.mk
