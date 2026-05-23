THEOS_DEVICE_IP = 0
DEBUG = 0
FINALPACKAGE = 1

ifeq ($(ROOTLESS),1)
TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
$(TWEAK_NAME)_BUNDLE_IDENTIFIER = com.macthemes.phantom~rootless
else
TARGET := iphone:clang:latest:11.0
ARCHS = arm64 arm64e
$(TWEAK_NAME)_BUNDLE_IDENTIFIER = com.macthemes.phantom
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Phantom
Phantom_FILES = Tweak.xm WAGOTHook.mm
Phantom_CFLAGS = -fobjc-arc -std=c++11 -Wno-deprecated-declarations
Phantom_LDFLAGS = -Wl,-no_fixup_chains -Wl,-no_data_const

include $(THEOS)/makefiles/tweak.mk

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

internal-stage::
ifeq ($(ROOTLESS),1)
	@mkdir -p $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceLoader/Preferences
	@cp Preferences/PhantomPrefs.plist $(THEOS_STAGING_DIR)/var/jb/Library/PreferenceLoader/Preferences/PhantomPrefs.plist
else
	@mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences
	@cp Preferences/PhantomPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/PhantomPrefs.plist
endif
