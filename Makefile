include theos/makefiles/common.mk
BUNDLE_NAME = TwitterPlugin

TwitterPlugin_FRAMEWORKS = Foundation IOKit CoreFoundation CoreGraphics GraphicsServices UIKit Security Preferences
TwitterPlugin_FILES = KeychainUtils.mm NSData+Base64.mm OAuth+Additions.mm OAuthCore.mm TwitterAuth.mm TwitterPlugin.mm

include $(THEOS_MAKE_PATH)/bundle.mk

Name=TwitterPlugin
Bundle=com.ashman.lockinfo.$(Name).bundle

package:: TwitterPlugin
	mkdir -p package/DEBIAN
	mkdir -p package/Library/LockInfo/Plugins/$(Bundle)
	cp -r Bundle/* package/Library/LockInfo/Plugins/$(Bundle)
	cp obj/$(Name) package/Library/LockInfo/Plugins/$(Bundle)
	rm *.deb
	rm -rf _
	rm -rf obj
#	cp control package/DEBIAN
#	find package -name .svn -print0 | xargs -0 rm -rf
#	dpkg-deb -b package $(Name)_$(shell grep ^Version: control | cut -d ' ' -f 2).deb

