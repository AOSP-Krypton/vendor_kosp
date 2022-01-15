PRODUCT_PACKAGES += \
    ThemePicker \

ifneq ($(GAPPS_BUILD),true)
PRODUCT_PACKAGES += \
    SimpleDeviceConfig
endif

# Include explicitly to work around GMS issues
PRODUCT_PACKAGES += \
    libprotobuf-cpp-full \
    librsjni

# OTA Updater
PRODUCT_PACKAGES += \
    KOSP-Updater

# GamingMode
PRODUCT_PACKAGES += \
    GamingMode

TARGET_BUILD_LAWNCHAIR ?= true
ifeq ($(strip $(TARGET_BUILD_LAWNCHAIR)),true)
include vendor/lawnchair/lawnchair.mk
# Lawnicons
$(call inherit-product-if-exists, vendor/lawnicons/overlay.mk)
endif

TARGET_BUILD_VIA_BROWSER ?= true
ifeq ($(strip $(TARGET_BUILD_VIA_BROWSER)),true)
PRODUCT_PACKAGES += \
    Via
endif

TARGET_BUILD_MATLOG ?= true
ifeq ($(strip $(TARGET_BUILD_MATLOG)),true)
PRODUCT_PACKAGES += \
    MatlogX
endif

TARGET_BUILD_GRAPHENEOS_CAMERA ?= true
ifeq ($(strip $(TARGET_BUILD_GRAPHENEOS_CAMERA)),true)
PRODUCT_PACKAGES += \
    GrapheneOS-Camera
endif

# RRO Overlays
PRODUCT_PACKAGES += \
    NavigationBarModeGesturalOverlayFS