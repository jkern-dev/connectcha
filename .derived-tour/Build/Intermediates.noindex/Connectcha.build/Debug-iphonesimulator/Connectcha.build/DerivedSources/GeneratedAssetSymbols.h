#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.connectcha.app";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "AppBackground" asset catalog color resource.
static NSString * const ACColorNameAppBackground AC_SWIFT_PRIVATE = @"AppBackground";

/// The "CardBackground" asset catalog color resource.
static NSString * const ACColorNameCardBackground AC_SWIFT_PRIVATE = @"CardBackground";

/// The "LaunchBackground" asset catalog color resource.
static NSString * const ACColorNameLaunchBackground AC_SWIFT_PRIVATE = @"LaunchBackground";

/// The "SubtleBackground" asset catalog color resource.
static NSString * const ACColorNameSubtleBackground AC_SWIFT_PRIVATE = @"SubtleBackground";

#undef AC_SWIFT_PRIVATE
