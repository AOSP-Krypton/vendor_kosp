# Set a default release key paths
SIGNING_KEY_PATH ?= certs
RELEASE_KEY := $(SIGNING_KEY_PATH)/releasekey

ifeq ($(strip $(OFFICIAL_BUILD)),true)
KEYS := $(shell ls $(SIGNING_KEY_PATH) | grep releasekey)
ifeq ($(strip $(KEYS)),)
$(error Official builds must be signed with releasekey, please run keygen)
else
PRODUCT_DEFAULT_DEV_CERTIFICATE := $(RELEASE_KEY)
PRODUCT_OTA_PUBLIC_KEYS := $(RELEASE_KEY)
endif
endif

PRODUCT_BUILD_PROP_OVERRIDES += BUILD_UTC_DATE=0

PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    dalvik.vm.debug.alloc=0 \
    keyguard.no_require_sim=true \
    media.recorder.show_manufacturer_and_model=true \
    net.tethering.noprovisioning=true \
    persist.sys.disable_rescue=true \
    ro.carrier=unknown \
    ro.com.android.dataroaming=false \
    ro.opa.eligible_device=true \
    ro.setupwizard.enterprise_mode=1 \
    ro.storage_manager.enabled=true \
    ro.url.legal=http://www.google.com/intl/%s/mobile/android/basic/phone-legal.html \
    ro.url.legal.android_privacy=http://www.google.com/intl/%s/mobile/android/basic/privacy.html \
    ro.boot.vendor.overlay.theme=com.android.internal.systemui.navbar.gestural

#Set Network Hostname
PRODUCT_PROPERTY_OVERRIDES += \
    net.hostname=$(TARGET_VENDOR_DEVICE_NAME)

# Charger
PRODUCT_PACKAGES += \
    charger_res_images

# Copy our init rc files
$(foreach f,$(wildcard vendor/kosp/prebuilt/common/etc/init/*.rc),\
    $(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_SYSTEM)/etc/init/$(notdir $f)))

# Copy all app permissions xml
$(foreach f,$(wildcard vendor/kosp/prebuilt/common/etc/permissions/*.xml),\
	$(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/$(notdir $f)))

$(foreach f,$(wildcard vendor/kosp/prebuilt/common/system_ext/etc/permissions/*.xml),\
	$(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/$(notdir $f)))

# Sysconfig
$(foreach f,$(wildcard vendor/kosp/prebuilts/common/product/etc/sysconfig/*.xml),\
	$(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_PRODUCT)/etc/sysconfig/$(notdir $f)))

# Don't compile SystemUITests
EXCLUDE_SYSTEMUI_TESTS := true

# Don't include art debug targets
PRODUCT_ART_TARGET_INCLUDE_DEBUG_BUILD := false

# LatinIME gesture typing
ifeq ($(TARGET_SUPPORTS_64_BIT_APPS),arm64)
PRODUCT_COPY_FILES += \
    vendor/kosp/prebuilt/common/lib64/libjni_latinime.so:$(TARGET_COPY_OUT_SYSTEM)/lib64/libjni_latinime.so \
    vendor/kosp/prebuilt/common/lib64/libjni_latinimegoogle.so:$(TARGET_COPY_OUT_SYSTEM)/lib64/libjni_latinimegoogle.so
else
PRODUCT_COPY_FILES += \
    vendor/kosp/prebuilt/common/lib/libjni_latinime.so:$(TARGET_COPY_OUT_SYSTEM)/lib/libjni_latinime.so \
    vendor/kosp/prebuilt/common/lib/libjni_latinimegoogle.so:$(TARGET_COPY_OUT_SYSTEM)/lib/libjni_latinimegoogle.so
endif

# Strip the local variable table and the local variable type table to reduce
# the size of the system image. This has no bearing on stack traces, but will
# leave less information available via JDWP.
PRODUCT_MINIMIZE_JAVA_DEBUG_INFO := true

# Product overlay
PRODUCT_PACKAGE_OVERLAYS += vendor/kosp/overlay
PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += vendor/kosp/overlay

# Disable vendor restrictions
PRODUCT_RESTRICT_VENDOR_FILES := false

# Disable touch video heatmap to reduce latency, motion jitter, and CPU usage
# on supported devices with Deep Press input classifier HALs and models
PRODUCT_PRODUCT_PROPERTIES += \
    ro.input.video_enabled=false

# Bootanimation
include vendor/kosp/config/bootanimation.mk

# Packages
include vendor/kosp/config/packages.mk

# Versioning
include vendor/kosp/config/version.mk

# ART
# Optimize everything for preopt
PRODUCT_DEX_PREOPT_DEFAULT_COMPILER_FILTER := everything
# Don't preopt prebuilts
DONT_DEXPREOPT_PREBUILTS := true

ifeq ($(TARGET_SUPPORTS_64_BIT_APPS), true)
# Use 64-bit dex2oat for better dexopt time.
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.dex2oat64.enabled=true
endif

PRODUCT_PROPERTY_OVERRIDES += \
    pm.dexopt.boot=verify \
    pm.dexopt.first-boot=quicken \
    pm.dexopt.install=speed-profile \
    pm.dexopt.bg-dexopt=everything

ifneq ($(AB_OTA_PARTITIONS),)
PRODUCT_PROPERTY_OVERRIDES += \
    pm.dexopt.ab-ota=quicken
endif

# Flatten APEXs for performance
OVERRIDE_TARGET_FLATTEN_APEX := true
# This needs to be specified explicitly to override ro.apex.updatable=true from
# # prebuilt vendors, as init reads /product/build.prop after /vendor/build.prop
PRODUCT_PRODUCT_PROPERTIES += ro.apex.updatable=false

ifeq ($(GAPPS_BUILD),true)
    $(call inherit-product-if-exists, vendor/google/gms/config.mk)
    $(call inherit-product-if-exists, vendor/google/pixel/config.mk)
endif

#OTA tools
PRODUCT_HOST_PACKAGES += \
    signapk \
    brotli

# Themes
$(call inherit-product, vendor/themes/common.mk)

# Sepolicy
$(call inherit-product, vendor/kosp/config/sepolicy.mk)
