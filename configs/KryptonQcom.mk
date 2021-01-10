# Board platforms
QCOM_MSMNILE := sm8150 msmnile

ifneq ($(filter $(TARGET_BOARD_PLATFORM),$(QCOM_MSMNILE)),)
QCOM_BOARD_PATH := sm8150
endif

# Get relative path for caf stuff 
get-caf-path = hardware/qcom-caf/$(QCOM_BOARD_PATH)/$(1)
