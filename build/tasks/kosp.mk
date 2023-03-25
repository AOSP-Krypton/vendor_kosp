# Copyright (C) 2007 The Android Open Source Project
# Copyright (C) 2021-2023 AOSP-Krypton Project
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

KOSP_OTA := $(PRODUCT_OUT)/$(KOSP_OTA_PACKAGE_NAME).zip

$(KOSP_OTA): $(BUILT_TARGET_FILES_PACKAGE) $(OTA_FROM_TARGET_FILES)
	$(call build-ota-package-target,$@,-k $(DEFAULT_KEY_CERT_PAIR) --output_metadata_path $(INTERNAL_OTA_METADATA))

.PHONY: kosp
kosp: $(KOSP_OTA)
	$(hide) mv $(KOSP_OTA) $(KOSP_OUT)/$(KOSP_OTA_PACKAGE_NAME)-$(shell date "+%Y%m%d-%H%M")-full.zip
	@echo "KOSP full OTA package is ready"

ifneq ($(strip $(PREVIOUS_TARGET_FILES_PACKAGE)),)
KOSP_INCREMENTAL_OTA := $(PRODUCT_OUT)/$(KOSP_OTA_PACKAGE_NAME)-incremental.zip

$(KOSP_INCREMENTAL_OTA): $(BUILT_TARGET_FILES_PACKAGE) $(OTA_FROM_TARGET_FILES)
	$(OTA_FROM_TARGET_FILES) \
	--block \
	-p $(SOONG_HOST_OUT) \
	-k $(DEFAULT_KEY_CERT_PAIR) \
	-i $(PREVIOUS_TARGET_FILES_PACKAGE) \
	$(BUILT_TARGET_FILES_PACKAGE) $@

.PHONY: kosp-incremental
kosp-incremental: $(KOSP_INCREMENTAL_OTA)
	$(hide) mv $(KOSP_INCREMENTAL_OTA) $(KOSP_OUT)/$(KOSP_OTA_PACKAGE_NAME)-$(shell date "+%Y%m%d-%H%M")-incremental.zip
	@echo "KOSP incremental OTA package is ready"
endif

KOSP_FASTBOOT_PACKAGE := $(PRODUCT_OUT)/$(KOSP_OTA_PACKAGE_NAME)-fastboot.zip

$(KOSP_FASTBOOT_PACKAGE): $(BUILT_TARGET_FILES_PACKAGE) $(IMG_FROM_TARGET_FILES)
	$(IMG_FROM_TARGET_FILES) \
	$(BUILT_TARGET_FILES_PACKAGE) $@

.PHONY: kosp-fastboot
kosp-fastboot: $(KOSP_FASTBOOT_PACKAGE)
	rm -rf $(KOSP_OUT)/kosp_tmp
	mkdir -p $(KOSP_OUT)/kosp_tmp
	unzip -o -q $(KOSP_FASTBOOT_PACKAGE) -d $(KOSP_OUT)/kosp_tmp
	rm -rf $(KOSP_FASTBOOT_PACKAGE)
	@echo "Recompressing fastboot package..."
	zip $(KOSP_OUT)/$(KOSP_OTA_PACKAGE_NAME)-$(shell date "+%Y%m%d-%H%M")-fastboot.zip -q -m -9 -r $(KOSP_OUT)/kosp_tmp/*
	rm -rf $(KOSP_OUT)/kosp_tmp
	@echo "KOSP fastboot package is ready"
