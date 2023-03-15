include vendor/kosp/config/BoardConfigKernel.mk

ifeq ($(BOARD_USES_QCOM_HARDWARE),true)
include vendor/kosp/config/BoardConfigQcom.mk
endif

include vendor/kosp/config/BoardConfigSoong.mk
