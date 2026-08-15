#import "TGCountryPickerViewController.h"
#import "TGClient.h"
#import "TGTheme.h"

static NSString *TGFlagEmojiForCountryCode(NSString *code) {
	if (code.length != 2)
		return @"🏳️";
	unichar first = [code.uppercaseString characterAtIndex:0];
	unichar second = [code.uppercaseString characterAtIndex:1];
	if (first < 'A' || first > 'Z' || second < 'A' || second > 'Z')
		return @"🏳️";
	UTF32Char regionalFirst = 0x1F1E6 + (first - 'A');
	UTF32Char regionalSecond = 0x1F1E6 + (second - 'A');
	return [NSString stringWithFormat:@"%@%@",
			[[NSString alloc] initWithBytes:&regionalFirst length:4 encoding:NSUTF32LittleEndianStringEncoding],
			[[NSString alloc] initWithBytes:&regionalSecond length:4 encoding:NSUTF32LittleEndianStringEncoding]];
}

static UIColor *TGCountryPickerColour(int rgb) {
	return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
						   green:((rgb >> 8) & 0xff) / 255.0f
							blue:(rgb & 0xff) / 255.0f
						   alpha:1.0f];
}

static NSComparisonResult TGCountryNameCompare(NSString *a, NSString *b) {
	return [a compare:b options:NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch | NSForcedOrderingSearch];
}

static NSArray *TGPhoneCountries(void) {
	static NSArray *list = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSArray *lines = @[
		@"6723;NF;Norfolk Island",
		@"5999;CW;Curaçao",
		@"1939;PR;Puerto Rico",
		@"1876;JM;Jamaica",
		@"1869;KN;Saint Kitts and Nevis",
		@"1868;TT;Trinidad and Tobago",
		@"1849;DO;Dominican Republic",
		@"1829;DO;Dominican Republic",
		@"1809;DO;Dominican Republic",
		@"1787;PR;Puerto Rico",
		@"1784;VC;Saint Vincent and the Grenadines",
		@"1767;DM;Dominica",
		@"1758;LC;Saint Lucia",
		@"1721;SX;Bonaire, Sint Eustatius and Saba",
		@"1684;AS;American Samoa",
		@"1671;GU;Guam",
		@"1670;MP;Northern Mariana Islands",
		@"1664;MS;Montserrat",
		@"1649;TC;Turks and Caicos Islands",
		@"1473;GD;Grenada",
		@"1441;BM;Bermuda",
		@"1345;KY;Cayman Islands",
		@"1340;VI;US Virgin Islands",
		@"1284;VG;British Virgin Islands",
		@"1268;AG;Antigua and Barbuda",
		@"1264;AI;Anguilla",
		@"1246;BB;Barbados",
		@"1242;BS;Bahamas",
		@"998;UZ;Uzbekistan",
		@"996;KG;Kyrgyzstan",
		@"995;GE;Georgia",
		@"994;AZ;Azerbaijan",
		@"993;TM;Turkmenistan",
		@"992;TJ;Tajikistan",
		@"977;NP;Nepal",
		@"976;MN;Mongolia",
		@"975;BT;Bhutan",
		@"974;QA;Qatar",
		@"973;BH;Bahrain",
		@"972;IL;Israel",
		@"971;AE;United Arab Emirates",
		@"970;PS;Palestine",
		@"968;OM;Oman",
		@"967;YE;Yemen",
		@"966;SA;Saudi Arabia",
		@"965;KW;Kuwait",
		@"964;IQ;Iraq",
		@"963;SY;Syria",
		@"962;JO;Jordan",
		@"961;LB;Lebanon",
		@"960;MV;Maldives",
		@"886;TW;Taiwan",
		@"880;BD;Bangladesh",
		@"856;LA;Laos",
		@"855;KH;Cambodia",
		@"853;MO;Macau",
		@"852;HK;Hong Kong",
		@"850;KP;North Korea",
		@"692;MH;Marshall Islands",
		@"691;FM;Micronesia",
		@"690;TK;Tokelau",
		@"689;PF;French Polynesia",
		@"688;TV;Tuvalu",
		@"687;NC;New Caledonia",
		@"686;KI;Kiribati",
		@"685;WS;Samoa",
		@"683;NU;Niue",
		@"682;CK;Cook Islands",
		@"681;WF;Wallis and Futuna",
		@"680;PW;Palau",
		@"679;FJ;Fiji",
		@"678;VU;Vanuatu",
		@"677;SB;Solomon Islands",
		@"676;TO;Tonga",
		@"675;PG;Papua New Guinea",
		@"674;NR;Nauru",
		@"673;BN;Brunei Darussalam",
		@"672;AU;Australia",
		@"670;TL;East Timor",
		@"599;BQ;Sint Maarten",
		@"598;UY;Uruguay",
		@"597;SR;Suriname",
		@"596;MQ;Martinique",
		@"595;PY;Paraguay",
		@"594;GF;French Guiana",
		@"593;EC;Ecuador",
		@"592;GY;Guyana",
		@"591;BO;Bolivia",
		@"590;GP;Guadeloupe",
		@"509;HT;Haiti",
		@"508;PM;Saint Pierre and Miquelon",
		@"507;PA;Panama",
		@"506;CR;Costa Rica",
		@"505;NI;Nicaragua",
		@"504;HN;Honduras",
		@"503;SV;El Salvador",
		@"502;GT;Guatemala",
		@"501;BZ;Belize",
		@"500;FK;Falkland Islands",
		@"423;LI;Liechtenstein",
		@"421;SK;Slovakia",
		@"420;CZ;Czech Republic",
		@"389;MK;Macedonia",
		@"387;BA;Bosnia and Herzegovina",
		@"386;SI;Slovenia",
		@"385;HR;Croatia",
		@"382;ME;Montenegro",
		@"381;RS;Serbia",
		@"380;UA;Ukraine",
		@"378;SM;San Marino",
		@"377;MC;Monaco",
		@"376;AD;Andorra",
		@"375;BY;Belarus",
		@"374;AM;Armenia",
		@"373;MD;Moldova",
		@"372;EE;Estonia",
		@"371;LV;Latvia",
		@"370;LT;Lithuania",
		@"359;BG;Bulgaria",
		@"358;FI;Finland",
		@"357;CY;Cyprus",
		@"356;MT;Malta",
		@"355;AL;Albania",
		@"354;IS;Iceland",
		@"353;IE;Ireland",
		@"352;LU;Luxembourg",
		@"351;PT;Portugal",
		@"350;GI;Gibraltar",
		@"299;GL;Greenland",
		@"298;FO;Faroe Islands",
		@"297;AW;Aruba",
		@"291;ER;Eritrea",
		@"290;SH;Saint Helena",
		@"269;KM;Comoros",
		@"268;SZ;Swaziland",
		@"267;BW;Botswana",
		@"266;LS;Lesotho",
		@"265;MW;Malawi",
		@"264;NA;Namibia",
		@"263;ZW;Zimbabwe",
		@"262;RE;Réunion",
		@"261;MG;Madagascar",
		@"260;ZM;Zambia",
		@"258;MZ;Mozambique",
		@"257;BI;Burundi",
		@"256;UG;Uganda",
		@"255;TZ;Tanzania",
		@"254;KE;Kenya",
		@"253;DJ;Djibouti",
		@"252;SO;Somalia",
		@"251;ET;Ethiopia",
		@"250;RW;Rwanda",
		@"249;SD;Sudan",
		@"248;SC;Seychelles",
		@"247;SH;Saint Helena",
		@"246;IO;United Kingdom",
		@"245;GW;Guinea-Bissau",
		@"244;AO;Angola",
		@"243;CD;Congo, Democratic Republic",
		@"242;CG;Congo",
		@"241;GA;Gabon",
		@"240;GQ;Equatorial Guinea",
		@"239;ST;São Tomé and Príncipe",
		@"238;CV;Cape Verde",
		@"237;CM;Cameroon",
		@"236;CF;Central African Republic",
		@"235;TD;Chad",
		@"234;NG;Nigeria",
		@"233;GH;Ghana",
		@"232;SL;Sierra Leone",
		@"231;LR;Liberia",
		@"230;MU;Mauritius",
		@"229;BJ;Benin",
		@"228;TG;Togo",
		@"227;NE;Niger",
		@"226;BF;Burkina Faso",
		@"225;CI;Côte d`Ivoire",
		@"224;GN;Guinea",
		@"223;ML;Mali",
		@"222;MR;Mauritania",
		@"221;SN;Senegal",
		@"220;GM;Gambia",
		@"218;LY;Libya",
		@"216;TN;Tunisia",
		@"213;DZ;Algeria",
		@"212;MA;Morocco",
		@"211;SS;South Sudan",
		@"98;IR;Iran",
		@"95;MM;Myanmar",
		@"94;LK;Sri Lanka",
		@"93;AF;Afghanistan",
		@"92;PK;Pakistan",
		@"91;IN;India",
		@"90;TR;Turkey",
		@"86;CN;China",
		@"84;VN;Vietnam",
		@"82;KR;South Korea",
		@"81;JP;Japan",
		@"66;TH;Thailand",
		@"65;SG;Singapore",
		@"64;NZ;New Zealand",
		@"63;PH;Philippines",
		@"62;ID;Indonesia",
		@"61;AU;Australia",
		@"60;MY;Malaysia",
		@"58;VE;Venezuela",
		@"57;CO;Colombia",
		@"56;CL;Chile",
		@"55;BR;Brazil",
		@"54;AR;Argentina",
		@"53;CU;Cuba",
		@"52;MX;Mexico",
		@"51;PE;Peru",
		@"49;DE;Germany",
		@"48;PL;Poland",
		@"47;NO;Norway",
		@"46;SE;Sweden",
		@"45;DK;Denmark",
		@"44;GB;United Kingdom",
		@"43;AT;Austria",
		@"41;CH;Switzerland",
		@"40;RO;Romania",
		@"39;IT;Italy",
		@"36;HU;Hungary",
		@"34;ES;Spain",
		@"33;FR;France",
		@"32;BE;Belgium",
		@"31;NL;Netherlands",
		@"30;GR;Greece",
		@"27;ZA;South Africa",
		@"20;EG;Egypt",
		@"7;RU;Russia",
		@"7;KZ;Kazakhstan",
		@"1;US;USA",
		@"1;CA;Canada",
		];
		NSMutableArray *countries = [NSMutableArray arrayWithCapacity:lines.count];
		for (NSString *line in lines){
			NSArray *parts = [line componentsSeparatedByString:@";"];
			if (parts.count < 3)
				continue;
			NSString *dial = parts[0];
			NSString *iso = [parts[1] uppercaseString];
			NSString *name = parts[2];
			if (!dial.length || !name.length)
				continue;
			[countries addObject:@[name, TGFlagEmojiForCountryCode(iso), [@"+" stringByAppendingString:dial], iso]];
		}
		list = countries;
	});
	return list;
}

@interface TGCountryPickerRowCell : UITableViewCell

@property (nonatomic, strong) UILabel *countryTitleLabel;
@property (nonatomic, strong) UILabel *countryCodeLabel;
@property (nonatomic, assign) BOOL useIndex;

@end

@implementation TGCountryPickerRowCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
	self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
	if (!self)
		return nil;

	BOOL flat = [[TGTheme shared] isFlat];
	UIColor *background = flat ? [UIColor clearColor] : [UIColor whiteColor];
	UIColor *titleColour = flat ? [[TGTheme shared] primaryTextColour] : [UIColor blackColor];
	UIColor *codeColour = flat ? [[TGTheme shared] accentColour] : TGCountryPickerColour(0x516691);

	_countryTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_countryTitleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	_countryTitleLabel.font = [UIFont boldSystemFontOfSize:17];
	_countryTitleLabel.backgroundColor = background;
	_countryTitleLabel.textColor = titleColour;
	_countryTitleLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:_countryTitleLabel];

	_countryCodeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	_countryCodeLabel.textAlignment = NSTextAlignmentRight;
	_countryCodeLabel.contentMode = UIViewContentModeRight;
	_countryCodeLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
	_countryCodeLabel.font = [UIFont boldSystemFontOfSize:17];
	_countryCodeLabel.backgroundColor = background;
	_countryCodeLabel.textColor = codeColour;
	_countryCodeLabel.highlightedTextColor = [UIColor whiteColor];
	[self.contentView addSubview:_countryCodeLabel];

	return self;
}

- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat contentWidth = self.contentView.frame.size.width;
	CGFloat cellWidth = self.frame.size.width;
	_countryTitleLabel.frame = _useIndex ? CGRectMake(9, 12, contentWidth - 54 - 5, 20)
										 : CGRectMake(9, 12, contentWidth - 54 - 15, 20);
	_countryCodeLabel.frame = _useIndex ? CGRectMake(cellWidth - 49 - 32, 12, 50, 20)
										: CGRectMake(cellWidth - 50 - 9, 12, 50, 20);
}

@end

@interface TGCountryPickerViewController () <UISearchBarDelegate> {
	BOOL _searchFieldStyled;
	BOOL _searchActive;
}
@property (nonatomic, strong) NSArray *countries;
@property (nonatomic, strong) NSArray *filtered;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) UISearchBar *searchBar;
@end

@implementation TGCountryPickerViewController

- (id)init {
	self = [super initWithStyle:UITableViewStylePlain];
	if (!self)
		return nil;
	self.title = @"Country";
	return self;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
	return NO;
}

- (NSUInteger)supportedInterfaceOrientations {
	return UIInterfaceOrientationMaskPortrait;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	BOOL flat = [[TGTheme shared] isFlat];
	self.tableView.backgroundColor = flat ? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];
	self.tableView.rowHeight = 44;
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	if (!flat){
		[self installCancelButton];

		UIView *overscroll = [[UIView alloc] initWithFrame:
				CGRectMake(0, -500, self.tableView.bounds.size.width, 500)];
		overscroll.backgroundColor = TGCountryPickerColour(0xe4e9f0);
		overscroll.opaque = YES;
		overscroll.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.tableView addSubview:overscroll];
	}

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
	self.searchBar.delegate = self;
	if (!flat && [self.searchBar respondsToSelector:@selector(setBackgroundImage:)]){
		UIImage *background = [UIImage imageNamed:@"SearchBarBackground.png"];
		if (background)
			[self.searchBar setBackgroundImage:background];
	}
	self.tableView.tableHeaderView = self.searchBar;
	if (!flat)
		[self hideStripe:self.searchBar];

	self.countries = TGPhoneCountries();
	[self rebuildSections];

	__weak typeof(self) weakSelf = self;
	[[TGClient shared] request:@{@"@type" : @"getCountries"} completion:^(NSDictionary *result){
		if (![result isKindOfClass:NSDictionary.class])
			return;
		if (![result[@"@type"] isEqualToString:@"countries"])
			return;
		NSArray *raw = result[@"countries"];
		if (![raw isKindOfClass:NSArray.class])
			return;
		NSMutableArray *countries = [NSMutableArray array];
		for (NSDictionary *c in raw){
			if (![c isKindOfClass:NSDictionary.class])
				continue;
			if ([c[@"is_hidden"] boolValue])
				continue;
			NSString *iso = [c[@"country_code"] isKindOfClass:NSString.class] ? c[@"country_code"] : @"";
			if ([iso isEqualToString:@"FT"])
				continue;
			NSString *name = c[@"name"];
			if (![name isKindOfClass:NSString.class] || !name.length){
				name = iso.length ? [[NSLocale currentLocale] displayNameForKey:NSLocaleCountryCode value:iso] : nil;
				if (!name.length)
					continue;
			}
			NSString *flag = c[@"flag_emoji"];
			if (![flag isKindOfClass:NSString.class] || !flag.length)
				flag = TGFlagEmojiForCountryCode(iso);
			NSArray *codes = c[@"calling_codes"];
			if (![codes isKindOfClass:NSArray.class] || !codes.count)
				continue;
			for (id code in codes){
				if (![code isKindOfClass:NSString.class] || ![(NSString *)code length])
					continue;
				[countries addObject:@[name, flag, [@"+" stringByAppendingString:code], iso]];
			}
		}
		if (countries.count < TGPhoneCountries().count)
			return;
		dispatch_async(dispatch_get_main_queue(), ^{
			TGCountryPickerViewController *me = weakSelf;
			if (!me)
				return;
			me.countries = countries;
			[me rebuildSections];
			if (me.searchBar.text.length)
				[me applyQuery:me.searchBar.text];
			[me.tableView reloadData];
		});
	}];
}

- (void)installCancelButton {
	UIImage *plate = [[UIImage imageNamed:@"HeaderButton_Login.png"] stretchableImageWithLeftCapWidth:11 topCapHeight:0];
	UIImage *pressed = [[UIImage imageNamed:@"HeaderButton_Login_Pressed.png"] stretchableImageWithLeftCapWidth:11 topCapHeight:0];
	if (!plate)
		return;

	UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	[button setBackgroundImage:plate forState:UIControlStateNormal];
	if (pressed)
		[button setBackgroundImage:pressed forState:UIControlStateHighlighted];
	[button setTitle:@"Cancel" forState:UIControlStateNormal];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
	button.titleLabel.shadowOffset = CGSizeMake(0, -1);
	[button setTitleShadowColor:[UIColor colorWithRed:0x07 / 255.0f green:0x08 / 255.0f blue:0x0a / 255.0f alpha:0.35f]
					   forState:UIControlStateNormal];

	CGSize titleSize = [[button titleForState:UIControlStateNormal] sizeWithFont:button.titleLabel.font];
	CGFloat width = MAX(59.0f, ceilf(titleSize.width) + 14.0f);
	button.frame = CGRectMake(0, 0, width, plate.size.height);

	[button addTarget:self action:@selector(cancelButtonPressed) forControlEvents:UIControlEventTouchUpInside];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (void)cancelButtonPressed {
	[self.searchBar resignFirstResponder];
	if (self.navigationController && self.navigationController.viewControllers.count > 1)
		[self.navigationController popViewControllerAnimated:YES];
	else
		[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!_searchFieldStyled && ![[TGTheme shared] isFlat]){
		_searchFieldStyled = YES;
		[self.searchBar layoutIfNeeded];
		[self styleSearchInputField:self.searchBar];
		[self hideStripe:self.searchBar];
	}
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	if (_searchActive){
		_searchActive = NO;
		[self.navigationController setNavigationBarHidden:NO animated:animated];
	}
}

- (void)hideStripe:(UIView *)view {
	if ([view isKindOfClass:[UIImageView class]] && view.frame.size.height == 1)
		view.hidden = YES;
	for (UIView *child in view.subviews)
		[self hideStripe:child];
}

- (void)styleSearchInputField:(UIView *)view {
	if ([view isKindOfClass:[UITextField class]]){
		UITextField *field = (UITextField *)view;
		BOOL retina = [[UIScreen mainScreen] respondsToSelector:@selector(scale)] &&
				[[UIScreen mainScreen] scale] > 1.5f;
		field.borderStyle = UITextBorderStyleNone;
		field.background = nil;
		field.clipsToBounds = NO;

		SEL clearButtonSelector = NSSelectorFromString([[NSString alloc]
				initWithFormat:@"%sBu%s", "clear", "tton"]);
		if ([field respondsToSelector:clearButtonSelector]){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
			UIButton *clearButton = [field performSelector:clearButtonSelector];
#pragma clang diagnostic pop
			if ([clearButton isKindOfClass:[UIButton class]]){
				UIImage *clear = [UIImage imageNamed:@"ClearInput.png"];
				UIImage *clearPressed = [UIImage imageNamed:@"ClearInput_Pressed.png"];
				if (clear)
					[clearButton setImage:clear forState:UIControlStateNormal];
				if (clearPressed)
					[clearButton setImage:clearPressed forState:UIControlStateHighlighted];
				if (retina)
					clearButton.frame = CGRectOffset(clearButton.frame, 0, 0.5f);
			}
		}

		UIImage *inputImage = [UIImage imageNamed:@"SearchInputField.png"];
		if (inputImage){
			inputImage = [inputImage stretchableImageWithLeftCapWidth:
					(int)(inputImage.size.width / 2) topCapHeight:0];
			UIImageView *inputImageView = [[UIImageView alloc] initWithFrame:
					CGRectMake(0, retina ? 0.5f : 0.0f, field.frame.size.width, inputImage.size.height)];
			inputImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			inputImageView.image = inputImage;
			[field insertSubview:inputImageView atIndex:0];
		}

		UIImage *icon = [UIImage imageNamed:@"SearchBarIcon.png"];
		UIView *leftView = [field leftView];
		if (icon && [leftView isKindOfClass:[UIImageView class]]){
			[(UIImageView *)leftView setImage:icon];
			[leftView sizeToFit];
		}
		return;
	}

	for (UIView *child in view.subviews)
		[self styleSearchInputField:child];
}

- (UIView *)sectionIndexView {
	UIView *view = nil;
	@try {
		id value = [self.tableView valueForKey:@"_index"];
		if ([value isKindOfClass:[UIView class]])
			view = value;
	}
	@catch (NSException *exception) {
		view = nil;
	}
	return view;
}

- (void)setSearchActive:(BOOL)active animated:(BOOL)animated {
	if (_searchActive == active)
		return;
	_searchActive = active;

	UIView *indexView = [self sectionIndexView];
	if (indexView){
		[UIView animateWithDuration:0.15f animations:^{
			indexView.alpha = active ? 0.0f : 1.0f;
		}];
	}

	[self.navigationController setNavigationBarHidden:active animated:animated];
}

- (void)rebuildSections {
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *sections = [NSMutableArray array];
	NSMutableDictionary *index = [NSMutableDictionary dictionary];
	for (NSArray *c in self.countries){
		NSString *name = c[0];
		if (!name.length)
			continue;
		NSString *title = [[name substringToIndex:1] uppercaseString];
		NSNumber *slot = index[title];
		if (!slot){
			slot = @(titles.count);
			index[title] = slot;
			[titles addObject:title];
			[sections addObject:[NSMutableArray array]];
		}
		[sections[slot.unsignedIntegerValue] addObject:c];
	}

	NSArray *order = [titles sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b){
		return TGCountryNameCompare(a, b);
	}];
	NSMutableArray *sortedSections = [NSMutableArray arrayWithCapacity:order.count];
	for (NSString *title in order){
		NSMutableArray *items = sections[[index[title] unsignedIntegerValue]];
		[items sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b){
			NSComparisonResult byName = TGCountryNameCompare(a[0], b[0]);
			return byName != NSOrderedSame ? byName : [a[2] compare:b[2]];
		}];
		[sortedSections addObject:items];
	}

	self.sectionTitles = order;
	self.sections = sortedSections;
}

- (NSArray *)rowsForSection:(NSInteger)section {
	if (self.filtered)
		return self.filtered;
	if (section < 0 || section >= (NSInteger)self.sections.count)
		return @[];
	return self.sections[section];
}

- (NSArray *)rowAtIndexPath:(NSIndexPath *)indexPath {
	NSArray *rows = [self rowsForSection:indexPath.section];
	if (indexPath.row < 0 || indexPath.row >= (NSInteger)rows.count)
		return nil;
	NSArray *row = rows[indexPath.row];
	return row.count >= 3 ? row : nil;
}

- (void)applyQuery:(NSString *)text {
	NSString *string = [text lowercaseString];
	if (!string.length){
		self.filtered = nil;
		return;
	}

	NSMutableString *transliterated = [[NSMutableString alloc] initWithString:string];
	CFStringTransform((__bridge CFMutableStringRef)transliterated, NULL, kCFStringTransformToLatin, false);
	CFStringTransform((__bridge CFMutableStringRef)transliterated, NULL, kCFStringTransformStripCombiningMarks, false);

	NSMutableArray *matches = [NSMutableArray array];
	for (NSArray *section in self.sections){
		for (NSArray *item in section){
			NSString *name = [item[0] lowercaseString];
			if ([name hasPrefix:string] || [name hasPrefix:transliterated]){
				[matches addObject:item];
				continue;
			}
			for (NSString *word in [name componentsSeparatedByString:@" "]){
				if ([word hasPrefix:string] || [word hasPrefix:transliterated]){
					[matches addObject:item];
					break;
				}
			}
		}
	}

	if (!matches.count){
		for (NSArray *section in self.sections){
			for (NSArray *item in section){
				NSString *iso = item.count > 3 ? [item[3] lowercaseString] : @"";
				NSString *dial = item.count > 2 ? item[2] : @"";
				if (dial.length > 1)
					dial = [dial substringFromIndex:1];
				if ((iso.length && [iso hasPrefix:string]) || (dial.length && [dial hasPrefix:string]))
					[matches addObject:item];
			}
		}
	}

	self.filtered = matches;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	[self applyQuery:text];
	[self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:YES animated:YES];
	[self setSearchActive:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:NO animated:YES];
	[self setSearchActive:NO animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.filtered = nil;
	[searchBar resignFirstResponder];
	[self.tableView reloadData];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
	[self.searchBar resignFirstResponder];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return self.filtered ? 1 : (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return [self rowsForSection:section].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return self.filtered ? 0 : 25;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
	if (self.filtered || section < 0 || section >= (NSInteger)self.sectionTitles.count)
		return nil;

	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, 25)];
	container.clipsToBounds = NO;
	container.opaque = NO;

	UIImage *background = [UIImage imageNamed:section == 0 ? @"CategoryDividerFirst.png" : @"CategoryDivider.png"];
	if (background && ![[TGTheme shared] isFlat]){
		UIImageView *backgroundView = [[UIImageView alloc] initWithFrame:
				CGRectMake(0, -1, tableView.bounds.size.width, 26)];
		backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		backgroundView.image = background;
		[container addSubview:backgroundView];
	} else {
		container.backgroundColor = [[TGTheme shared] listBackgroundColour];
	}

	UILabel *label = [[UILabel alloc] init];
	label.font = [UIFont boldSystemFontOfSize:15];
	label.backgroundColor = [UIColor clearColor];
	label.numberOfLines = 1;
	if ([[TGTheme shared] isFlat]){
		label.textColor = [[TGTheme shared] sectionHeaderColour];
	} else {
		label.textColor = [UIColor whiteColor];
		label.shadowColor = TGCountryPickerColour(0x88929c);
		label.shadowOffset = CGSizeMake(0, -1);
	}
	label.text = self.sectionTitles[section];
	[label sizeToFit];
	label.frame = CGRectOffset(label.frame, 10, 1);
	[container addSubview:label];

	return container;
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView {
	if (self.filtered)
		return nil;
	NSMutableArray *titles = [NSMutableArray arrayWithObject:UITableViewIndexSearch];
	[titles addObjectsFromArray:self.sectionTitles];
	return titles;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index {
	if (index == 0){
		[tableView scrollRectToVisible:tableView.tableHeaderView.frame animated:NO];
		return -1;
	}
	return index - 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *reuse = @"TGCountryCell";
	TGCountryPickerRowCell *cell = (TGCountryPickerRowCell *)[tableView dequeueReusableCellWithIdentifier:reuse];
	if (!cell)
		cell = [[TGCountryPickerRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuse];
	NSArray *c = [self rowAtIndexPath:indexPath];
	cell.useIndex = !self.filtered;
	cell.countryTitleLabel.text = c ? c[0] : @"";
	cell.countryCodeLabel.text = c ? c[2] : @"";
	cell.accessibilityLabel = cell.countryTitleLabel.text;
	cell.accessibilityValue = cell.countryCodeLabel.text;
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.selectionStyle = UITableViewCellSelectionStyleBlue;
	if ([[TGTheme shared] isFlat])
		[[TGTheme shared] styleCell:cell];
	[cell setNeedsLayout];
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSArray *c = [self rowAtIndexPath:indexPath];
	if (!c)
		return;
	[self.searchBar resignFirstResponder];
	if (self.onPick)
		self.onPick(c[0], c[1], c[2]);
	if (self.navigationController)
		[self.navigationController popViewControllerAnimated:YES];
	else
		[self dismissViewControllerAnimated:YES completion:nil];
}

@end
