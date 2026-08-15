#import "TGClient+Private.h"
#import "TGClient+Account.h"

static BOOL TGAccountIsError(NSDictionary *result) {
	if (![result isKindOfClass:[NSDictionary class]])
		return YES;
	id type = result[@"@type"];
	if (![type isKindOfClass:[NSString class]])
		return YES;
	return [type isEqualToString:@"error"];
}

static NSArray *TGAccountArray(id value) {
	if (![value isKindOfClass:[NSArray class]])
		return [NSArray array];
	return value;
}

static NSDictionary *TGAccountDict(id value) {
	if (![value isKindOfClass:[NSDictionary class]])
		return nil;
	return value;
}

static NSString *TGAccountString(id value) {
	if (![value isKindOfClass:[NSString class]])
		return @"";
	return value;
}

static NSNumber *TGAccountNumber(id value) {
	if (![value isKindOfClass:[NSNumber class]])
		return @0;
	return value;
}

static NSNumber *TGAccountBool(id value) {
	if (![value isKindOfClass:[NSNumber class]])
		return @NO;
	return [value boolValue] ? @YES : @NO;
}

static NSDictionary *TGAccountPhoneSettings(BOOL isCurrentNumber) {
	return @{
		@"@type"                   : @"phoneNumberAuthenticationSettings",
		@"allow_flash_call"        : @NO,
		@"allow_missed_call"       : @NO,
		@"is_current_phone_number" : isCurrentNumber ? @YES : @NO,
		@"has_unknown_phone_number": @NO,
		@"allow_sms_retriever_api" : @NO,
		@"authentication_tokens"   : [NSArray array],
	};
}

static NSString *TGAccountCodeDescription(NSDictionary *type, NSString *phone) {
	NSString *name = TGAccountString(type[@"@type"]);
	if ([name isEqualToString:@"authenticationCodeTypeTelegramMessage"])
		return @"We sent the code to your Telegram app on another device.";
	if ([name isEqualToString:@"authenticationCodeTypeSms"] ||
	    [name isEqualToString:@"authenticationCodeTypeSmsWord"] ||
	    [name isEqualToString:@"authenticationCodeTypeSmsPhrase"])
		return [NSString stringWithFormat:@"We sent an SMS to %@.", phone.length ? phone : @"your phone"];
	if ([name isEqualToString:@"authenticationCodeTypeCall"])
		return @"We are calling you to dictate the code.";
	if ([name isEqualToString:@"authenticationCodeTypeMissedCall"])
		return @"We are calling your phone. Do not answer - the code is the last digits of the calling number.";
	if ([name isEqualToString:@"authenticationCodeTypeFlashCall"])
		return @"We are calling your phone. Do not answer.";
	if ([name isEqualToString:@"authenticationCodeTypeFragment"])
		return @"The code was sent to your Fragment anonymous number.";
	if (name.length)
		return @"Enter the code you received.";
	return @"";
}

static NSString *TGAccountNextTitle(NSDictionary *type) {
	NSString *name = TGAccountString(type[@"@type"]);
	if ([name isEqualToString:@"authenticationCodeTypeCall"] ||
	    [name isEqualToString:@"authenticationCodeTypeMissedCall"] ||
	    [name isEqualToString:@"authenticationCodeTypeFlashCall"])
		return @"Call me";
	if ([name isEqualToString:@"authenticationCodeTypeSms"] ||
	    [name isEqualToString:@"authenticationCodeTypeSmsWord"] ||
	    [name isEqualToString:@"authenticationCodeTypeSmsPhrase"])
		return @"Send code via SMS";
	if ([name isEqualToString:@"authenticationCodeTypeTelegramMessage"])
		return @"Send code via Telegram";
	if (name.length)
		return @"Send code again";
	return @"";
}

static NSInteger TGAccountCodeLength(NSDictionary *type) {
	NSDictionary *safe = TGAccountDict(type);
	if (!safe)
		return 0;
	return [TGAccountNumber(safe[@"length"]) integerValue];
}

static NSDictionary *TGAccountCodeInfoDict(NSDictionary *codeInfo) {
	NSDictionary *info = TGAccountDict(codeInfo);
	if (!info)
		return nil;
	NSString *phone = TGAccountString(info[@"phone_number"]);
	NSDictionary *type = TGAccountDict(info[@"type"]);
	NSDictionary *next = TGAccountDict(info[@"next_type"]);
	return @{
		@"phone"           : phone,
		@"type"            : TGAccountString(type[@"@type"]),
		@"description"     : TGAccountCodeDescription(type, phone),
		@"length"          : @(TGAccountCodeLength(type)),
		@"timeout"         : TGAccountNumber(info[@"timeout"]),
		@"nextType"        : TGAccountString(next[@"@type"]),
		@"nextDescription" : TGAccountNextTitle(next),
	};
}

static NSDictionary *TGAccountEmailCodeInfo(NSDictionary *codeInfo) {
	NSDictionary *info = TGAccountDict(codeInfo);
	if (!info)
		return nil;
	return @{
		@"pattern"    : TGAccountString(info[@"email_address_pattern"]),
		@"codeLength" : TGAccountNumber(info[@"length"]),
	};
}

static NSDictionary *TGAccountSessionDict(NSDictionary *session) {
	NSDictionary *safe = TGAccountDict(session);
	if (!safe)
		return nil;
	return @{
		@"id"          : TGAccountNumber(safe[@"id"]),
		@"appName"     : TGAccountString(safe[@"application_name"]),
		@"deviceModel" : TGAccountString(safe[@"device_model"]),
		@"platform"    : [NSString stringWithFormat:@"%@ %@",
		                  TGAccountString(safe[@"platform"]),
		                  TGAccountString(safe[@"system_version"])],
		@"ip"          : TGAccountString(safe[@"ip_address"]),
		@"location"    : TGAccountString(safe[@"location"]),
	};
}

@interface TGClient (AccountInternal)
- (void)authorizationStateOfType:(NSString *)type
                      completion:(void (^)(NSDictionary *state))completion;
- (void)pollQrCodeLinkWithAttemptsLeft:(NSInteger)attemptsLeft
                            completion:(void (^)(NSString *link))completion;
@end

@implementation TGClient (Account)

#pragma mark - countries and phone numbers

- (void)countriesWithCompletion:(void (^)(NSArray *))completion {
	[self request:@{@"@type" : @"getCountries"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion([NSArray array]);
			return;
		}
		NSMutableArray *out = [NSMutableArray array];
		for (id entry in TGAccountArray(result[@"countries"])){
			NSDictionary *country = TGAccountDict(entry);
			if (!country || [TGAccountBool(country[@"is_hidden"]) boolValue])
				continue;
			NSMutableArray *codes = [NSMutableArray array];
			for (id code in TGAccountArray(country[@"calling_codes"])){
				if ([code isKindOfClass:[NSString class]])
					[codes addObject:code];
			}
			[out addObject:@{
				@"code"         : TGAccountString(country[@"country_code"]),
				@"name"         : TGAccountString(country[@"name"]),
				@"englishName"  : TGAccountString(country[@"english_name"]),
				@"flag"         : TGAccountString(country[@"flag_emoji"]),
				@"callingCodes" : codes,
			}];
		}
		completion(out);
	}];
}

- (void)guessedCountryCodeWithCompletion:(void (^)(NSString *))completion {
	[self request:@{@"@type" : @"getCountryCode"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		NSString *code = TGAccountString(result[@"text"]);
		completion(code.length ? code : nil);
	}];
}

- (void)phoneNumberInfo:(NSString *)phoneNumberPrefix
             completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"               : @"getPhoneNumberInfo",
		@"phone_number_prefix" : phoneNumberPrefix ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *country = TGAccountDict(result[@"country"]);
		if (!country){
			completion(nil);
			return;
		}
		completion(@{
			@"countryCode" : TGAccountString(country[@"country_code"]),
			@"countryName" : TGAccountString(country[@"name"]),
			@"callingCode" : TGAccountString(result[@"country_calling_code"]),
			@"formatted"   : TGAccountString(result[@"formatted_phone_number"]),
		});
	}];
}

- (void)preferredLanguageForCountry:(NSString *)countryCode
                         completion:(void (^)(NSString *))completion {
	[self request:@{
		@"@type"        : @"getPreferredCountryLanguage",
		@"country_code" : countryCode ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		NSString *language = TGAccountString(result[@"text"]);
		completion(language.length ? language : nil);
	}];
}

#pragma mark - login: phone number and code

- (void)startLoginWithPhoneNumber:(NSString *)phoneNumber
                  isCurrentNumber:(BOOL)isCurrentNumber
                       completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"        : @"setAuthenticationPhoneNumber",
		@"phone_number" : phoneNumber ?: @"",
		@"settings"     : TGAccountPhoneSettings(isCurrentNumber),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)authorizationStateOfType:(NSString *)type
                      completion:(void (^)(NSDictionary *state))completion {
	[self request:@{@"@type" : @"getAuthorizationState"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		if (type.length && ![TGAccountString(result[@"@type"]) isEqualToString:type]){
			completion(nil);
			return;
		}
		completion(result);
	}];
}

- (void)authenticationCodeInfoWithCompletion:(void (^)(NSDictionary *))completion {
	[self authorizationStateOfType:@"authorizationStateWaitCode"
	                    completion:^(NSDictionary *state){
		if (!completion)
			return;
		completion(TGAccountCodeInfoDict(state[@"code_info"]));
	}];
}

- (void)resendAuthenticationCodeWithFailureMessage:(NSString *)verificationFailedMessage
                                        completion:(void (^)(NSDictionary *))completion {
	NSDictionary *reason = verificationFailedMessage.length
		? [NSDictionary dictionaryWithObjectsAndKeys:
		   @"resendCodeReasonVerificationFailed", @"@type",
		   verificationFailedMessage, @"error_message", nil]
		: [NSDictionary dictionaryWithObject:@"resendCodeReasonUserRequest" forKey:@"@type"];

	__weak TGClient *weakSelf = self;
	[self request:@{@"@type" : @"resendAuthenticationCode", @"reason" : reason}
	   completion:^(NSDictionary *result){
		if (TGAccountIsError(result)){
			if (completion)
				completion(nil);
			return;
		}
		[weakSelf authenticationCodeInfoWithCompletion:completion];
	}];
}

- (void)reportAuthenticationCodeMissing:(NSString *)mobileNetworkCode
                             completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"               : @"reportAuthenticationCodeMissing",
		@"mobile_network_code" : mobileNetworkCode ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - login: registration

- (void)registrationTermsWithCompletion:(void (^)(NSDictionary *))completion {
	[self authorizationStateOfType:@"authorizationStateWaitRegistration"
	                    completion:^(NSDictionary *state){
		if (!completion)
			return;
		NSDictionary *terms = TGAccountDict(state[@"terms_of_service"]);
		if (!terms){
			completion(nil);
			return;
		}
		NSDictionary *text = TGAccountDict(terms[@"text"]);
		completion(@{
			@"text"       : TGAccountString(text[@"text"]),
			@"minUserAge" : TGAccountNumber(terms[@"min_user_age"]),
			@"showPopup"  : TGAccountBool(terms[@"show_popup"]),
		});
	}];
}

- (void)registerWithFirstName:(NSString *)firstName
                     lastName:(NSString *)lastName
                   completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                : @"registerUser",
		@"first_name"           : firstName ?: @"",
		@"last_name"            : lastName ?: @"",
		@"disable_notification" : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)acceptTermsOfService:(NSString *)termsId completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"                : @"acceptTermsOfService",
		@"terms_of_service_id"  : termsId ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - login: QR code

- (void)requestQrCodeLoginWithCompletion:(void (^)(NSString *))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{
		@"@type"          : @"requestQrCodeAuthentication",
		@"other_user_ids" : [NSArray array],
	} completion:^(NSDictionary *result){
		if (TGAccountIsError(result)){
			if (completion)
				completion(nil);
			return;
		}
		[weakSelf pollQrCodeLinkWithAttemptsLeft:10 completion:completion];
	}];
}

- (void)pollQrCodeLinkWithAttemptsLeft:(NSInteger)attemptsLeft
                            completion:(void (^)(NSString *link))completion {
	__weak TGClient *weakSelf = self;
	[self qrCodeLoginLinkWithCompletion:^(NSString *link){
		if (link.length || attemptsLeft <= 0){
			if (completion)
				completion(link);
			return;
		}
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
		               dispatch_get_main_queue(), ^{
			[weakSelf pollQrCodeLinkWithAttemptsLeft:attemptsLeft - 1 completion:completion];
		});
	}];
}

- (void)qrCodeLoginLinkWithCompletion:(void (^)(NSString *))completion {
	[self authorizationStateOfType:@"authorizationStateWaitOtherDeviceConfirmation"
	                    completion:^(NSDictionary *state){
		if (!completion)
			return;
		NSString *link = TGAccountString(state[@"link"]);
		completion(link.length ? link : nil);
	}];
}

- (void)confirmQrCodeLogin:(NSString *)link
                completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type" : @"confirmQrCodeAuthentication",
		@"link"  : link ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		completion(TGAccountSessionDict(result));
	}];
}

#pragma mark - login: email address as second factor

- (void)setAuthenticationEmailAddress:(NSString *)emailAddress
                           completion:(void (^)(NSString *, NSInteger))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{
		@"@type"         : @"setAuthenticationEmailAddress",
		@"email_address" : emailAddress ?: @"",
	} completion:^(NSDictionary *result){
		if (TGAccountIsError(result)){
			if (completion)
				completion(nil, 0);
			return;
		}
		[weakSelf authenticationEmailStateWithCompletion:^(NSDictionary *info){
			if (!completion)
				return;
			NSString *pattern = TGAccountString(info[@"pattern"]);
			completion(pattern.length ? pattern : nil,
			           [TGAccountNumber(info[@"codeLength"]) integerValue]);
		}];
	}];
}

- (void)checkAuthenticationEmailCode:(NSString *)code
                          completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"checkAuthenticationEmailCode",
		@"code"  : @{@"@type" : @"emailAddressAuthenticationCode", @"code" : code ?: @""},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)authenticationEmailStateWithCompletion:(void (^)(NSDictionary *))completion {
	[self authorizationStateOfType:@"authorizationStateWaitEmailCode"
	                    completion:^(NSDictionary *state){
		if (!completion)
			return;
		if (!state){
			completion(nil);
			return;
		}
		NSDictionary *codeInfo = TGAccountEmailCodeInfo(state[@"code_info"]);
		NSDictionary *reset = TGAccountDict(state[@"email_address_reset_state"]);
		NSString *resetType = TGAccountString(reset[@"@type"]);
		NSString *resetState = @"";
		if ([resetType isEqualToString:@"emailAddressResetStateAvailable"])
			resetState = @"available";
		else if ([resetType isEqualToString:@"emailAddressResetStatePending"])
			resetState = @"pending";
		completion(@{
			@"pattern"    : TGAccountString(codeInfo[@"pattern"]),
			@"codeLength" : TGAccountNumber(codeInfo[@"codeLength"]),
			@"resetState" : resetState,
			@"waitPeriod" : TGAccountNumber(reset[@"wait_period"]),
			@"resetIn"    : TGAccountNumber(reset[@"reset_in"]),
		});
	}];
}

- (void)resetAuthenticationEmailAddressWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"resetAuthenticationEmailAddress"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - login: forgotten two-step password

- (void)requestAuthenticationPasswordRecoveryWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"requestAuthenticationPasswordRecovery"}
	   completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)checkAuthenticationPasswordRecoveryCode:(NSString *)recoveryCode
                                     completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"         : @"checkAuthenticationPasswordRecoveryCode",
		@"recovery_code" : recoveryCode ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)recoverAuthenticationPasswordWithCode:(NSString *)recoveryCode
                                  newPassword:(NSString *)newPassword
                                      newHint:(NSString *)newHint
                                   completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"         : @"recoverAuthenticationPassword",
		@"recovery_code" : recoveryCode ?: @"",
		@"new_password"  : newPassword ?: @"",
		@"new_hint"      : newHint ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - changing our own phone number

- (void)sendChangePhoneNumberCode:(NSString *)phoneNumber
                       completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"        : @"sendPhoneNumberCode",
		@"phone_number" : phoneNumber ?: @"",
		@"settings"     : TGAccountPhoneSettings(NO),
		@"type"         : @{@"@type" : @"phoneNumberCodeTypeChange"},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		completion(TGAccountCodeInfoDict(result));
	}];
}

- (void)checkChangePhoneNumberCode:(NSString *)code
                        completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"checkPhoneNumberCode",
		@"code"  : code ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)resendChangePhoneNumberCodeWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type"  : @"resendPhoneNumberCode",
		@"reason" : @{@"@type" : @"resendCodeReasonUserRequest"},
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		completion(TGAccountCodeInfoDict(result));
	}];
}

- (void)reportChangePhoneNumberCodeMissing:(NSString *)mobileNetworkCode
                                completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"               : @"reportPhoneNumberCodeMissing",
		@"mobile_network_code" : mobileNetworkCode ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - login email address, from Settings

- (void)setLoginEmailAddress:(NSString *)emailAddress
                  completion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{
		@"@type"                   : @"setLoginEmailAddress",
		@"new_login_email_address" : emailAddress ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil, 0);
			return;
		}
		NSDictionary *info = TGAccountEmailCodeInfo(result);
		completion(TGAccountString(info[@"pattern"]),
		           [TGAccountNumber(info[@"codeLength"]) integerValue]);
	}];
}

- (void)resendLoginEmailAddressCodeWithCompletion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{@"@type" : @"resendLoginEmailAddressCode"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil, 0);
			return;
		}
		NSDictionary *info = TGAccountEmailCodeInfo(result);
		completion(TGAccountString(info[@"pattern"]),
		           [TGAccountNumber(info[@"codeLength"]) integerValue]);
	}];
}

- (void)checkLoginEmailAddressCode:(NSString *)code completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"checkLoginEmailAddressCode",
		@"code"  : @{@"@type" : @"emailAddressAuthenticationCode", @"code" : code ?: @""},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - generic email verification

- (void)sendEmailAddressVerificationCode:(NSString *)emailAddress
                              completion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{
		@"@type"         : @"sendEmailAddressVerificationCode",
		@"email_address" : emailAddress ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil, 0);
			return;
		}
		NSDictionary *info = TGAccountEmailCodeInfo(result);
		completion(TGAccountString(info[@"pattern"]),
		           [TGAccountNumber(info[@"codeLength"]) integerValue]);
	}];
}

- (void)resendEmailAddressVerificationCodeWithCompletion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{@"@type" : @"resendEmailAddressVerificationCode"}
	   completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil, 0);
			return;
		}
		NSDictionary *info = TGAccountEmailCodeInfo(result);
		completion(TGAccountString(info[@"pattern"]),
		           [TGAccountNumber(info[@"codeLength"]) integerValue]);
	}];
}

- (void)checkEmailAddressVerificationCode:(NSString *)code completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"checkEmailAddressVerificationCode",
		@"code"  : code ?: @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

#pragma mark - our own profile

- (void)usernamesWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		NSDictionary *usernames = TGAccountDict(result[@"usernames"]);
		if (!usernames){
			completion(@{
				@"editable" : @"",
				@"active"   : [NSArray array],
				@"disabled" : [NSArray array],
			});
			return;
		}
		NSMutableArray *active = [NSMutableArray array];
		for (id name in TGAccountArray(usernames[@"active_usernames"])){
			if ([name isKindOfClass:[NSString class]])
				[active addObject:name];
		}
		NSMutableArray *disabled = [NSMutableArray array];
		for (id name in TGAccountArray(usernames[@"disabled_usernames"])){
			if ([name isKindOfClass:[NSString class]])
				[disabled addObject:name];
		}
		completion(@{
			@"editable" : TGAccountString(usernames[@"editable_username"]),
			@"active"   : active,
			@"disabled" : disabled,
		});
	}];
}

- (void)setUsername:(NSString *)username
             active:(BOOL)active
         completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"     : @"toggleUsernameIsActive",
		@"username"  : username ?: @"",
		@"is_active" : active ? @YES : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)reorderActiveUsernames:(NSArray *)usernames completion:(void (^)(BOOL))completion {
	NSMutableArray *names = [NSMutableArray array];
	for (id name in TGAccountArray(usernames)){
		if ([name isKindOfClass:[NSString class]])
			[names addObject:name];
	}
	[self request:@{
		@"@type"     : @"reorderActiveUsernames",
		@"usernames" : names,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)setProfilePhotoAtPath:(NSString *)path completion:(void (^)(BOOL))completion {
	if (!path.length){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{
		@"@type"     : @"setProfilePhoto",
		@"photo"     : @{
			@"@type" : @"inputChatPhotoStatic",
			@"photo" : @{@"@type" : @"inputFileLocal", @"path" : path},
		},
		@"is_public" : @NO,
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)profilePhotosWithCompletion:(void (^)(NSArray *))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *me){
		if (TGAccountIsError(me)){
			if (completion)
				completion([NSArray array]);
			return;
		}
		[weakSelf request:@{
			@"@type"   : @"getUserProfilePhotos",
			@"user_id" : TGAccountNumber(me[@"id"]),
			@"offset"  : @(0),
			@"limit"   : @(100),
		} completion:^(NSDictionary *result){
			if (!completion)
				return;
			if (TGAccountIsError(result)){
				completion([NSArray array]);
				return;
			}
			NSMutableArray *out = [NSMutableArray array];
			for (id entry in TGAccountArray(result[@"photos"])){
				NSDictionary *photo = TGAccountDict(entry);
				if (!photo)
					continue;
				NSArray *sizes = TGAccountArray(photo[@"sizes"]);
				NSNumber *small = nil;
				NSNumber *big = nil;
				NSInteger bestWidth = -1;
				NSInteger smallestWidth = NSIntegerMax;
				for (id sizeEntry in sizes){
					NSDictionary *size = TGAccountDict(sizeEntry);
					NSDictionary *file = TGAccountDict(size[@"photo"]);
					if (!file)
						continue;
					NSInteger width = [TGAccountNumber(size[@"width"]) integerValue];
					if (width > bestWidth){
						bestWidth = width;
						big = TGAccountNumber(file[@"id"]);
					}
					if (width < smallestWidth){
						smallestWidth = width;
						small = TGAccountNumber(file[@"id"]);
					}
				}
				[out addObject:@{
					@"id"          : TGAccountNumber(photo[@"id"]),
					@"fileId"      : big ?: @0,
					@"smallFileId" : small ?: @0,
					@"date"        : TGAccountNumber(photo[@"added_date"]),
				}];
			}
			completion(out);
		}];
	}];
}

- (void)deleteProfilePhoto:(long long)photoId completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"            : @"deleteProfilePhoto",
		@"profile_photo_id" : @(photoId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)publicLinkWithCompletion:(void (^)(NSString *, NSInteger))completion {
	[self request:@{@"@type" : @"getUserLink"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil, 0);
			return;
		}
		NSString *url = TGAccountString(result[@"url"]);
		completion(url.length ? url : nil,
		           [TGAccountNumber(result[@"expires_in"]) integerValue]);
	}];
}

- (void)searchUserByToken:(NSString *)token
               completion:(void (^)(NSDictionary *))completion {
	[self request:@{
		@"@type" : @"searchUserByToken",
		@"token" : token ?: @"",
	} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		NSString *first = TGAccountString(result[@"first_name"]);
		NSString *last = TGAccountString(result[@"last_name"]);
		NSString *name = last.length
			? [NSString stringWithFormat:@"%@ %@", first, last]
			: first;
		NSDictionary *usernames = TGAccountDict(result[@"usernames"]);
		completion(@{
			@"id"       : TGAccountNumber(result[@"id"]),
			@"name"     : name,
			@"username" : TGAccountString(usernames[@"editable_username"]),
		});
	}];
}

- (void)setBirthdateDay:(NSInteger)day
                  month:(NSInteger)month
                   year:(NSInteger)year
             completion:(void (^)(BOOL))completion {
	if (day < 1 || day > 31 || month < 1 || month > 12){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{
		@"@type"     : @"setBirthdate",
		@"birthdate" : @{
			@"@type" : @"birthdate",
			@"day"   : @(day),
			@"month" : @(month),
			@"year"  : @(year),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)clearBirthdateWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"setBirthdate"} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)setPersonalChat:(int64_t)chatId completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type"   : @"setPersonalChat",
		@"chat_id" : @(chatId),
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

static NSDictionary *TGAccountFlattenUser(NSDictionary *user) {
	if (!user)
		return nil;
	NSString *first = TGAccountString(user[@"first_name"]);
	NSString *last = TGAccountString(user[@"last_name"]);
	NSString *name = last.length
		? [NSString stringWithFormat:@"%@ %@", first, last]
		: first;
	NSDictionary *usernames = TGAccountDict(user[@"usernames"]);
	NSDictionary *verification = TGAccountDict(user[@"verification_status"]);
	NSDictionary *photo = TGAccountDict(user[@"profile_photo"]);
	NSDictionary *small = TGAccountDict(photo[@"small"]);
	NSDictionary *big = TGAccountDict(photo[@"big"]);
	return @{
		@"id"          : TGAccountNumber(user[@"id"]),
		@"firstName"   : first,
		@"lastName"    : last,
		@"name"        : name,
		@"username"    : TGAccountString(usernames[@"editable_username"]),
		@"phoneNumber" : TGAccountString(user[@"phone_number"]),
		@"isPremium"   : TGAccountBool(user[@"is_premium"]),
		@"isVerified"  : TGAccountBool(verification[@"is_verified"]),
		@"smallFileId" : TGAccountNumber(small[@"id"]),
		@"bigFileId"   : TGAccountNumber(big[@"id"]),
	};
}

static NSString *TGAccountSessionDeviceType(id value) {
	NSString *name = TGAccountString(value);
	if ([name hasPrefix:@"sessionDeviceType"])
		return [name substringFromIndex:[@"sessionDeviceType" length]];
	return @"Unknown";
}

static NSDictionary *TGAccountFlattenSession(NSDictionary *session) {
	if (!session)
		return nil;
	return @{
		@"id"                    : TGAccountNumber(session[@"id"]),
		@"isCurrent"             : TGAccountBool(session[@"is_current"]),
		@"isPasswordPending"     : TGAccountBool(session[@"is_password_pending"]),
		@"isUnconfirmed"         : TGAccountBool(session[@"is_unconfirmed"]),
		@"isOfficialApplication" : TGAccountBool(session[@"is_official_application"]),
		@"canAcceptCalls"        : TGAccountBool(session[@"can_accept_calls"]),
		@"canAcceptSecretChats"  : TGAccountBool(session[@"can_accept_secret_chats"]),
		@"appName"               : TGAccountString(session[@"application_name"]),
		@"appVersion"            : TGAccountString(session[@"application_version"]),
		@"deviceModel"           : TGAccountString(session[@"device_model"]),
		@"deviceType"            : TGAccountSessionDeviceType(TGAccountDict(session[@"device_type"])[@"@type"]),
		@"platform"              : TGAccountString(session[@"platform"]),
		@"systemVersion"         : TGAccountString(session[@"system_version"]),
		@"ipAddress"             : TGAccountString(session[@"ip_address"]),
		@"location"              : TGAccountString(session[@"location"]),
		@"loginDate"             : TGAccountNumber(session[@"log_in_date"]),
		@"lastActiveDate"        : TGAccountNumber(session[@"last_active_date"]),
		@"apiId"                 : TGAccountNumber(session[@"api_id"]),
	};
}

- (void)accountInfoWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		completion(TGAccountFlattenUser(result));
	}];
}

- (void)profileInfoWithCompletion:(void (^)(NSDictionary *))completion {
	__weak TGClient *weakSelf = self;
	[self request:@{@"@type" : @"getMe"} completion:^(NSDictionary *me){
		if (TGAccountIsError(me)){
			if (completion)
				completion(nil);
			return;
		}
		NSDictionary *base = TGAccountFlattenUser(me);
		[weakSelf request:@{
			@"@type"   : @"getUserFullInfo",
			@"user_id" : TGAccountNumber(me[@"id"]),
		} completion:^(NSDictionary *full){
			if (!completion)
				return;
			NSMutableDictionary *out = [NSMutableDictionary dictionaryWithDictionary:base];
			NSDictionary *bio = TGAccountDict(full[@"bio"]);
			NSDictionary *birthdate = TGAccountDict(full[@"birthdate"]);
			[out setObject:TGAccountString(bio[@"text"]) forKey:@"bio"];
			[out setObject:TGAccountNumber(birthdate[@"day"]) forKey:@"birthdayDay"];
			[out setObject:TGAccountNumber(birthdate[@"month"]) forKey:@"birthdayMonth"];
			[out setObject:TGAccountNumber(birthdate[@"year"]) forKey:@"birthdayYear"];
			[out setObject:TGAccountNumber(full[@"personal_chat_id"]) forKey:@"personalChatId"];
			completion(out);
		}];
	}];
}

- (void)setFirstName:(NSString *)firstName
            lastName:(NSString *)lastName
          completion:(void (^)(BOOL))completion {
	if (![firstName isKindOfClass:[NSString class]] || firstName.length == 0){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{
		@"@type"      : @"setName",
		@"first_name" : firstName,
		@"last_name"  : [lastName isKindOfClass:[NSString class]] ? lastName : @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)setBio:(NSString *)bio completion:(void (^)(BOOL))completion {
	[self request:@{
		@"@type" : @"setBio",
		@"bio"   : [bio isKindOfClass:[NSString class]] ? bio : @"",
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)setAccountTtlDays:(NSInteger)days completion:(void (^)(BOOL))completion {
	if (days <= 0){
		if (completion)
			completion(NO);
		return;
	}
	[self request:@{
		@"@type" : @"setAccountTtl",
		@"ttl"   : @{
			@"@type" : @"accountTtl",
			@"days"  : @(days),
		},
	} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

- (void)currentSessionWithCompletion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getActiveSessions"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		for (id entry in TGAccountArray(result[@"sessions"])){
			NSDictionary *session = TGAccountDict(entry);
			if (!session)
				continue;
			if ([TGAccountBool(session[@"is_current"]) boolValue]){
				completion(TGAccountFlattenSession(session));
				return;
			}
		}
		completion(nil);
	}];
}

- (void)sessionInfoForId:(long long)sessionId
              completion:(void (^)(NSDictionary *))completion {
	[self request:@{@"@type" : @"getActiveSessions"} completion:^(NSDictionary *result){
		if (!completion)
			return;
		if (TGAccountIsError(result)){
			completion(nil);
			return;
		}
		for (id entry in TGAccountArray(result[@"sessions"])){
			NSDictionary *session = TGAccountDict(entry);
			if (!session)
				continue;
			if ([TGAccountNumber(session[@"id"]) longLongValue] == sessionId){
				completion(TGAccountFlattenSession(session));
				return;
			}
		}
		completion(nil);
	}];
}

- (void)logOutWithCompletion:(void (^)(BOOL))completion {
	[self request:@{@"@type" : @"logOut"} completion:^(NSDictionary *result){
		if (completion)
			completion(!TGAccountIsError(result));
	}];
}

@end

// vim:ft=objc
