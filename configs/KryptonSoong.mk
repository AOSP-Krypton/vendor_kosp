# Krypton soong configs

# Add variables that we wish to make available to soong here.
EXPORT_TO_SOONG := \
    KERNEL_ARCH \
    KERNEL_MAKE_ENV_SOONG \
    KERNEL_CROSS_COMPILE \
    TARGET_KERNEL_SOURCE

# Setup SOONG_CONFIG_* vars to export the vars listed above.
# Documentation here:
# https://github.com/LineageOS/android_build_soong/commit/8328367c44085b948c003116c0ed74a047237a69

SOONG_CONFIG_NAMESPACES += kryptonVarsPlugin

SOONG_CONFIG_kryptonVarsPlugin :=

define addVar
  SOONG_CONFIG_kryptonVarsPlugin += $(1)
  SOONG_CONFIG_kryptonVarsPlugin_$(1) := $$(subst ",\",$$($1))
endef

$(foreach v,$(EXPORT_TO_SOONG),$(eval $(call addVar,$(v))))

SOONG_CONFIG_NAMESPACES += kryptonGlobalVars
SOONG_CONFIG_kryptonGlobalVars += \
    target_init_vendor_lib \
    target_surfaceflinger_fod_lib


SOONG_CONFIG_NAMESPACES += kryptonQcomVars
SOONG_CONFIG_kryptonQcomVars += \
    uses_pre_uplink_features_netmgrd

# Set default values
TARGET_INIT_VENDOR_LIB ?= vendor_init
TARGET_SURFACEFLINGER_FOD_LIB ?= surfaceflinger_fod_lib

# Soong bool variables
SOONG_CONFIG_kryptonQcomVars_uses_pre_uplink_features_netmgrd := $(TARGET_USES_PRE_UPLINK_FEATURES_NETMGRD)

# Soong value variables
SOONG_CONFIG_kryptonGlobalVars_target_init_vendor_lib := $(TARGET_INIT_VENDOR_LIB)
SOONG_CONFIG_kryptonGlobalVars_target_surfaceflinger_fod_lib := $(TARGET_SURFACEFLINGER_FOD_LIB)
