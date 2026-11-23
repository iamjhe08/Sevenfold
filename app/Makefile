# Sevenfold app (Theos)
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

ROOT := ..
APPLICATION_NAME = Sevenfold

ENGINE_DIRS := $(ROOT)/Shared/Engine $(ROOT)/Shared/Apps $(ROOT)/Shared/Account
APP_DIRS := $(ROOT)/iOS

SRC := $(shell find $(ENGINE_DIRS) $(APP_DIRS) -type f \( -name '*.m' -o -name '*.mm' -o -name '*.c' -o -name '*.cpp' \) ! -name 'ldid.old.cpp' | sort)
INC_DIRS := $(shell find $(ENGINE_DIRS) $(APP_DIRS) $(ROOT)/Shared/include $(ROOT)/Shared/Daemon -type d ! -path '*/Headers/*' | sort)

Sevenfold_FILES = $(SRC)
Sevenfold_USE_MODULES = 0
Sevenfold_CFLAGS = -fobjc-arc -Wno-error $(if $(SF_WARN),-Wall -Wno-unused-variable -Wno-unused-function -Wno-deprecated-declarations,-w) \
	-DCORECRYPTO_DONOT_USE_TRANSPARENT_UNION=1 \
	$(addprefix -I,$(INC_DIRS)) -I$(ROOT)/iOS/Headers -I$(ROOT)/vendor/openssl/include
SF_BUILD ?= $(shell date +%Y%m%d.%H%M)
Sevenfold_CFLAGS += -DSF_BUILD=\"$(SF_BUILD)\"
Sevenfold_CCFLAGS = -std=gnu++14
Sevenfold_FRAMEWORKS = UIKit Foundation CoreFoundation Security MobileCoreServices UserNotifications WebKit SystemConfiguration UniformTypeIdentifiers CoreGraphics QuartzCore PhotosUI
Sevenfold_PRIVATE_FRAMEWORKS = AuthKit Preferences
Sevenfold_LIBRARIES = MobileGestalt z
Sevenfold_LDFLAGS = $(ROOT)/vendor/openssl/lib/libcrypto.a
Sevenfold_CODESIGN_FLAGS = -S$(ROOT)/Shared/entitlements.xml

include $(THEOS_MAKE_PATH)/application.mk
