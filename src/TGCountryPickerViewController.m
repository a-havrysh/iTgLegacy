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

static NSArray *TGCountrySearchTokens(NSString *string) {
	if (!string.length)
		return @[];
	NSString *folded = [[string stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
													locale:[NSLocale currentLocale]] lowercaseString];
	folded = [folded stringByReplacingOccurrencesOfString:@"." withString:@""];
	NSMutableCharacterSet *separators = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
	[separators formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
	NSMutableArray *tokens = [NSMutableArray array];
	for (NSString *piece in [folded componentsSeparatedByCharactersInSet:separators]){
		if (piece.length && ![tokens containsObject:piece])
			[tokens addObject:piece];
	}
	return tokens;
}

static BOOL TGCountryMatchesTokens(NSArray *tokens, NSArray *queryTokens) {
	if (!queryTokens.count || !tokens.count)
		return NO;
	for (NSString *queryToken in queryTokens){
		BOOL found = NO;
		for (NSString *token in tokens){
			if ([token hasPrefix:queryToken]){
				found = YES;
				break;
			}
		}
		if (!found)
			return NO;
	}
	return YES;
}

@interface TGCountryPickerViewController () <UISearchBarDelegate> {
	BOOL _searchFieldStyled;
}
@property (nonatomic, strong) NSArray *countries;
@property (nonatomic, strong) NSArray *filtered;
@property (nonatomic, strong) NSArray *sections;
@property (nonatomic, strong) NSArray *sectionTitles;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *emptyLabel;
@end

@implementation TGCountryPickerViewController

- (id)init {
	self = [super initWithStyle:UITableViewStylePlain];
	if (!self)
		return nil;
	self.title = @"Country";
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[[TGTheme shared] styleNavigationBar:self.navigationController.navigationBar];

	BOOL flat = [[TGTheme shared] isFlat];
	self.tableView.backgroundColor = flat ? [[TGTheme shared] listBackgroundColour] : [UIColor whiteColor];
	self.tableView.rowHeight = 44;
	self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

	if (!flat){
		UIView *overscroll = [[UIView alloc] initWithFrame:
				CGRectMake(0, -500, self.tableView.bounds.size.width, 500)];
		overscroll.backgroundColor = TGCountryPickerColour(0xe4e9f0);
		overscroll.opaque = YES;
		overscroll.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[self.tableView addSubview:overscroll];
	}

	self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
	self.searchBar.delegate = self;
	self.searchBar.placeholder = @"Search";
	if (!flat && [self.searchBar respondsToSelector:@selector(setBackgroundImage:)]){
		UIImage *background = [UIImage imageNamed:@"SearchBarBackground.png"];
		if (background)
			[self.searchBar setBackgroundImage:background];
	}
	self.tableView.tableHeaderView = self.searchBar;
	if (!flat)
		[self hideStripe:self.searchBar];

	self.emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
	self.emptyLabel.backgroundColor = [UIColor clearColor];
	self.emptyLabel.textAlignment = NSTextAlignmentCenter;
	self.emptyLabel.font = [UIFont boldSystemFontOfSize:15];
	self.emptyLabel.textColor = flat ? [[TGTheme shared] secondaryTextColour] : TGCountryPickerColour(0x8e8e93);
	self.emptyLabel.text = @"No results";
	self.emptyLabel.hidden = YES;
	[self.view addSubview:self.emptyLabel];

	self.countries = [self fallbackCountries];
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
		if (!countries.count)
			return;
		[countries sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b){
			NSComparisonResult byName = [a[0] localizedCaseInsensitiveCompare:b[0]];
			return byName != NSOrderedSame ? byName : [a[2] compare:b[2]];
		}];
		dispatch_async(dispatch_get_main_queue(), ^{
			TGCountryPickerViewController *me = weakSelf;
			if (!me)
				return;
			me.countries = countries;
			if (me.searchBar.text.length)
				[me applyQuery:me.searchBar.text];
			[me rebuildSections];
			[me.tableView reloadData];
			[me updateEmptyState];
		});
	}];
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

- (void)hideStripe:(UIView *)view {
	if ([view isKindOfClass:[UIImageView class]] && view.frame.size.height == 1)
		view.hidden = YES;
	for (UIView *child in view.subviews)
		[self hideStripe:child];
}

- (void)styleSearchInputField:(UIView *)view {
	if ([view isKindOfClass:[UITextField class]]){
		UITextField *field = (UITextField *)view;
		field.borderStyle = UITextBorderStyleNone;
		field.background = nil;
		field.clipsToBounds = NO;
		field.font = [UIFont systemFontOfSize:14];

		UIImage *inputImage = [UIImage imageNamed:@"SearchInputField.png"];
		if (inputImage){
			inputImage = [inputImage stretchableImageWithLeftCapWidth:
					(int)(inputImage.size.width / 2) topCapHeight:0];
			UIImageView *inputImageView = [[UIImageView alloc] initWithFrame:
					CGRectMake(0, 0.5f, field.frame.size.width, inputImage.size.height)];
			inputImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
			inputImageView.image = inputImage;
			[field insertSubview:inputImageView atIndex:0];
		}

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
			}
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

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	CGRect bounds = self.view.bounds;
	self.emptyLabel.frame = CGRectMake(0, bounds.origin.y + floorf((bounds.size.height - 20) / 2.0f),
									   bounds.size.width, 20);
}

- (void)updateEmptyState {
	self.emptyLabel.hidden = !(self.filtered && self.filtered.count == 0);
	if (!self.emptyLabel.hidden)
		[self.view setNeedsLayout];
}

- (NSArray *)fallbackCountries {
	NSArray *countries = @[
		@[@"United States", @"🇺🇸", @"+1", @"US"],
		@[@"United Kingdom", @"🇬🇧", @"+44", @"GB"],
		@[@"Ukraine", @"🇺🇦", @"+380", @"UA"],
		@[@"Poland", @"🇵🇱", @"+48", @"PL"],
		@[@"Germany", @"🇩🇪", @"+49", @"DE"],
		@[@"France", @"🇫🇷", @"+33", @"FR"],
		@[@"Italy", @"🇮🇹", @"+39", @"IT"],
		@[@"Spain", @"🇪🇸", @"+34", @"ES"],
		@[@"Netherlands", @"🇳🇱", @"+31", @"NL"],
		@[@"Russia", @"🇷🇺", @"+7", @"RU"],
		@[@"Kazakhstan", @"🇰🇿", @"+7", @"KZ"],
		@[@"Belarus", @"🇧🇾", @"+375", @"BY"],
		@[@"Turkey", @"🇹🇷", @"+90", @"TR"],
		@[@"Israel", @"🇮🇱", @"+972", @"IL"],
		@[@"United Arab Emirates", @"🇦🇪", @"+971", @"AE"],
		@[@"India", @"🇮🇳", @"+91", @"IN"],
		@[@"China", @"🇨🇳", @"+86", @"CN"],
		@[@"Japan", @"🇯🇵", @"+81", @"JP"],
		@[@"Brazil", @"🇧🇷", @"+55", @"BR"],
		@[@"Canada", @"🇨🇦", @"+1", @"CA"],
		@[@"Mexico", @"🇲🇽", @"+52", @"MX"],
		@[@"Australia", @"🇦🇺", @"+61", @"AU"],
	];
	return [countries sortedArrayUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b){
		return [a[0] localizedCaseInsensitiveCompare:b[0]];
	}];
}

- (void)rebuildSections {
	NSMutableArray *titles = [NSMutableArray array];
	NSMutableArray *sections = [NSMutableArray array];
	for (NSArray *c in self.countries){
		NSString *name = c[0];
		if (!name.length)
			continue;
		NSString *title = [[name substringToIndex:1] uppercaseString];
		if (!titles.count || ![titles.lastObject isEqualToString:title]){
			[titles addObject:title];
			[sections addObject:[NSMutableArray array]];
		}
		[sections.lastObject addObject:c];
	}
	self.sectionTitles = titles;
	self.sections = sections;
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
	NSString *trimmed = [text stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!trimmed.length){
		self.filtered = nil;
		return;
	}
	NSArray *queryTokens = TGCountrySearchTokens(trimmed);
	if (!queryTokens.count){
		self.filtered = nil;
		return;
	}
	NSMutableArray *matches = [NSMutableArray array];
	for (NSArray *c in self.countries){
		NSString *name = c.count > 0 ? c[0] : @"";
		NSString *dial = c.count > 2 ? c[2] : @"";
		NSString *iso = c.count > 3 ? c[3] : @"";
		NSMutableArray *tokens = [NSMutableArray arrayWithArray:TGCountrySearchTokens(name)];
		NSMutableString *abbreviation = [NSMutableString string];
		for (NSString *word in [name componentsSeparatedByString:@" "]){
			if (word.length)
				[abbreviation appendString:[word substringToIndex:1]];
		}
		if (abbreviation.length)
			[tokens addObject:[abbreviation lowercaseString]];
		if (iso.length)
			[tokens addObject:[iso lowercaseString]];
		if (dial.length > 1)
			[tokens addObject:[dial substringFromIndex:1]];
		if (TGCountryMatchesTokens(tokens, queryTokens))
			[matches addObject:c];
	}
	self.filtered = matches;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)text {
	[self applyQuery:text];
	[self.tableView reloadData];
	[self updateEmptyState];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
	[searchBar resignFirstResponder];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:YES animated:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
	[searchBar setShowsCancelButton:NO animated:YES];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
	searchBar.text = @"";
	self.filtered = nil;
	[searchBar resignFirstResponder];
	[self.tableView reloadData];
	[self updateEmptyState];
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
