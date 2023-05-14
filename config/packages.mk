PRODUCT_PACKAGES += \
    ThemePicker \

# Include explicitly to work around GMS issues
PRODUCT_PACKAGES += \
    libprotobuf-cpp-full \
    librsjni

# Config
PRODUCT_PACKAGES += \
    SimpleDeviceConfig

# GamingMode
PRODUCT_PACKAGES += \
    GamingMode

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
    Camera
endif

# RRO Overlays
PRODUCT_PACKAGES += \
    NavigationBarModeGesturalOverlayFS

# Repainter integration
PRODUCT_PACKAGES += \
    RepainterServicePriv

PRODUCT_PACKAGES += \
    Updater
