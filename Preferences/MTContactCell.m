#import "MTContactCell.h"

@implementation MTContactCell
{
	UIImageView *imageView;

	UILabel *title;
	UILabel *subTitle;
}

	- (instancetype)initWithStyle: (UITableViewCellStyle)style reuseIdentifier: (NSString *)identifier specifier: (PSSpecifier *)specifier
	{
		self = [super initWithStyle: style reuseIdentifier: identifier specifier: specifier];

		if (self)
		{
			NSBundle *prefBundle = [NSBundle bundleForClass: self.class];

			NSString *localizedTitle = [prefBundle localizedStringForKey: [specifier propertyForKey: @"title"] value: @"" table: nil];
			NSString *localizedSubTitle = [prefBundle localizedStringForKey: [specifier propertyForKey: @"subTitle"] value: @"" table: nil];

			UIImage *image = [UIImage imageNamed: [specifier propertyForKey: @"image"] inBundle: [NSBundle bundleForClass: self.class] compatibleWithTraitCollection: nil];

			imageView = [[UIImageView alloc] initWithImage: image];

			imageView.layer.masksToBounds = true;
			imageView.translatesAutoresizingMaskIntoConstraints = false;

			[self.contentView addSubview: imageView];

			title = [UILabel new];

			title.text = localizedTitle;
			title.font = [UIFont systemFontOfSize: 15];
			title.translatesAutoresizingMaskIntoConstraints = false;

			[self.contentView addSubview: title];

			subTitle = [UILabel new];

			subTitle.font = [UIFont systemFontOfSize: 11];
			subTitle.text = localizedSubTitle;
			subTitle.textColor = UIColor.systemGrayColor;
			subTitle.translatesAutoresizingMaskIntoConstraints = false;

			[self.contentView addSubview: subTitle];
		}

		return self;
	}

	- (void)layoutSubviews
	{
		[super layoutSubviews];

		[NSLayoutConstraint activateConstraints:
		@[
			[imageView.centerYAnchor constraintEqualToAnchor: self.centerYAnchor],
			[imageView.leadingAnchor constraintEqualToAnchor: self.leadingAnchor constant: 15],
			[imageView.heightAnchor constraintEqualToConstant: 40],
			[imageView.widthAnchor constraintEqualToConstant: 40],

			[title.topAnchor constraintEqualToAnchor: self.centerYAnchor constant: -19.5],
			[title.leadingAnchor constraintEqualToAnchor: imageView.trailingAnchor constant: 10],
			[title.heightAnchor constraintEqualToConstant: 20],

			[subTitle.bottomAnchor constraintEqualToAnchor: self.centerYAnchor constant: 19.5],
			[subTitle.leadingAnchor constraintEqualToAnchor: imageView.trailingAnchor constant: 10],
			[subTitle.heightAnchor constraintEqualToConstant: 20],
		]];
	}

@end
