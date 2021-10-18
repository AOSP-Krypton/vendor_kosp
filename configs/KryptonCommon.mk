# Copyright 2021 AOSP-Krypton Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Krypton build info
include vendor/krypton/configs/KryptonProps.mk

# Krypton utils
include vendor/krypton/configs/KryptonUtils.mk

# Bootanimation
PRODUCT_COPY_FILES += \
	vendor/krypton/prebuilts/bootanimation/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip

# Apns
PRODUCT_COPY_FILES += \
	vendor/krypton/prebuilts/etc/apns-conf.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml

# Font config template
PRODUCT_COPY_FILES += \
    vendor/krypton/prebuilts/etc/custom_font_config.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/custom_font_config.xml

# Inherit gapps if GAPPS_BUILD env variable is set
ifeq ($(GAPPS_BUILD),true)
$(call inherit-product, vendor/google/gms/config.mk)
$(call inherit-product, vendor/google/pixel/config.mk)
else

PRODUCT_PACKAGES += \
    UnifiedNlp

endif

# OTA Updater
PRODUCT_PACKAGES += \
    KOSP-Updater

# ThemePicker
PRODUCT_PACKAGES += \
    ThemePicker

# SimpleDeviceConfig
PRODUCT_PACKAGES += \
    SimpleDeviceConfig

# Overlays
PRODUCT_PACKAGE_OVERLAYS += \
	vendor/krypton/overlays/common

PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += \
	vendor/krypton/overlays/common

DEVICE_PACKAGE_OVERLAYS += \
	vendor/krypton/overlays/overlay-krypton

# gms
ifeq ($(PRODUCT_GMS_CLIENTID_BASE),)
PRODUCT_PROPERTY_OVERRIDES += \
    ro.com.google.clientidbase=android-google
else
PRODUCT_PROPERTY_OVERRIDES += \
    ro.com.google.clientidbase=$(PRODUCT_GMS_CLIENTID_BASE)
endif

# Copy all krypton-specific init rc files
$(foreach f,$(wildcard vendor/krypton/prebuilts/etc/init/*.rc),\
	$(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_SYSTEM)/etc/init/$(notdir $f)))

# Copy all app permissions xml
$(foreach f,$(wildcard vendor/krypton/prebuilts/etc/permissions/*.xml),\
	$(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/$(notdir $f)))

$(foreach f,$(wildcard vendor/krypton/prebuilts/system_ext/etc/permissions/*.xml),\
	$(eval PRODUCT_COPY_FILES += $(f):$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/$(notdir $f)))

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

PRODUCT_DEXPREOPT_SPEED_APPS += \
    Settings \
    SystemUI \
    Launcher3QuickStep

# IORap app launch prefetching using Perfetto traces and madvise
PRODUCT_PRODUCT_PROPERTIES += \
    ro.iorapd.enable=true

# Disable touch video heatmap to reduce latency, motion jitter, and CPU usage
# on supported devices with Deep Press input classifier HALs and models
PRODUCT_PRODUCT_PROPERTIES += \
	ro.input.video_enabled=false

#Blurr
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    ro.sf.blurs_are_expensive=1 \
    ro.surface_flinger.supports_background_blur=1 \
    persist.sys.sf.disable_blurs=1

# Don't compile SystemUITests
EXCLUDE_SYSTEMUI_TESTS := true

# Common props
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
	keyguard.no_require_sim=true \
    dalvik.vm.debug.alloc=0 \
    ro.url.legal=http://www.google.com/intl/%s/mobile/android/basic/phone-legal.html \
    ro.url.legal.android_privacy=http://www.google.com/intl/%s/mobile/android/basic/privacy.html \
    ro.error.receiver.system.apps=com.google.android.gms \
    ro.setupwizard.enterprise_mode=1 \
	ro.com.android.dataroaming=false \
    ro.atrace.core.services=com.google.android.gms,com.google.android.gms.ui,com.google.android.gms.persistent \
    ro.com.android.dateformat=MM-dd-yyyy \
    ro.build.selinux=1 \
	media.recorder.show_manufacturer_and_model=true \
	ro.storage_manager.enabled=true \
	persist.sys.disable_rescue=true \
	net.tethering.noprovisioning=true \
	ro.opa.eligible_device=true \
	ro.boot.vendor.overlay.theme=com.android.internal.systemui.navbar.gestural \
	log.tag.Telephony=ERROR

# Charger
PRODUCT_PACKAGES += \
    charger_res_images

# Do not include art debug targets
PRODUCT_ART_TARGET_INCLUDE_DEBUG_BUILD := false

# Strip the local variable table and the local variable type table to reduce
# the size of the system image. This has no bearing on stack traces, but will
# leave less information available via JDWP.
PRODUCT_MINIMIZE_JAVA_DEBUG_INFO := true

# Disable vendor restrictions
PRODUCT_RESTRICT_VENDOR_FILES := false

# Wallet app for Power menu integration
# https://source.android.com/devices/tech/connect/quick-access-wallet
PRODUCT_PACKAGES += \
    QuickAccessWallet

# Include explicitly to work around GMS issues
PRODUCT_PACKAGES += \
    libprotobuf-cpp-full \
    librsjni
