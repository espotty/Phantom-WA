#import "MTAutumnBoard.h"

@implementation MTAutumnBoard

	- (id)init
	{
		self = [super init];

		if (self)
		{
			NSBundle *prefBundle = [NSBundle bundleForClass: self.class];
			NSString *prefBundleTheme = ROOT_PATH_NS([prefBundle pathForResource: @"Theme" ofType: @"plist"]);

			NSDictionary *theme = [NSDictionary dictionaryWithContentsOfFile: prefBundleTheme];

			NSDictionary *tintColors;

			if(theme[@"AXTintColors"])
			{
				tintColors = theme[@"AXTintColors"];
			}

			_tintApply		= tintColors[@"AXApplyButton"]	 ? [self colorWithHexString: tintColors[@"AXApplyButton"]]	 : [UIColor colorWithRed: 68/255.0f green: 192/255.0f blue: 84/255.0f alpha: 1.0f];
			_tintApplyNo	= tintColors[@"AXApplyNo"]		 ? [self colorWithHexString: tintColors[@"AXApplyNo"]]		 : [UIColor colorWithRed: 68/255.0f green: 192/255.0f blue: 84/255.0f alpha: 1.0f];
			_tintApplyYes	= tintColors[@"AXApplyYes"]		 ? [self colorWithHexString: tintColors[@"AXApplyYes"]]		 : [UIColor colorWithRed: 192/255.0f green: 68/255.0f blue: 84/255.0f alpha: 1.0f];
			_tintDebug		= tintColors[@"AXDebugSwitch"]	 ? [self colorWithHexString: tintColors[@"AXDebugSwitch"]]	 : [UIColor colorWithRed: 68/255.0f green: 192/255.0f blue: 84/255.0f alpha: 1.0f];
			_tintEnable		= tintColors[@"AXEnableSwitch"]	 ? [self colorWithHexString: tintColors[@"AXEnableSwitch"]]	 : [UIColor colorWithRed: 68/255.0f green: 192/255.0f blue: 84/255.0f alpha: 1.0f];
			_tintNavBar		= tintColors[@"AXNavigationBar"] ? [self colorWithHexString: tintColors[@"AXNavigationBar"]] : [UIColor colorWithRed: 68/255.0f green: 192/255.0f blue: 84/255.0f alpha: 1.0f];
			_tintTwitter	= tintColors[@"AXTwitterButton"] ? [self colorWithHexString: tintColors[@"AXTwitterButton"]] : [UIColor colorWithRed: 0/255.0f green: 152/255.0f blue: 192/255.0f alpha: 1.0f];
			_tintWebsite	= tintColors[@"AXWebsiteButton"] ? [self colorWithHexString: tintColors[@"AXWebsiteButton"]] : [UIColor colorWithRed: 114/255.0f green: 115/255.0f blue: 115/255.0f alpha: 1.0f];
		}

		return self;
	}

	- (UIColor *)colorWithHexString: (NSString *)stringToConvert
	{
		NSArray *components = [stringToConvert componentsSeparatedByString: @":"];

		NSString *hashString = ([components count] > 0) ? components[0] : components;

		float alphaValue = ([components count] > 1) ? [components[1] floatValue] : 1.0f;

		NSString *noHashString = [hashString stringByReplacingOccurrencesOfString: @"#" withString: @""];

		NSScanner *scanner = [NSScanner scannerWithString: noHashString];

		[scanner setCharactersToBeSkipped: [NSCharacterSet symbolCharacterSet]];

		unsigned hex;

		if (! [scanner scanHexInt: &hex])
		{
			return nil;
		}

		int red = (hex >> 16) & 0xFF;
		int green = (hex >> 8) & 0xFF;
		int blue = (hex) & 0xFF;

		return [UIColor colorWithRed: red/255.0f green: green/255.0f blue: blue/255.0f alpha: alphaValue];
	}

@end
