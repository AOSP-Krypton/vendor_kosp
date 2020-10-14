# Krypton soong configs

SOONG_CONFIG_NAMESPACES += kryptonGlobalVars
SOONG_CONFIG_kryptonGlobalVars += \
    target_init_vendor_lib \
    target_surfaceflinger_fod_lib

# Set default values
TARGET_INIT_VENDOR_LIB ?= vendor_init
TARGET_SURFACEFLINGER_FOD_LIB ?= surfaceflinger_fod_lib

# Soong value variables
SOONG_CONFIG_kryptonGlobalVars_target_init_vendor_lib := $(TARGET_INIT_VENDOR_LIB)
SOONG_CONFIG_kryptonGlobalVars_target_surfaceflinger_fod_lib := $(TARGET_SURFACEFLINGER_FOD_LIB)
