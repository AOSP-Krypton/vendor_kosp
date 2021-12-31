# Inherit common stuff
$(call inherit-product, vendor/krypton/config/common.mk)

# World APN list
PRODUCT_PACKAGES += \
    apns-conf.xml

# SIM Toolkit
PRODUCT_PACKAGES += \
    Stk

# Wallet app for Power menu integration
# https://source.android.com/devices/tech/connect/quick-access-wallet
PRODUCT_PACKAGES += \
    QuickAccessWallet

# Enable support of one-handed mode
PRODUCT_PRODUCT_PROPERTIES += \
    ro.support_one_handed_mode=true

# gms
ifeq ($(PRODUCT_GMS_CLIENTID_BASE),)
PRODUCT_PROPERTY_OVERRIDES += \
    ro.com.google.clientidbase=android-google
else
PRODUCT_PROPERTY_OVERRIDES += \
    ro.com.google.clientidbase=$(PRODUCT_GMS_CLIENTID_BASE)
endif
