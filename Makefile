TARGET = iphone:clang:15.6
ARCHS := arm64 arm64e
FINALPACKAGE := 1
DEBUG = 1

THEOS_PACKAGE_SCHEME = roothide

# INSTALL_TARGET_PROCESSES := SolarlandClient

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := JPushDisable

JPushDisable_FILES := Tweak.xm
JPushDisable_CFLAGS := -fobjc-arc -Wall -Wextra

include $(THEOS_MAKE_PATH)/tweak.mk
