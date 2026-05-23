#import <Foundation/Foundation.h>

#import <rootless.h>

#include <dlfcn.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

#define DEFAULT_VERSION @"25.1.83.0";

/*
	Preferences …
*/
NSDictionary *preferences;

/*
	Variables …
*/
BOOL enabled;
BOOL debugLogging;
BOOL fixNotifications;

int newVersionMajor;
int newVersionMinor;
int newVersionBuild;
int newVersionRevision;

NSString *newVersion;

static NSDate * (*_orig_WAAppExpirationDate)();
static NSDate * (*_orig_WABuildDate)();
static NSDate * (*_orig_WADeprecatedPlatformCutOffDate)();

static NSString * (*_orig_WABuildVersion)(void *, void *);

/*
	Function Overrides …
*/
static NSDate *_new_WAAppExpirationDate()
{
	if (debugLogging)
	{
		NSLog(@"_new_WAAppExpirationDate called");

		NSDate *originalDate = _orig_WAAppExpirationDate();

		NSLog(@"Original expiration date: %@", originalDate);
	}

	// Modify the Date or do whatever you want here …

	return [NSDate dateWithTimeIntervalSinceNow: 31536000];
}

static NSDate *_new_WABuildDate()
{
	if (debugLogging)
	{
		NSLog(@"_new_WABuildDate called");

		NSDate *originalDate = _orig_WABuildDate();

		NSLog(@"Original build date: %@", originalDate);
	}

	// Modify the Date or do whatever you want here …

	return [NSDate date];
}


static NSString *_new_WABuildVersion(void *arg1, void *arg2)
{
	if (debugLogging)
	{
		NSLog(@"_new_WABuildVersion called");

		NSString *originalVersion = _orig_WABuildVersion(arg1, arg2);

		NSLog(@"Original build version: %@", originalVersion);
	}

	// Modify the Version or do whatever you want here …

	return newVersion;
}

static NSDate *_new_WADeprecatedPlatformCutOffDate()
{
	if (debugLogging)
	{
		NSLog(@"_new_WADeprecatedPlatformCutOffDate called");

		NSDate *originalDate = _orig_WADeprecatedPlatformCutOffDate();

		NSLog(@"Original expiration date: %@", originalDate);
	}

	// Modify the Date or do whatever you want here …

	return [NSDate dateWithTimeIntervalSinceNow: 31536000];
}

/*
	Hooks …
*/
%group Phantom

	%hook WALogWriter

		- (NSString*)formatLogText: (NSString*)ar1 withLevel: (int)ar2
		{
			NSString *result = %orig;

			if (debugLogging)
			{
				NSLog(@"WALog: %@", result);
			}

			return result;
		}

	%end

	%hook WAMessage

		- (bool)needsLocalNotification
		{
			return fixNotifications ? true : %orig;
		}

	%end

	%hook WAPBClientPayload_UserAgent_AppVersion

		- (void)setPrimary: (int)i
		{
			%orig(newVersionMajor);
		}

		- (void)setSecondary: (int)i
		{
			%orig(newVersionMinor);
		}

		- (void)setTertiary: (int)i
		{
			%orig(newVersionBuild);
		}

		- (void)setQuaternary: (int)i
		{
			%orig(newVersionRevision);
		}

	%end

	/*
		WACreateUserAgent
		WASubmitMessageSendEvent
		WAChatServers
		WAStreamVersion
		WACreateClientPayload
	*/

	%hook WARootViewController

		- (bool)isBuildExpired
		{
			return NO;
		}

		- (void)expireBuild
		{
			return;
		}

		- (void)presentHelperScreen
		{
			return;
		}

		- (void)wa_applicationDidEnterBackground
		{
			%orig;
		}

	%end

	%hook WamEventDaily

		- (double)iphone_jailbroken
		{
			return 0;
		}

	%end

%end

/*
	Constructor …
*/
%ctor
{
	// Load Preferences …

	preferences = [NSDictionary dictionaryWithContentsOfFile: ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.macthemes.phantomprefs.plist")];

	// … and parse only the "enabled" Preference.

	enabled = preferences[@"enabled"] ? [preferences[@"enabled"] boolValue] : YES;

	// Let's check, if the Tweak is enabled and initialize them …

	if (enabled)
	{
		// Now let's get the Preferences for Debug Logging and the new Version …

		debugLogging = preferences[@"debugLogging"] ? [preferences[@"debugLogging"] boolValue] : NO;
		fixNotifications = preferences[@"fixNotifications"] ? [preferences[@"fixNotifications"] boolValue] : NO;

		// Use user-set version, or fall back to actual installed WhatsApp version
		NSString *actualVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
		NSString *fallbackVersion = (actualVersion && actualVersion.length > 0) ? actualVersion : DEFAULT_VERSION;

		newVersion = preferences[@"newVersion"] ? [preferences[@"newVersion"] stringValue] : fallbackVersion;

		// Check, if the Version is valid …

		NSPredicate *isValidVersion = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", @"^\\d+(\\.\\d+){2,3}$"];

		// … and if not, use the actual installed version.

		if (![isValidVersion evaluateWithObject: newVersion])
		{
			newVersion = fallbackVersion;
		}

		// Separate the Version by it's Point and get the Components …

		NSArray *components = [newVersion componentsSeparatedByString: @"."];

		// … and set the Variables.

		newVersionMajor = [components[0] intValue];
		newVersionMinor = [components[1] intValue];
		newVersionBuild = [components[2] intValue];
		newVersionRevision = ([components count] > 3) ? [components[3] intValue] : 0;

		// Get SharedModules-Framework …

		NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
		NSString *frameworkPath = [bundlePath stringByAppendingPathComponent: @"Frameworks/SharedModules.framework/SharedModules"];

		void *image = dlopen([frameworkPath UTF8String], RTLD_LAZY);

		// Initialize the Tweak …

		%init(Phantom);

		// If we have a valid Image …

		if (image)
		{
			// Get Build Date and change it to our new Date …

			void * _WAAppExpirationDate = dlsym(image, "WAAppExpirationDate");

			if (_WAAppExpirationDate)
			{
				// Check, if Debug Logging is requested …

				if (debugLogging)
				{
					// Cast the Void Pointer to a Function Pointer and call it …

					NSDate * (*func)() = (NSDate *(*)())_WAAppExpirationDate;
					NSDate *result = func();

					NSLog(@"Function result: %@", result);
				}

				// Replace the original Function by our new One with different Expiration Date …

				MSHookFunction(_WAAppExpirationDate, (void *)&_new_WAAppExpirationDate, (void **)&_orig_WAAppExpirationDate);
			}
			else if (debugLogging)
			{
				NSLog(@"Failed to find WAAppExpirationDate");
			}

			// Get Build Date and change it to our new Date …

			void * _WABuildDate = dlsym(image, "WABuildDate");

			if (_WABuildDate)
			{
				// Check, if Debug Logging is requested …

				if (debugLogging)
				{
					// Cast the Void Pointer to a Function Pointer and call it …

					NSDate * (*func)() = (NSDate *(*)())_WABuildDate;
					NSDate *result = func();

					NSLog(@"Function result: %@", result);
				}

				// Replace the original Function by our new One with different Build Date …

				MSHookFunction(_WABuildDate, (void *)&_new_WABuildDate, (void **)&_orig_WABuildDate);
			}
			else if (debugLogging)
			{
				NSLog(@"Failed to find WABuildDate");
			}

			// Get the Build Version and change it to our new Version …

			void * _WABuildVersion = dlsym(image, "WABuildVersion");

			if (_WABuildVersion)
			{
				// Check, if Debug Logging is requested …

				if (debugLogging)
				{
					// Cast the Void Pointer to a Function Pointer and call it …

					NSString * (*func)(void *, void *) = (NSString *(*)(void *, void *))_WABuildVersion;

					// Pass NULL for the Arguments if you don't know what to pass …

					NSString *result = func((void*)@"", (void*)@"");

					NSLog(@"Function result: %@", result);
				}

				// Replace the original Function by our new One with different Build Version …

				MSHookFunction(_WABuildVersion, (void *)&_new_WABuildVersion, (void **)&_orig_WABuildVersion);
			}
			else if (debugLogging)
			{
				NSLog(@"Failed to find WABuildVersion");
			}

			// WABuildHash: intentionally not hooked — spoofing the hash breaks server auth

			// Get Deprecated Platform Cut-Off Date and change it to our new Date …

			void *_WADeprecatedPlatformCutOffDate = dlsym(image, "_WADeprecatedPlatformCutOffDate");

			if (_WADeprecatedPlatformCutOffDate)
			{
				// Check, if Debug Logging is requested …

				if (debugLogging)
				{
					// Cast the Void Pointer to a Function Pointer and call it …

					NSDate * (*func)() = (NSDate *(*)())_WADeprecatedPlatformCutOffDate;
					NSDate *result = func();

					NSLog(@"Function result: %@", result);
				}

				MSHookFunction(_WADeprecatedPlatformCutOffDate, (void *)&_new_WADeprecatedPlatformCutOffDate, (void **)&_orig_WADeprecatedPlatformCutOffDate);
			}
			else if (debugLogging)
			{
				NSLog(@"Failed to find _WADeprecatedPlatformCutOffDate");
			}
		}
		else if (debugLogging)
		{
			NSLog(@"Failed to load image at path: %@", frameworkPath);
		}

		return;
	}
}
