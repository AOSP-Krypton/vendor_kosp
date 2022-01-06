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
