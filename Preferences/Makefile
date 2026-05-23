BUNDLE_NAME = PhantomPrefs

ifeq ($(ROOTLESS),1)
TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
$(BUNDLE_NAME)_BUNDLE_IDENTIFIER = com.macthemes.phantom~rootless
else
TARGET := iphone:clang:latest:11.0
ARCHS = arm64 arm64e
$(BUNDLE_NAME)_BUNDLE_IDENTIFIER = com.macthemes.phantom
endif

DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

$(BUNDLE_NAME)_CFLAGS = -fobjc-arc
$(BUNDLE_NAME)_FILES = $(wildcard *.m)
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_INSTALL_PATH = /Library/PreferenceBundles
$(BUNDLE_NAME)_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
ifeq ($(ROOTLESS),1)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)var/jb/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp PhantomPrefs.plist $(THEOS_STAGING_DIR)var/jb/Library/PreferenceLoader/Preferences/PhantomPrefs.plist$(ECHO_END)
else
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp PhantomPrefs.plist $(THEOS_STAGING_DIR)Library/PreferenceLoader/Preferences/PhantomPrefs.plist$(ECHO_END)
endif
