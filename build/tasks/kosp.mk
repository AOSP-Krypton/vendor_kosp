# Copyright (C) 2007 The Android Open Source Project
#				2021 AOSP-Krypton Project
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

KOSP_OTA := $(PRODUCT_OUT)/$(KOSP_OTA_PACKAGE_NAME)

$(KOSP_OTA): $(BUILT_TARGET_FILES_PACKAGE) $(OTA_FROM_TARGET_FILES)
	$(call build-ota-package-target,$@,-k $(DEFAULT_KEY_CERT_PAIR) --output_metadata_path $(INTERNAL_OTA_METADATA))
	@echo "KOSP OTA Package: $@"

.PHONY: kosp
kosp: $(KOSP_OTA)
