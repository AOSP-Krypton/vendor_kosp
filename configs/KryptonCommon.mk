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
	vendor/krypton/prebuilts/bootanimation/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip \
	vendor/krypton/prebuilts/etc/apns-conf.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/apns-conf.xml

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

# Overlays
PRODUCT_ENFORCE_RRO_EXCLUDED_OVERLAYS += \
	vendor/krypton/overlays

DEVICE_PACKAGE_OVERLAYS += \
	vendor/krypton/overlays/overlay-krypton

# Sepolicy
include vendor/krypton/sepolicy/KryptonSepolicy.mk

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
