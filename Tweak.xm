#import <Foundation/Foundation.h>

#import <rootless.h>

#include <dlfcn.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

#define DEFAULT_VERSION    @"25.1.83.0"
#define SPOOF_IOS_VERSION  @"17.5.1"
#define SPOOF_IOS_BUILD    @"21F90"

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
NSString *spoofedUserAgent;

/*
	C Function Originals …
*/
static NSDate *   (*_orig_WAAppExpirationDate)();
static NSDate *   (*_orig_WABuildDate)();
static NSDate *   (*_orig_WADeprecatedPlatformCutOffDate)();
static NSString * (*_orig_WABuildVersion)(void *, void *);
static NSString * (*_orig_WABuildHTTPUserAgentString)();
static int        (*_orig_WAIsAfterDeprecatedPlatformCutoffDate)();
static void       (*_orig_WAHandleFailureInFunction)();

/*
	C Function Overrides …
*/
static NSDate *_new_WAAppExpirationDate()
{
	if (debugLogging) NSLog(@"[Phantom] WAAppExpirationDate called");
	return [NSDate dateWithTimeIntervalSinceNow: 315360000.0];
}

static NSDate *_new_WABuildDate()
{
	if (debugLogging) NSLog(@"[Phantom] WABuildDate called");
	return [NSDate date];
}

static NSString *_new_WABuildVersion(void *arg1, void *arg2)
{
	if (debugLogging) NSLog(@"[Phantom] WABuildVersion → %@", newVersion);
	return newVersion;
}

static NSDate *_new_WADeprecatedPlatformCutOffDate()
{
	if (debugLogging) NSLog(@"[Phantom] WADeprecatedPlatformCutOffDate called");
	return [NSDate dateWithTimeIntervalSinceNow: 315360000.0];
}

// Spoof the HTTP User-Agent sent to WhatsApp servers.
// Without this, the server sees "iOS/14.x" and rejects the connection.
static NSString *_new_WABuildHTTPUserAgentString()
{
	if (debugLogging) NSLog(@"[Phantom] WABuildHTTPUserAgentString → %@", spoofedUserAgent);
	return spoofedUserAgent;
}

// Return 0 (false) — we are NOT after the deprecated platform cutoff date.
static int _new_WAIsAfterDeprecatedPlatformCutoffDate()
{
	if (debugLogging) NSLog(@"[Phantom] WAIsAfterDeprecatedPlatformCutoffDate → 0");
	return 0;
}

// Suppress internal failure handler to prevent crashes on version mismatch.
static void _new_WAHandleFailureInFunction()
{
	if (debugLogging) NSLog(@"[Phantom] WAHandleFailureInFunction suppressed");
}

/*
	Hooks …
*/
%group Phantom

	%hook WALogWriter

		- (NSString*)formatLogText: (NSString*)ar1 withLevel: (int)ar2
		{
			NSString *result = %orig;
			if (debugLogging) NSLog(@"WALog: %@", result);
			return result;
		}

	%end

	%hook WAMessage

		- (bool)needsLocalNotification
		{
			return fixNotifications ? true : %orig;
		}

	%end

	// Hook getters (read path) — called when proto is serialized and sent to server.
	// Hooking setters is not enough; the server reads these getter values directly.
	%hook WAPBClientPayload_UserAgent_AppVersion

		- (unsigned int)primary    { return (unsigned int)newVersionMajor; }
		- (unsigned int)secondary  { return (unsigned int)newVersionMinor; }
		- (unsigned int)tertiary   { return (unsigned int)newVersionBuild; }
		- (unsigned int)quaternary { return (unsigned int)newVersionRevision; }

	%end

	// Spoof iOS version sent to server in the protobuf user-agent payload.
	// The server rejects iOS 14 connections; spoofing to iOS 17 allows them through.
	%hook WAPBClientPayload_UserAgent

		- (NSString *)osVersion    { return SPOOF_IOS_VERSION; }
		- (NSString *)osBuildNumber { return SPOOF_IOS_BUILD; }

	%end

	%hook WARootViewController

		- (bool)isBuildExpired      { return NO; }
		- (void)expireBuild         { return; }
		- (void)presentHelperScreen { return; }

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
	Helper …
*/
static void hookSym(void *image, const char *name, void *replacement, void **orig)
{
	void *sym = dlsym(image, name);

	if (!sym)
	{
		// some symbols are exported with a leading underscore in older frameworks
		char buf[256];
		buf[0] = '_';
		int i = 1;
		while (name[i - 1] && i < 255) { buf[i] = name[i - 1]; i++; }
		buf[i] = '\0';
		sym = dlsym(image, buf);
	}

	if (sym)
	{
		MSHookFunction(sym, replacement, orig);
	}
	else if (debugLogging)
	{
		NSLog(@"[Phantom] Symbol not found: %s", name);
	}
}

/*
	Constructor …
*/
%ctor
{
	preferences = [NSDictionary dictionaryWithContentsOfFile: ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.macthemes.phantomprefs.plist")];

	enabled = preferences[@"enabled"] ? [preferences[@"enabled"] boolValue] : YES;

	if (enabled)
	{
		debugLogging    = preferences[@"debugLogging"]    ? [preferences[@"debugLogging"] boolValue]    : NO;
		fixNotifications = preferences[@"fixNotifications"] ? [preferences[@"fixNotifications"] boolValue] : NO;

		// Use user-set version or fall back to DEFAULT_VERSION.
		NSString *userVersion = preferences[@"newVersion"] ? [preferences[@"newVersion"] stringValue] : nil;
		NSPredicate *isValidVersion = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", @"^\\d+(\\.\\d+){2,3}$"];

		if (userVersion && [isValidVersion evaluateWithObject: userVersion])
			newVersion = userVersion;
		else
			newVersion = DEFAULT_VERSION;

		NSArray *components = [newVersion componentsSeparatedByString: @"."];
		newVersionMajor   = [components[0] intValue];
		newVersionMinor   = [components[1] intValue];
		newVersionBuild   = [components[2] intValue];
		newVersionRevision = ([components count] > 3) ? [components[3] intValue] : 0;

		spoofedUserAgent = [NSString stringWithFormat: @"WhatsApp/%@ iOS/%@ Device/iPhone14,3",
		                    newVersion, SPOOF_IOS_VERSION];

		NSString *bundlePath   = [[NSBundle mainBundle] bundlePath];
		NSString *frameworkPath = [bundlePath stringByAppendingPathComponent: @"Frameworks/SharedModules.framework/SharedModules"];

		void *image = dlopen([frameworkPath UTF8String], RTLD_LAZY);

		%init(Phantom);

		if (image)
		{
			hookSym(image, "WAAppExpirationDate",
			        (void *)&_new_WAAppExpirationDate,
			        (void **)&_orig_WAAppExpirationDate);

			hookSym(image, "WABuildDate",
			        (void *)&_new_WABuildDate,
			        (void **)&_orig_WABuildDate);

			hookSym(image, "WABuildVersion",
			        (void *)&_new_WABuildVersion,
			        (void **)&_orig_WABuildVersion);

			// Key fix: spoof the HTTP User-Agent so server doesn't see iOS 14
			hookSym(image, "WABuildHTTPUserAgentString",
			        (void *)&_new_WABuildHTTPUserAgentString,
			        (void **)&_orig_WABuildHTTPUserAgentString);

			// Key fix: tell WhatsApp we're NOT past the deprecated platform cutoff
			hookSym(image, "WAIsAfterDeprecatedPlatformCutoffDate",
			        (void *)&_new_WAIsAfterDeprecatedPlatformCutoffDate,
			        (void **)&_orig_WAIsAfterDeprecatedPlatformCutoffDate);

			hookSym(image, "WADeprecatedPlatformCutOffDate",
			        (void *)&_new_WADeprecatedPlatformCutOffDate,
			        (void **)&_orig_WADeprecatedPlatformCutOffDate);

			// Prevent crash when WhatsApp detects version inconsistencies
			hookSym(image, "WAHandleFailureInFunction",
			        (void *)&_new_WAHandleFailureInFunction,
			        (void **)&_orig_WAHandleFailureInFunction);

			// WABuildHash: intentionally not hooked — spoofing the hash breaks server auth
		}
		else if (debugLogging)
		{
			NSLog(@"[Phantom] Failed to load SharedModules at: %@", frameworkPath);
		}

		return;
	}
}
