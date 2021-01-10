# Krypton utils
include vendor/krypton/configs/KryptonUtils.mk

# Bootanimation
PRODUCT_COPY_FILES += \
	vendor/krypton/prebuilts/bootanimation/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip

# Inherit gapps if GAPPS_BUILD env variable is set
ifeq ($(GAPPS_BUILD),true)
GAPPS_VARIANT := nano
$(call inherit-product, vendor/opengapps/build/opengapps-packages.mk)
GAPPS_PRODUCT_PACKAGES += \
  	Chrome \
	PrebuiltBugle \
	CalculatorGoogle \
	GoogleContacts \
	LatinImeGoogle \
	PrebuiltDeskClockGoogle \
	WebViewGoogle \
	CalendarGooglePrebuilt \
	GoogleDialer

GAPPS_EXCLUDED_PACKAGES := Velvet
GAPPS_FORCE_PACKAGE_OVERRIDES := true
GAPPS_FORCE_WEBVIEW_OVERRIDES := true
GAPPS_FORCE_MMS_OVERRIDES := true
GAPPS_FORCE_DIALER_OVERRIDES := true
GAPPS_PACKAGE_OVERRIDES := LatinImeGoogle
endif

# Sepolicy
include vendor/krypton/sepolicy/KryptonSepolicy.mk
