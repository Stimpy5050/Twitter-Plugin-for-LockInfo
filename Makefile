CC=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/arm-apple-darwin10-gcc-4.0.1
CPP=/Developer/Platforms/iPhoneOS.platform/Developer/usr/bin/arm-apple-darwin10-g++-4.0.1
LD=$(CC)

SDKVER=4.2
SDK=/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$(SDKVER).sdk

LDFLAGS= -framework Foundation \
	-framework UIKit \
	-framework IOKit \
	-framework Security \
	-framework CoreFoundation \
	-framework CoreGraphics \
	-framework Preferences \
	-framework GraphicsServices \
	-L../iphone/Common \
	-L$(SDK)/var/lib \
	-L$(SDK)/usr/lib \
	-F$(SDK)/System/Library/Frameworks \
	-F$(SDK)/System/Library/PrivateFrameworks \
	-lsubstrate \
	-lsqlite3 \
	-lobjc \
	-isysroot $(SDK)

CFLAGS= -I/var/include \
  -I$(SDK)/var/include \
  -I/var/include/gcc/darwin/4.0 \
  -I../iphone/LockInfo/SDK/LockInfo \
  -I"$(SDK)/usr/include" \
  -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/include" \
  -I"/Developer/Platforms/iPhoneOS.platform/Developer/usr/lib/gcc/arm-apple-darwin10/4.0.1/include" \
  -DDEBUG -Diphoneos_version_min=2.0 -objc-exceptions

Name=TwitterPlugin
Bundle=com.ashman.lockinfo.$(Name).bundle

all:	package

$(Name):	NSData+Base64.o KeychainUtils.o OAuth+Additions.o OAuthCore.o TwitterAuth.o $(Name).o
		$(LD) $(LDFLAGS) -bundle -o $@ $^
		ldid -S $@
		chmod 755 $@

%.o:	%.mm
		$(CPP) -c $(CFLAGS) $< -o $@

clean:
		rm -f *.o $(Name)
		rm -rf package

package: 	$(Name)
	mkdir -p package/DEBIAN
	mkdir -p package/Library/LockInfo/Plugins/$(Bundle)
	cp -r Bundle/* package/Library/LockInfo/Plugins/$(Bundle)
	cp $(Name) package/Library/LockInfo/Plugins/$(Bundle)
	cp control package/DEBIAN
	find package -name .svn -print0 | xargs -0 rm -rf
	dpkg-deb -b package $(Name)_$(shell grep ^Version: control | cut -d ' ' -f 2).deb
