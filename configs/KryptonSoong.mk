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

# Krypton soong configs

SOONG_CONFIG_NAMESPACES += kryptonGlobalVars
SOONG_CONFIG_kryptonGlobalVars += \
    target_init_vendor_lib \
    target_surfaceflinger_fod_lib \
    target_ld_shim_libs \
    has_legacy_camera_hal1

SOONG_CONFIG_NAMESPACES += kryptonQcomVars
SOONG_CONFIG_kryptonQcomVars += \
    uses_pre_uplink_features_netmgrd \
    supports_hw_fde \
    supports_hw_fde_perf \
    uses_qti_camera_device

# Set default values
TARGET_INIT_VENDOR_LIB ?= vendor_init
TARGET_SURFACEFLINGER_FOD_LIB ?= surfaceflinger_fod_lib

# Soong bool variables
SOONG_CONFIG_kryptonQcomVars_uses_pre_uplink_features_netmgrd := $(TARGET_USES_PRE_UPLINK_FEATURES_NETMGRD)

# Soong value variables
SOONG_CONFIG_kryptonGlobalVars_target_init_vendor_lib := $(TARGET_INIT_VENDOR_LIB)
SOONG_CONFIG_kryptonGlobalVars_target_surfaceflinger_fod_lib := $(TARGET_SURFACEFLINGER_FOD_LIB)
SOONG_CONFIG_kryptonGlobalVars_target_ld_shim_libs := $(subst $(space),:,$(TARGET_LD_SHIM_LIBS))
SOONG_CONFIG_kryptonGlobalVars_has_legacy_camera_hal1 := $(TARGET_HAS_LEGACY_CAMERA_HAL1)
SOONG_CONFIG_kryptonQcomVars_supports_hw_fde := $(TARGET_HW_DISK_ENCRYPTION)
SOONG_CONFIG_kryptonQcomVars_supports_hw_fde_perf := $(TARGET_HW_DISK_ENCRYPTION_PERF)
SOONG_CONFIG_kryptonQcomVars_uses_qti_camera_device := $(TARGET_USES_QTI_CAMERA_DEVICE)
