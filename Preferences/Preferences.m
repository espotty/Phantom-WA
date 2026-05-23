#import "Preferences.h"

#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare: v options: NSNumericSearch] == NSOrderedAscending)

@implementation PhantomPreferencesListController

	MTAutumnBoard *autumnBoard;

	- (NSArray *)specifiers
	{
		if (!_specifiers)
		{
			_specifiers = [self loadSpecifiersFromPlistName: @"Root" target: self];
		}

		return _specifiers;
	}

	- (instancetype)init
	{
		self = [super init];

		if (self)
		{
			autumnBoard = [[MTAutumnBoard alloc] init];

			UIButton *applyButton = [UIButton buttonWithType: UIButtonTypeCustom];

			applyButton.frame = CGRectMake(0, 0, 30, 30);
			applyButton.layer.masksToBounds = YES;

			UIImage *imageCheckmark = [UIImage imageNamed: @"checkmark.png" inBundle: [NSBundle bundleForClass: self.class] compatibleWithTraitCollection: nil];

			[applyButton setImage: [imageCheckmark imageWithRenderingMode: UIImageRenderingModeAlwaysTemplate] forState: UIControlStateNormal];
			[applyButton addTarget: self action: @selector(applyChanges:) forControlEvents: UIControlEventTouchUpInside];

			applyButton.tintColor = [autumnBoard tintApply];

			self.applyButtonItem = [[UIBarButtonItem alloc] initWithCustomView: applyButton];

			self.navigationItem.titleView = [UIView new];

			self.iconView = [[UIImageView alloc] initWithFrame: CGRectMake(0, 0, 10, 10)];

			self.iconView.alpha = 0.0;
			self.iconView.contentMode = UIViewContentModeScaleAspectFit;
			self.iconView.image = [UIImage imageNamed: @"icon.png" inBundle: [NSBundle bundleForClass: self.class] compatibleWithTraitCollection: nil];
			self.iconView.translatesAutoresizingMaskIntoConstraints = NO;

			[self.navigationItem.titleView addSubview: self.iconView];

			[NSLayoutConstraint activateConstraints:
			@[
				[self.iconView.topAnchor constraintEqualToAnchor: self.navigationItem.titleView.topAnchor],
				[self.iconView.leadingAnchor constraintEqualToAnchor: self.navigationItem.titleView.leadingAnchor],
				[self.iconView.trailingAnchor constraintEqualToAnchor: self.navigationItem.titleView.trailingAnchor],
				[self.iconView.bottomAnchor constraintEqualToAnchor: self.navigationItem.titleView.bottomAnchor]
			]];
		}

		return self;
	}

	- (void)viewDidLoad
	{
		[super viewDidLoad];

		UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget: self action: @selector(dismissKeyboard)];

		[self.view addGestureRecognizer: tapGestureRecognizer];

		tapGestureRecognizer.cancelsTouchesInView = NO;

		UIImage *headerImage = [UIImage imageNamed: @"banner.png" inBundle: [NSBundle bundleForClass: self.class] compatibleWithTraitCollection: nil];

		if (headerImage)
		{
			self.headerView = [[UIImageView alloc] initWithFrame: CGRectMake(0, 0, headerImage.size.width, headerImage.size.height)];

			self.headerImageView = [[UIImageView alloc] initWithFrame: CGRectMake(0, 0, 0, 0)];

			self.headerImageView.contentMode = UIViewContentModeScaleAspectFill;
			self.headerImageView.image = headerImage;
			self.headerImageView.translatesAutoresizingMaskIntoConstraints = NO;

			[self.headerView addSubview: self.headerImageView];

			[NSLayoutConstraint activateConstraints:
			@[
				[self.headerImageView.widthAnchor constraintEqualToConstant: headerImage.size.width],
				[self.headerImageView.heightAnchor constraintEqualToConstant: headerImage.size.height],
				[self.headerImageView.centerXAnchor constraintEqualToAnchor: self.headerView.centerXAnchor],
				[self.headerImageView.topAnchor constraintEqualToAnchor: self.headerView.topAnchor constant: 25]
			]];

			tableViewRoot.tableHeaderView = self.headerView;
		}

		tableViewRoot.userInteractionEnabled = YES;

		[[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(handleNo:) name: UIApplicationDidEnterBackgroundNotification object: nil];
	}

	- (void)viewWillAppear: (BOOL)animated
	{
		[super viewWillAppear: animated];

		[self.navigationController.navigationController.navigationBar setShadowImage: [UIImage new]];

		self.navigationController.navigationController.navigationBar.tintColor = [autumnBoard tintNavBar];
	}

	- (void)viewWillDisappear: (BOOL)animated
	{
		[super viewWillDisappear: animated];

		self.navigationController.navigationController.navigationBar.tintColor = nil;
	}

	- (void)scrollViewDidScroll: (UIScrollView *)scrollView
	{
		CGFloat headerHeight = self.headerImageView.bounds.size.height - (SYSTEM_VERSION_LESS_THAN(@"13.0") ? 38 : 66);

		CGFloat offsetY = scrollView.contentOffset.y;

		if (offsetY > headerHeight)
		{
			[UIView animateWithDuration: 0.2 animations: ^
			{
				self.iconView.alpha = 1.0;
			}];
		}
		else
		{
			[UIView animateWithDuration: 0.2 animations: ^
			{
				self.iconView.alpha = 0.0;
			}];
		}
	}

	- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController: (UIPresentationController *)controller
	{
		return UIModalPresentationNone;
	}

	- (UITableViewCell *)tableView: (UITableView *)tableView cellForRowAtIndexPath: (NSIndexPath *)indexPath
	{
		tableView.tableHeaderView = self.headerView;

		return [super tableView: tableView cellForRowAtIndexPath: indexPath];
	}

	- (void)visitWebsite: (id)sender
	{
		[[UIApplication sharedApplication] openURL: [NSURL URLWithString: @"https://github.com/espotty/Axolotl-fixed"] options: @{} completionHandler: nil];
	}

	- (void)visitTwitter: (id)sender
	{
		// No-op: removed Twitter link
	}

	- (void)applyChanges: (UIButton *)sender
	{
		[self.view endEditing: YES];

		NSBundle *prefBundle = [NSBundle bundleForClass: self.class];

		NSString *applyLabelText = [prefBundle localizedStringForKey: @"AXApplyLabel" value: @"" table: nil];
		NSString *yesButtonTitle = [prefBundle localizedStringForKey: @"AXApplyYes" value: @"" table: nil];
		NSString *noButtonTitle = [prefBundle localizedStringForKey: @"AXApplyNo" value: @"" table: nil];

		self.popController = [[UIViewController alloc] init];

		self.popController.modalPresentationStyle = UIModalPresentationPopover;
		self.popController.preferredContentSize = CGSizeMake(200, 130);

		double offsetY = (SYSTEM_VERSION_LESS_THAN(@"13.0") ? 0 : 12.5);

		UILabel *applyLabel = [[UILabel alloc] init];

		applyLabel.adjustsFontSizeToFitWidth = YES;
		applyLabel.font = [UIFont boldSystemFontOfSize: 20];
		applyLabel.frame = CGRectMake(20, 10 + offsetY, 160, 60);
		applyLabel.numberOfLines = 2;
		applyLabel.text = applyLabelText;
		applyLabel.textAlignment = NSTextAlignmentCenter;
		applyLabel.textColor = [applyLabel.textColor colorWithAlphaComponent: 0.75];

		[self.popController.view addSubview: applyLabel];

		UIButton *yesButton = [UIButton buttonWithType: UIButtonTypeCustom];

		yesButton.frame = CGRectMake(100, 85 + offsetY, 100, 30);
		yesButton.titleLabel.font = [UIFont boldSystemFontOfSize: 20];

		[yesButton addTarget: self action: @selector(handleYes:) forControlEvents: UIControlEventTouchUpInside];
		[yesButton setTitle: yesButtonTitle forState: UIControlStateNormal];
		[yesButton setTitleColor: [autumnBoard tintApplyYes] forState: UIControlStateNormal];

		[self.popController.view addSubview: yesButton];

		UIButton *noButton = [UIButton buttonWithType: UIButtonTypeCustom];

		noButton.frame = CGRectMake(0, 85 + offsetY, 100, 30);
		noButton.titleLabel.font = [UIFont boldSystemFontOfSize: 20];

		[noButton addTarget: self action: @selector(handleNo:) forControlEvents: UIControlEventTouchUpInside];
		[noButton setTitle: noButtonTitle forState: UIControlStateNormal];
		[noButton setTitleColor: [autumnBoard tintApplyNo] forState: UIControlStateNormal];

		[self.popController.view addSubview: noButton];

		UIPopoverPresentationController *popover = self.popController.popoverPresentationController;

		popover.delegate = self;
		popover.permittedArrowDirections = UIPopoverArrowDirectionUp;
		popover.barButtonItem = self.applyButtonItem;

		[self presentViewController: self.popController animated: YES completion: nil];
	}

	- (void)handleYes: (UIButton *)sender
	{
		[self.popController dismissViewControllerAnimated: YES completion: nil];

		pid_t pid;

		const char* args[] = { "-9", "WhatsApp", NULL };

		posix_spawn(&pid, ROOT_PATH("/usr/bin/killall"), NULL, NULL, (char* const*)args, NULL);
	}

	- (void)handleNo: (UIButton *)sender
	{
		[self.popController dismissViewControllerAnimated: YES completion: nil];
	}

	- (void)dismissKeyboard
	{
		[self.view endEditing: YES];
	}

	- (void)open: (PSSpecifier *)sender
	{
		[[UIApplication sharedApplication] openURL: [NSURL URLWithString: [sender propertyForKey: @"url"]] options: @{} completionHandler: nil];
	}

@end
