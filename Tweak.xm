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
static int        (*_orig_WABuildVersionComponent1)();
static int        (*_orig_WABuildVersionComponent2)();
static int        (*_orig_WABuildVersionComponent3)();
static int        (*_orig_WABuildVersionComponent4)();

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

// Individual version component functions — must be consistent with WABuildVersion.
static int _new_WABuildVersionComponent1() { return newVersionMajor; }
static int _new_WABuildVersionComponent2() { return newVersionMinor; }
static int _new_WABuildVersionComponent3() { return newVersionBuild; }
static int _new_WABuildVersionComponent4() { return newVersionRevision; }

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
	%hook WAPBClientPayload_UserAgent_AppVersion

		- (unsigned int)primary    { return (unsigned int)newVersionMajor; }
		- (unsigned int)secondary  { return (unsigned int)newVersionMinor; }
		- (unsigned int)tertiary   { return (unsigned int)newVersionBuild; }
		- (unsigned int)quaternary { return (unsigned int)newVersionRevision; }

	%end

	// Spoof iOS version sent to server in the protobuf user-agent payload.
	// The server rejects iOS 14 connections; spoofing to iOS 17 allows them through.
	%hook WAPBClientPayload_UserAgent

		- (NSString *)osVersion     { return SPOOF_IOS_VERSION; }
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
	Helper — tries to find a symbol in SharedModules then the main binary.
*/
static void tryHook(void *sharedModules, void *mainBin,
                    const char *name, void *replacement, void **orig)
{
	void *sym = dlsym(sharedModules, name);
	if (!sym && mainBin) sym = dlsym(mainBin, name);

	if (sym)
	{
		MSHookFunction(sym, replacement, orig);

		if (debugLogging) NSLog(@"[Phantom] Hooked: %s", name);
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
		debugLogging     = preferences[@"debugLogging"]     ? [preferences[@"debugLogging"] boolValue]     : NO;
		fixNotifications = preferences[@"fixNotifications"] ? [preferences[@"fixNotifications"] boolValue] : NO;

		// Use user-set version or fall back to DEFAULT_VERSION.
		NSString *userVersion   = preferences[@"newVersion"] ? [preferences[@"newVersion"] stringValue] : nil;
		NSPredicate *isValid    = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", @"^\\d+(\\.\\d+){2,3}$"];

		newVersion = (userVersion && [isValid evaluateWithObject: userVersion]) ? userVersion : DEFAULT_VERSION;

		NSArray *components = [newVersion componentsSeparatedByString: @"."];
		newVersionMajor    = [components[0] intValue];
		newVersionMinor    = [components[1] intValue];
		newVersionBuild    = [components[2] intValue];
		newVersionRevision = ([components count] > 3) ? [components[3] intValue] : 0;

		spoofedUserAgent = [NSString stringWithFormat: @"WhatsApp/%@ iOS/%@ Device/iPhone14,3",
		                    newVersion, SPOOF_IOS_VERSION];

		// Open SharedModules framework and the main WhatsApp binary.
		NSString *bundlePath    = [[NSBundle mainBundle] bundlePath];
		NSString *frameworkPath = [bundlePath stringByAppendingPathComponent:
		                           @"Frameworks/SharedModules.framework/SharedModules"];

		void *sharedModules = dlopen([frameworkPath UTF8String], RTLD_LAZY);
		void *mainBin       = dlopen(NULL, RTLD_LAZY);

		%init(Phantom);

		if (sharedModules || mainBin)
		{
			tryHook(sharedModules, mainBin,
			        "WAAppExpirationDate",
			        (void *)&_new_WAAppExpirationDate,
			        (void **)&_orig_WAAppExpirationDate);

			tryHook(sharedModules, mainBin,
			        "WABuildDate",
			        (void *)&_new_WABuildDate,
			        (void **)&_orig_WABuildDate);

			tryHook(sharedModules, mainBin,
			        "WABuildVersion",
			        (void *)&_new_WABuildVersion,
			        (void **)&_orig_WABuildVersion);

			// Key fix: spoof the HTTP User-Agent so server doesn't see iOS 14
			tryHook(sharedModules, mainBin,
			        "WABuildHTTPUserAgentString",
			        (void *)&_new_WABuildHTTPUserAgentString,
			        (void **)&_orig_WABuildHTTPUserAgentString);

			// Key fix: tell WhatsApp we are NOT past the deprecated platform cutoff
			tryHook(sharedModules, mainBin,
			        "WAIsAfterDeprecatedPlatformCutoffDate",
			        (void *)&_new_WAIsAfterDeprecatedPlatformCutoffDate,
			        (void **)&_orig_WAIsAfterDeprecatedPlatformCutoffDate);

			tryHook(sharedModules, mainBin,
			        "WADeprecatedPlatformCutOffDate",
			        (void *)&_new_WADeprecatedPlatformCutOffDate,
			        (void **)&_orig_WADeprecatedPlatformCutOffDate);

			// Suppress internal failure handler to prevent crashes
			tryHook(sharedModules, mainBin,
			        "WAHandleFailureInFunction",
			        (void *)&_new_WAHandleFailureInFunction,
			        (void **)&_orig_WAHandleFailureInFunction);

			// Version components must be consistent with WABuildVersion string
			tryHook(sharedModules, mainBin,
			        "WABuildVersionComponent1",
			        (void *)&_new_WABuildVersionComponent1,
			        (void **)&_orig_WABuildVersionComponent1);

			tryHook(sharedModules, mainBin,
			        "WABuildVersionComponent2",
			        (void *)&_new_WABuildVersionComponent2,
			        (void **)&_orig_WABuildVersionComponent2);

			tryHook(sharedModules, mainBin,
			        "WABuildVersionComponent3",
			        (void *)&_new_WABuildVersionComponent3,
			        (void **)&_orig_WABuildVersionComponent3);

			tryHook(sharedModules, mainBin,
			        "WABuildVersionComponent4",
			        (void *)&_new_WABuildVersionComponent4,
			        (void **)&_orig_WABuildVersionComponent4);

			// WABuildHash: intentionally not hooked — spoofing the hash breaks server auth
		}
		else if (debugLogging)
		{
			NSLog(@"[Phantom] Failed to open any image to hook");
		}

		return;
	}
}
