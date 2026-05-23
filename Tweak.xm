#import <Foundation/Foundation.h>

#import <rootless.h>

#include <dlfcn.h>

#include <CydiaSubstrate/CydiaSubstrate.h>

#define DEFAULT_VERSION    @"25.1.83.0"
#define SPOOF_IOS_VERSION  @"17.5.1"
#define SPOOF_IOS_BUILD    @"21F90"

// Declared here, used by WAGOTHook.m
int       newVersionMajor;
int       newVersionMinor;
int       newVersionBuild;
int       newVersionRevision;
NSString *newVersion;
NSString *spoofedUserAgent;
BOOL      debugLogging;

/*
	Preferences …
*/
NSDictionary *preferences;

BOOL enabled;
BOOL fixNotifications;

// Forward declaration from WAGOTHook.m
void wa_got_hook_apply(void);

/*
	ObjC Hooks …
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

	// Spoof iOS version in the protobuf user-agent payload.
	%hook WAPBClientPayload_UserAgent

		- (NSString *)osVersion     { return SPOOF_IOS_VERSION; }
		- (NSString *)osBuildNumber { return SPOOF_IOS_BUILD; }

	%end

	%hook WARootViewController

		- (bool)isBuildExpired      { return NO; }
		- (void)expireBuild         { return; }
		- (void)presentHelperScreen { return; }

		- (void)wa_applicationDidEnterBackground { %orig; }

	%end

	%hook WamEventDaily

		- (double)iphone_jailbroken { return 0; }

	%end

%end

/*
	Constructor …
*/
%ctor
{
	preferences = [NSDictionary dictionaryWithContentsOfFile:
	               ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.macthemes.phantomprefs.plist")];

	enabled = preferences[@"enabled"] ? [preferences[@"enabled"] boolValue] : YES;

	if (enabled)
	{
		debugLogging     = preferences[@"debugLogging"]     ? [preferences[@"debugLogging"] boolValue]     : NO;
		fixNotifications = preferences[@"fixNotifications"] ? [preferences[@"fixNotifications"] boolValue] : NO;

		// Use user-set version or fall back to DEFAULT_VERSION.
		NSString *userVersion = preferences[@"newVersion"] ? [preferences[@"newVersion"] stringValue] : nil;
		NSPredicate *isValid  = [NSPredicate predicateWithFormat: @"SELF MATCHES %@", @"^\\d+(\\.\\d+){2,3}$"];

		newVersion = (userVersion && [isValid evaluateWithObject: userVersion]) ? userVersion : DEFAULT_VERSION;

		NSArray *components = [newVersion componentsSeparatedByString: @"."];
		newVersionMajor    = [components[0] intValue];
		newVersionMinor    = [components[1] intValue];
		newVersionBuild    = [components[2] intValue];
		newVersionRevision = ([components count] > 3) ? [components[3] intValue] : 0;

		spoofedUserAgent = [NSString stringWithFormat: @"WhatsApp/%@ iOS/%@ Device/iPhone14,3",
		                    newVersion, SPOOF_IOS_VERSION];

		%init(Phantom);

		// Apply GOT rebinding for all WA C functions (works even for non-exported symbols).
		// This is the same mechanism used by wafix and is more reliable than MSHookFunction
		// when symbols are not in the SharedModules export table.
		wa_got_hook_apply();

		return;
	}
}
