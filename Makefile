TARGET = iphone:clang:15.6
ARCHS := arm64 arm64e
FINALPACKAGE := 1
DEBUG = 1

# Set to 1 to log the first JPD_TRACE_BLOCKED_CALL_LIMIT unique methods that
# reach a neutralized implementation at runtime. This records class/selector
# names only; method arguments and return data are never logged.
JPD_TRACE_BLOCKED_CALLS ?= 0
JPD_TRACE_BLOCKED_CALL_LIMIT ?= 100

THEOS_PACKAGE_SCHEME = roothide

# INSTALL_TARGET_PROCESSES := SolarlandClient

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := JPushDisable

JPushDisable_FILES := Tweak.xm JPDMethodNeutralizer.mm
JPushDisable_CFLAGS := -fobjc-arc -Wall -Wextra \
	-DJPD_TRACE_BLOCKED_CALLS=$(JPD_TRACE_BLOCKED_CALLS) \
	-DJPD_TRACE_BLOCKED_CALL_LIMIT=$(JPD_TRACE_BLOCKED_CALL_LIMIT)

include $(THEOS_MAKE_PATH)/tweak.mk
