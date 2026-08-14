#include "TGDateUtils.h"
#include <time.h>

static bool value_dateHas12hFormat = false;
static __strong NSString *value_monthNamesGenShort[] = {
	@"Jan", @"Feb", @"Mar", @"Apr", @"May", @"Jun",
	@"Jul", @"Aug", @"Sep", @"Oct", @"Nov", @"Dec"
};
static __strong NSString *value_weekdayNamesShort[] = {
	@"Mon", @"Tue", @"Wed", @"Thu", @"Fri", @"Sat", @"Sun"
};

static bool value_dialogTimeMonthNameFirst = false;
static NSString *value_dialogTimeFormat = @"%@ %d";

static NSString *value_today = @"today";
static NSString *value_yesterday = @"yesterday";
static NSString *value_tomorrow = @"tomorrow";
static NSString *value_at = @"at";

static char value_date_separator = '.';
static bool value_monthFirst = false;

static bool TGDateUtilsInitialized = false;
static void initializeTGDateUtils() {
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setLocale:[NSLocale currentLocale]];
	[dateFormatter setDateStyle:NSDateFormatterNoStyle];
	[dateFormatter setTimeStyle:NSDateFormatterMediumStyle];
	[dateFormatter setTimeZone:[NSTimeZone localTimeZone]];
	NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
	NSRange amRange = [dateString rangeOfString:[dateFormatter AMSymbol]];
	NSRange pmRange = [dateString rangeOfString:[dateFormatter PMSymbol]];
	value_dateHas12hFormat = !(amRange.location == NSNotFound && pmRange.location == NSNotFound);

	dateString = [NSDateFormatter dateFormatFromTemplate:@"MdY" options:0 locale:[NSLocale currentLocale]];
	if ([dateString rangeOfString:@"."].location != NSNotFound)
		value_date_separator = '.';
	else if ([dateString rangeOfString:@"/"].location != NSNotFound)
		value_date_separator = '/';
	else if ([dateString rangeOfString:@"-"].location != NSNotFound)
		value_date_separator = '-';

	if ([dateString rangeOfString:[NSString stringWithFormat:@"M%cd", value_date_separator]].location != NSNotFound)
		value_monthFirst = true;

	TGDateUtilsInitialized = true;
}

static inline bool dateHas12hFormat() {
	if (!TGDateUtilsInitialized)
		initializeTGDateUtils();
	return value_dateHas12hFormat;
}

bool TGUse12hDateFormat() {
	if (!TGDateUtilsInitialized)
		initializeTGDateUtils();
	return value_dateHas12hFormat;
}

static inline NSString *weekdayNameShort(int number) {
	if (!TGDateUtilsInitialized)
		initializeTGDateUtils();
	if (number < 0) number = 0;
	if (number > 6) number = 6;
	number = (number == 0) ? 6 : number - 1;
	return value_weekdayNamesShort[number];
}

static inline NSString *monthNameGenShort(int number) {
	if (!TGDateUtilsInitialized)
		initializeTGDateUtils();
	if (number < 0) number = 0;
	if (number > 11) number = 11;
	return value_monthNamesGenShort[number];
}

static inline bool dialogTimeMonthNameFirst() {
	if (!TGDateUtilsInitialized)
		initializeTGDateUtils();
	return value_dialogTimeMonthNameFirst;
}

static inline NSString *dialogTimeFormat() {
	if (!TGDateUtilsInitialized)
		initializeTGDateUtils();
	return value_dialogTimeFormat;
}

static NSString *shortAbsoluteDate(struct tm timeinfo) {
	if (value_monthFirst)
		return [[NSString alloc] initWithFormat:@"%d%c%d%c%02d", timeinfo.tm_mon + 1, value_date_separator, timeinfo.tm_mday, value_date_separator, timeinfo.tm_year - 100];
	return [[NSString alloc] initWithFormat:@"%d%c%02d%c%02d", timeinfo.tm_mday, value_date_separator, timeinfo.tm_mon + 1, value_date_separator, timeinfo.tm_year - 100];
}

@implementation TGDateUtils

+ (NSString *)stringForShortTime:(int)time {
	time_t t = time;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);

	if (dateHas12hFormat()){
		if (timeinfo.tm_hour < 12)
			return [[NSString alloc] initWithFormat:@"%d:%02d AM", timeinfo.tm_hour == 0 ? 12 : timeinfo.tm_hour, timeinfo.tm_min];
		return [[NSString alloc] initWithFormat:@"%d:%02d PM", (timeinfo.tm_hour - 12 == 0) ? 12 : (timeinfo.tm_hour - 12), timeinfo.tm_min];
	}
	return [[NSString alloc] initWithFormat:@"%02d:%02d", timeinfo.tm_hour, timeinfo.tm_min];
}

+ (NSString *)stringForDialogTime:(int)time {
	time_t t = time;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);

	if (dialogTimeMonthNameFirst())
		return [[NSString alloc] initWithFormat:dialogTimeFormat(), monthNameGenShort(timeinfo.tm_mon), timeinfo.tm_mday];
	return [[NSString alloc] initWithFormat:dialogTimeFormat(), monthNameGenShort(timeinfo.tm_mon), timeinfo.tm_mday];
}

+ (NSString *)stringForDayOfMonth:(int)date dayOfMonth:(int *)dayOfMonth {
	time_t t = date;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);
	if (dayOfMonth != NULL)
		*dayOfMonth = timeinfo.tm_mday;
	if (dialogTimeMonthNameFirst())
		return [[NSString alloc] initWithFormat:@"%@ %d", monthNameGenShort(timeinfo.tm_mon), timeinfo.tm_mday];
	return [[NSString alloc] initWithFormat:@"%d %@", timeinfo.tm_mday, monthNameGenShort(timeinfo.tm_mon)];
}

+ (NSString *)stringForDayOfWeek:(int)date {
	time_t t = date;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);
	return weekdayNameShort(timeinfo.tm_wday);
}

+ (NSString *)stringForMessageListDate:(int)date {
	time_t t = date;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);
	time_t t_now = time(0);
	struct tm timeinfo_now;
	localtime_r(&t_now, &timeinfo_now);

	if (timeinfo.tm_year != timeinfo_now.tm_year)
		return shortAbsoluteDate(timeinfo);

	int dayDiff = timeinfo.tm_yday - timeinfo_now.tm_yday;
	if (dayDiff == 0)
		return [self stringForShortTime:date];
	if (dayDiff >= -6 && dayDiff <= -1)
		return weekdayNameShort(timeinfo.tm_wday);
	return shortAbsoluteDate(timeinfo);
}

+ (NSString *)stringForLastSeen:(int)date {
	time_t t = date;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);
	time_t t_now = time(0);
	struct tm timeinfo_now;
	localtime_r(&t_now, &timeinfo_now);

	if (timeinfo.tm_year != timeinfo_now.tm_year)
		return shortAbsoluteDate(timeinfo);

	int dayDiff = timeinfo.tm_yday - timeinfo_now.tm_yday;
	if (dayDiff == 0 || dayDiff == -1){
		NSString *day = dayDiff == 0 ? value_today : value_yesterday;
		if (dateHas12hFormat()){
			if (timeinfo.tm_hour < 12)
				return [[NSString alloc] initWithFormat:@"%@ %@ %d:%02d AM", day, value_at, timeinfo.tm_hour == 0 ? 12 : timeinfo.tm_hour, timeinfo.tm_min];
			return [[NSString alloc] initWithFormat:@"%@ %@ %d:%02d PM", day, value_at, (timeinfo.tm_hour - 12 == 0) ? 12 : (timeinfo.tm_hour - 12), timeinfo.tm_min];
		}
		return [[NSString alloc] initWithFormat:@"%@ %@ %02d:%02d", day, value_at, timeinfo.tm_hour, timeinfo.tm_min];
	}
	return shortAbsoluteDate(timeinfo);
}

+ (NSString *)stringForLastSeenShort:(int)date {
	return [self stringForLastSeen:date];
}

+ (NSString *)stringForRelativeLastSeen:(int)date {
	time_t t = date;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);
	time_t t_now = time(0);
	struct tm timeinfo_now;
	localtime_r(&t_now, &timeinfo_now);

	if (timeinfo.tm_year != timeinfo_now.tm_year)
		return shortAbsoluteDate(timeinfo);

	int dayDiff = timeinfo.tm_yday - timeinfo_now.tm_yday;
	int minutesDiff = (int)((t_now - date) / 60);
	int hoursDiff = (int)((t_now - date) / (60 * 60));

	if (dayDiff == 0 && hoursDiff <= 23){
		if (minutesDiff < 1)
			return @"just now";
		if (minutesDiff < 60)
			return [[NSString alloc] initWithFormat:@"%d %s ago", minutesDiff, minutesDiff == 1 ? "minute" : "minutes"];
		return [[NSString alloc] initWithFormat:@"%d %s ago", hoursDiff, hoursDiff == 1 ? "hour" : "hours"];
	}
	if (dayDiff == 0 || dayDiff == -1)
		return [self stringForLastSeen:date];
	return shortAbsoluteDate(timeinfo);
}

+ (NSString *)stringForUntil:(int)date {
	time_t t = date;
	struct tm timeinfo;
	localtime_r(&t, &timeinfo);
	time_t t_now = time(0);
	struct tm timeinfo_now;
	localtime_r(&t_now, &timeinfo_now);

	if (timeinfo.tm_year != timeinfo_now.tm_year)
		return shortAbsoluteDate(timeinfo);

	int dayDiff = timeinfo.tm_yday - timeinfo_now.tm_yday;
	if (dayDiff == 0 || dayDiff == 1){
		NSString *day = dayDiff == 0 ? value_today : value_tomorrow;
		if (dateHas12hFormat()){
			if (timeinfo.tm_hour < 12)
				return [[NSString alloc] initWithFormat:@"%@, %d:%02d AM", day, timeinfo.tm_hour == 0 ? 12 : timeinfo.tm_hour, timeinfo.tm_min];
			return [[NSString alloc] initWithFormat:@"%@, %d:%02d PM", day, (timeinfo.tm_hour - 12 == 0) ? 12 : (timeinfo.tm_hour - 12), timeinfo.tm_min];
		}
		return [[NSString alloc] initWithFormat:@"%@, %02d:%02d", day, timeinfo.tm_hour, timeinfo.tm_min];
	}
	return shortAbsoluteDate(timeinfo);
}

@end
