ORIG_PATH := $(shell cat $(OUT_DIR)/.path_interposer_origpath)
# Add variables that we wish to make available to soong here.
EXPORT_TO_SOONG := \
    ORIG_PATH \
    KERNEL_ARCH \
    KERNEL_BUILD_OUT_PREFIX \
    KERNEL_CROSS_COMPILE \
    KERNEL_MAKE_CMD \
    KERNEL_MAKE_FLAGS \
    PATH_OVERRIDE_SOONG \
    TARGET_KERNEL_CONFIG \
    TARGET_KERNEL_SOURCE \
    KERNEL_CLANG_TRIPLE \
    KERNEL_CC \
    MAKE_PREBUILT

# Setup SOONG_CONFIG_* vars to export the vars listed above.
# Documentation here:
# https://github.com/LineageOS/android_build_soong/commit/8328367c44085b948c003116c0ed74a047237a69

SOONG_CONFIG_NAMESPACES += kospVarsPlugin
SOONG_CONFIG_kospVarsPlugin :=

SOONG_CONFIG_NAMESPACES += kospGlobalVars
SOONG_CONFIG_kospGlobalVars += \
    camera_skip_kind_check \
    target_surfaceflinger_udfps_lib \
    target_init_vendor_lib \
    camera_needs_client_info_defaults  \
    target_ld_shim_libs \
    gralloc_handle_has_reserved_size \
    camera_needs_client_info_lib

SOONG_CONFIG_NAMESPACES += kospQcomVars
SOONG_CONFIG_kospQcomVars += \
    no_camera_smooth_apis \
    uses_qti_camera_device \
    should_wait_for_qsee \
    supports_extended_compress_format \
    uses_pre_uplink_features_netmgrd

# Only create display_headers_namespace var if dealing with UM platforms to avoid breaking build for all other platforms
ifneq ($(filter $(UM_PLATFORMS),$(TARGET_BOARD_PLATFORM)),)
SOONG_CONFIG_kospQcomVars += \
    qcom_display_headers_namespace
endif

define addVar
    SOONG_CONFIG_kospVarsPlugin += $(1)
    SOONG_CONFIG_kospVarsPlugin_$(1) := $$(subst ",\",$$($1))
endef

# Set default values
TARGET_SURFACEFLINGER_UDFPS_LIB ?= surfaceflinger_udfps_lib
TARGET_INIT_VENDOR_LIB ?= vendor_init
TARGET_CAMERA_NEEDS_CLIENT_INFO ?= false
TARGET_GRALLOC_HANDLE_HAS_RESERVED_SIZE ?= false

# Soong bool variables
SOONG_CONFIG_kospGlobalVars_gralloc_handle_has_reserved_size := $(TARGET_GRALLOC_HANDLE_HAS_RESERVED_SIZE)
SOONG_CONFIG_kospQcomVars_uses_pre_uplink_features_netmgrd := $(TARGET_USES_PRE_UPLINK_FEATURES_NETMGRD)

# Soong value variables
SOONG_CONFIG_kospGlobalVars_camera_skip_kind_check := $(CAMERA_SKIP_KIND_CHECK)
SOONG_CONFIG_kospGlobalVars_target_surfaceflinger_udfps_lib := $(TARGET_SURFACEFLINGER_UDFPS_LIB)
SOONG_CONFIG_kospGlobalVars_target_ld_shim_libs := $(subst $(space),:,$(TARGET_LD_SHIM_LIBS))
SOONG_CONFIG_kospGlobalVars_camera_needs_client_info_lib := $(TARGET_CAMERA_NEEDS_CLIENT_INFO_LIB)
SOONG_CONFIG_kospQcomVars_no_camera_smooth_apis := $(TARGET_HAS_NO_CAMERA_SMOOTH_APIS)
SOONG_CONFIG_kospQcomVars_uses_qti_camera_device := $(TARGET_USES_QTI_CAMERA_DEVICE)
SOONG_CONFIG_kospGlobalVars_target_init_vendor_lib := $(TARGET_INIT_VENDOR_LIB)
SOONG_CONFIG_kospGlobalVars_camera_needs_client_info_defaults := $(TARGET_CAMERA_NEEDS_CLIENT_INFO)
SOONG_CONFIG_kospQcomVars_should_wait_for_qsee := $(TARGET_KEYMASTER_WAIT_FOR_QSEE)
SOONG_CONFIG_kospQcomVars_supports_extended_compress_format := $(AUDIO_FEATURE_ENABLED_EXTENDED_COMPRESS_FORMAT)

ifneq ($(filter $(QSSI_SUPPORTED_PLATFORMS),$(TARGET_BOARD_PLATFORM)),)
SOONG_CONFIG_kospQcomVars_qcom_display_headers_namespace := vendor/qcom/opensource/commonsys-intf/display
else
SOONG_CONFIG_kospQcomVars_qcom_display_headers_namespace := $(QCOM_SOONG_NAMESPACE)/display
endif

ifneq ($(TARGET_USE_QTI_BT_STACK),true)
PRODUCT_SOONG_NAMESPACES += packages/apps/Bluetooth
endif #TARGET_USE_QTI_BT_STACK

$(foreach v,$(EXPORT_TO_SOONG),$(eval $(call addVar,$(v))))
