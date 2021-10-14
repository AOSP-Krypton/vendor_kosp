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

# Board platforms
QCOM_MSMNILE := sm8150 msmnile
QCOM_MSM8998 := sdm660 msm8998
QCOM_TRINKET := sm6125 trinket

ifneq ($(filter $(TARGET_BOARD_PLATFORM),$(QCOM_MSMNILE)),)
QCOM_BOARD_PATH := sm8150
else ifneq ($(filter $(TARGET_BOARD_PLATFORM),$(QCOM_MSM8998)),)
QCOM_BOARD_PATH := msm8998
else ifneq ($(filter $(TARGET_BOARD_PLATFORM),$(QCOM_TRINKET)),)
QCOM_BOARD_PATH := sm6125
endif

LIBION_HEADER_PATHS := system/memory/libion/include \
                      system/memory/libion/kernel-headers

# Soong namespaces and common flags
PRODUCT_SOONG_NAMESPACES += \
    hardware/qcom-caf/$(QCOM_BOARD_PATH) \
    vendor/qcom/opensource/display-commonsys-intf

MSM_VIDC_TARGET_LIST := $(QCOM_MSMNILE) $(QCOM_TRINKET)

# Build libOmx encoders
TARGET_USES_QCOM_MM_AUDIO := true

# Get relative path for caf stuff
get-caf-path = hardware/qcom-caf/$(QCOM_BOARD_PATH)/$(1)

# Include caf wlan in cfi path
PRODUCT_CFI_INCLUDE_PATHS += \
    hardware/qcom-caf/wlan/qcwcn/wpa_supplicant_8_lib

# fwk-detect
PRODUCT_PACKAGES += \
    libvndfwk_detect_jni.qti \
    libvndfwk_detect_jni.qti.vendor

# caf bt stack
ifeq ($(TARGET_USE_QTI_BT_STACK),true)
PRODUCT_SOONG_NAMESPACES += \
    vendor/qcom/opensource/commonsys/packages/apps/Bluetooth \
    vendor/qcom/opensource/commonsys/system/bt/conf

PRODUCT_PACKAGES += \
	libbluetooth_qti \
	libbluetooth_qti_jni \
	libbtconfigstore \
	vendor.qti.hardware.btconfigstore@1.0 \
	vendor.qti.hardware.btconfigstore@2.0 \
	com.qualcomm.qti.bluetooth_audio@1.0 \
	vendor.qti.hardware.bluetooth_audio@2.0
else
PRODUCT_SOONG_NAMESPACES += \
    packages/apps/Bluetooth
endif
