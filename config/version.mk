# Copyright 2021-2023 AOSP-Krypton Project
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

# Version and fingerprint
KOSP_VERSION_MAJOR := 3
KOSP_VERSION_MINOR := 0
KOSP_VERSION := $(KOSP_VERSION_MAJOR).$(KOSP_VERSION_MINOR)

# Set props
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
  ro.kosp.build.device=$(KOSP_BUILD) \
  ro.kosp.build.version=$(KOSP_VERSION)

ifeq ($(strip $(GAPPS_BUILD)),true)
KOSP_BUILD_FLAVOR := GApps
else
KOSP_BUILD_FLAVOR := Vanilla
endif

KOSP_OTA_PACKAGE_NAME := KOSP-v$(KOSP_VERSION)-$(KOSP_BUILD)-$(TARGET_BUILD_VARIANT)-$(KOSP_BUILD_FLAVOR)
