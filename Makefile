GO_EASY_ON_ME=1
include theos/makefiles/common.mk

BUNDLE_NAME = TwitterPlugin
TwitterPlugin_FILES = KeychainUtils.mm OAuth+Additions.mm TwitterAuth.mm NSData+Base64.mm OAuthCore.mm TwitterPlugin.mm
TwitterPlugin_FRAMEWORKS = UIKit CoreGraphics SystemConfiguration Security IOKit 
TwitterPlugin_PRIVATE_FRAMEWORKS = Preferences
TwitterPlugin_CFLAGS = -I"/XCode4.1/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS4.2.sdk/var/include" -I../lockinfo/SDK/LockInfo
TwitterPlugin_INSTALL_PATH = /Library/LockInfo/Plugins

include $(THEOS_MAKE_PATH)/bundle.mk
