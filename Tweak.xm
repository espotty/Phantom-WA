#import <Foundation/Foundation.h>

#import <rootless.h>

#include <dlfcn.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

#define DEFAULT_VERSION @"25.1.83.0"

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
BOOL versionSpoofActive;

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

	// Only overrides version proto fields when user has explicitly set a custom version.
	// Without this guard, WhatsApp sends inconsistent version data that breaks server auth.
	%hook WAPBClientPayload_UserAgent_AppVersion

		- (void)setPrimary: (int)i
		{
			versionSpoofActive ? %orig(newVersionMajor) : %orig(i);
		}

		- (void)setSecondary: (int)i
		{
			versionSpoofActive ? %orig(newVersionMinor) : %orig(i);
		}

		- (void)setTertiary: (int)i
		{
			versionSpoofActive ? %orig(newVersionBuild) : %orig(i);
		}

		- (void)setQuaternary: (int)i
		{
			versionSpoofActive ? %orig(newVersionRevision) : %orig(i);
		}

	%end

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
	preferences = [NSDictionary dictionaryWithContentsOfFile: ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.macthemes.phantomprefs.plist")];

	enabled = preferences[@"enabled"] ? [preferences[@"enabled"] boolValue] : YES;

	if (enabled)
	{
		debugLogging = preferences[@"debugLogging"] ? [preferences[@"debugLogging"] boolValue] : NO;
		fixNotifications = preferences[@"fixNotifications"] ? [preferences[@"fixNotifications"] boolValue] : NO;

		// Version spoof is only active when the user has explicitly saved a version in Settings.
		// Defaulting to the installed version would still cause proto mismatches; skipping is safer.
		NSString *userVersion = preferences[@"newVersion"] ? [preferences[@"newVersion"] stringValue] : nil;

		NSPredicate *isValidVersion = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", @"^\\d+(\\.\\d+){2,3}$"];

		if (userVersion && [isValidVersion evaluateWithObject: userVersion])
		{
			newVersion = userVersion;
			versionSpoofActive = YES;
		}
		else
		{
			versionSpoofActive = NO;
		}

		if (versionSpoofActive)
		{
			NSArray *components = [newVersion componentsSeparatedByString: @"."];

			newVersionMajor = [components[0] intValue];
			newVersionMinor = [components[1] intValue];
			newVersionBuild = [components[2] intValue];
			newVersionRevision = ([components count] > 3) ? [components[3] intValue] : 0;
		}

		NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
		NSString *frameworkPath = [bundlePath stringByAppendingPathComponent: @"Frameworks/SharedModules.framework/SharedModules"];

		void *image = dlopen([frameworkPath UTF8String], RTLD_LAZY);

		%init(Phantom);

		if (image)
		{
			void * _WAAppExpirationDate = dlsym(image, "WAAppExpirationDate");

			if (_WAAppExpirationDate)
			{
				if (debugLogging)
				{
					NSDate * (*func)() = (NSDate *(*)())_WAAppExpirationDate;
					NSLog(@"WAAppExpirationDate result: %@", func());
				}

				MSHookFunction(_WAAppExpirationDate, (void *)&_new_WAAppExpirationDate, (void **)&_orig_WAAppExpirationDate);
			}
			else if (debugLogging)
			{
				NSLog(@"Failed to find WAAppExpirationDate");
			}

			void * _WABuildDate = dlsym(image, "WABuildDate");

			if (_WABuildDate)
			{
				if (debugLogging)
				{
					NSDate * (*func)() = (NSDate *(*)())_WABuildDate;
					NSLog(@"WABuildDate result: %@", func());
				}

				MSHookFunction(_WABuildDate, (void *)&_new_WABuildDate, (void **)&_orig_WABuildDate);
			}
			else if (debugLogging)
			{
				NSLog(@"Failed to find WABuildDate");
			}

			// Only hook WABuildVersion when version spoof is active
			if (versionSpoofActive)
			{
				void * _WABuildVersion = dlsym(image, "WABuildVersion");

				if (_WABuildVersion)
				{
					if (debugLogging)
					{
						NSString * (*func)(void *, void *) = (NSString *(*)(void *, void *))_WABuildVersion;
						NSLog(@"WABuildVersion result: %@", func((void*)@"", (void*)@""));
					}

					MSHookFunction(_WABuildVersion, (void *)&_new_WABuildVersion, (void **)&_orig_WABuildVersion);
				}
				else if (debugLogging)
				{
					NSLog(@"Failed to find WABuildVersion");
				}
			}

			// WABuildHash: intentionally not hooked — spoofing the hash breaks server auth

			void *_WADeprecatedPlatformCutOffDate = dlsym(image, "_WADeprecatedPlatformCutOffDate");

			if (_WADeprecatedPlatformCutOffDate)
			{
				if (debugLogging)
				{
					NSDate * (*func)() = (NSDate *(*)())_WADeprecatedPlatformCutOffDate;
					NSLog(@"WADeprecatedPlatformCutOffDate result: %@", func());
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
