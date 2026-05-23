#import "MTTintedSwitchCell.h"

@implementation MTTintedSwitchCell
{
	UIColor *switchOnTintColor;
}

	- (instancetype)initWithStyle: (UITableViewCellStyle)style reuseIdentifier: (NSString *)identifier specifier: (PSSpecifier *)specifier
	{
		self = [super initWithStyle: style reuseIdentifier: identifier specifier: specifier];

		MTAutumnBoard *autumnBoard = [[MTAutumnBoard alloc] init];

		NSString *key = [specifier propertyForKey: @"key"];

		if ([key isEqual: @"debugLogging"])
		{
			switchOnTintColor = [autumnBoard tintDebug];
		}
		else if ([key isEqual: @"enabled"])
		{
			switchOnTintColor = [autumnBoard tintEnable];
		}

		return self;
	}

	- (void)layoutSubviews
	{
		[super layoutSubviews];

		[((UISwitch *)self.control) setOnTintColor: switchOnTintColor];
	}

@end
