# TDLib feature catalogue

853 capabilities across 28 areas, catalogued from `td_api.tl` (3178 declarations) and cross-checked against the modern Telegram-iOS modules.

- **trivial** - API is simple, the wrapper is one method, the UI is a row, a toggle or a sheet.
- **design** - needs genuinely new UI or substantial client plumbing.
- **blocked** - cannot work on an iPhone 4S running iOS 6.

Totals: 434 trivial, 283 design, 136 blocked.

## auth-account
42 capabilities - 19 trivial, 14 design, 9 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Authorization state machine driving login flow | `getAuthorizationState, updateAuthorizationState, authorizationStateWaitTdlibParameters` | yes | root login navigation controller that swaps step screens; our existing login flow |
| Login code entry, code type display and timeout | `checkAuthenticationCode, authenticationCodeInfo, authenticationCodeTypeTelegramMessage` | yes | code field + 'we sent a code via X' label and countdown on login screen |
| Resend code / request call / report code missing | `resendAuthenticationCode, resendCodeReasonUserRequest, resendCodeReasonVerificationFailed` | no | 'Send code again' / 'Call me' buttons under the code field |
| Two-step verification password at login, with hint | `checkAuthenticationPassword, authorizationStateWaitPassword` | yes | password screen with hint label; login flow |
| Log out | `logOut` | yes | destructive row + confirm action sheet in Settings |
| Log in by scanning a QR code shown on another device | `confirmQrCodeAuthentication, session` | no | reuse the existing QR scanner screen, then a confirm sheet naming the device |
| Active sessions list with device, app, IP, location and dates | `getActiveSessions, sessions, session` | yes | 'Active Sessions' table in Privacy and Security; current session header + others |
| Terminate one session / terminate all other sessions | `terminateSession, terminateAllOtherSessions` | no | swipe-to-delete row and a destructive 'Terminate All Other Sessions' button |
| Per-session permissions: accept calls, accept secret chats | `toggleSessionCanAcceptCalls, toggleSessionCanAcceptSecretChats` | no | two switches on a session detail screen |
| Auto-terminate inactive sessions after N days | `setInactiveSessionTtl, sessions.inactive_session_ttl_days` | no | 'Terminate Old Sessions' row with a value picker action sheet |
| Account self-destruct timer | `getAccountTtl, setAccountTtl, accountTtl` | yes | 'If Away For' row with choice sheet in Privacy and Security |
| Delete account with reason and password | `deleteAccount` | no | destructive row, reason text field, password prompt alert |
| Edit own name and bio | `setName, setBio, getMe` | yes | Edit Profile fields |
| Own username set and availability check | `setUsername, checkChatUsername, checkChatUsernameResultOk` | yes | username field with live green/red availability label |
| Public profile link (t.me/username) and login by token | `getUserLink, userLink, searchUserByToken` | no | 'Share my link' row with copy/share sheet on the profile screen |
| Birthdate on own profile | `setBirthdate, birthdate, userFullInfo.birthdate` | no | date row with UIDatePicker in Edit Profile |
| Personal chat shown on own profile | `setPersonalChat` | no | row opening a channel picker in Edit Profile |
| Email address verification (generic, used by passport/support) | `sendEmailAddressVerificationCode, resendEmailAddressVerificationCode, checkEmailAddressVerificationCode` | no | email + code screens |
| Preferred country language for the login screen | `getPreferredCountryLanguage` | no | invisible; picks localisation after country selection |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Phone number entry with country picker and code type hints | `setAuthenticationPhoneNumber, phoneNumberAuthenticationSettings, getCountries` | no | country list table + phone field on login screen (sendPhoneNumber: exists but hardcodes settings, no country list) |
| Password recovery at login via recovery email | `requestAuthenticationPasswordRecovery, checkAuthenticationPasswordRecoveryCode, recoverAuthenticationPassword` | no | 'Forgot password' link -> code entry -> new password screens on login flow |
| New-user registration (first/last name, terms of service) | `registerUser, authorizationStateWaitRegistration, termsOfService` | no | name entry screen + ToS alert on login flow |
| Log in on this device by displaying a QR code | `requestQrCodeAuthentication, authorizationStateWaitOtherDeviceConfirmation` | no | full-screen QR image on the login screen, refreshed when the link changes |
| Login email address (email as second factor at sign-in) | `setAuthenticationEmailAddress, checkAuthenticationEmailCode, emailAddressAuthenticationCode` | no | email entry + email code screens, plus a 'reset email' countdown row, on login flow |
| Two-step verification setup: enable, change and disable password | `getPasswordState, setPassword, passwordState` | no | Privacy and Security section: 'Two-Step Verification' row -> password/hint entry screens |
| Recovery email address management | `getRecoveryEmailAddress, setRecoveryEmailAddress, checkRecoveryEmailAddressCode` | no | row inside Two-Step Verification showing masked email + edit/verify screens |
| Password recovery and account password reset from settings | `requestPasswordRecovery, checkPasswordRecoveryCode, recoverPassword` | no | 'Forgot password' / 'Reset password' rows with pending-date label |
| Login email address change from settings | `setLoginEmailAddress, resendLoginEmailAddressCode, checkLoginEmailAddressCode` | no | row in Two-Step Verification showing login_email_address_pattern + edit screen |
| Unconfirmed new-login banner and session confirmation | `confirmSession, updateUnconfirmedSession, session.is_unconfirmed` | no | banner over the chat list with Confirm / Terminate actions |
| Change own phone number | `sendPhoneNumberCode, phoneNumberCodeTypeChange, checkPhoneNumberCode` | no | 'Change Number' flow reusing the phone entry and code entry screens from login |
| Multiple usernames: activate/deactivate and reorder | `toggleUsernameIsActive, reorderActiveUsernames, usernames` | no | list of usernames with per-row toggle and drag reorder in Edit Profile |
| Own profile photo set and delete | `setProfilePhoto, inputChatPhotoStatic, deleteProfilePhoto` | no | avatar tap -> action sheet (take photo / choose / delete) in Edit Profile |
| Own profile QR code | `getUserLink, settingsSectionQrCode` | no | full-screen QR sheet from the profile screen |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Sign in with Apple ID / Google ID during login | `emailAddressAuthenticationAppleId, emailAddressAuthenticationGoogleId` | no | No Sign in with Apple or Google SDK exists for iOS 6; the token cannot be obtained on a 4S. |
| Firebase SMS device verification | `sendAuthenticationFirebaseSms, firebaseAuthenticationSettingsIos, authenticationCodeTypeFirebaseIos` | no | Requires a valid APNs push receipt for the app bundle; we have no push registration and no matching APNs entitlement on a sideloaded legacy build. |
| Passkey / WebAuthn login and web-token login | `getAuthenticationPasskeyParameters, checkAuthenticationPasskey, checkAuthenticationWebToken` | no | iOS 6 has no AuthenticationServices/passkey support and no WKWebView to run the web token flow. |
| Premium-purchase-gated authorization | `authorizationStateWaitPremiumPurchase, checkAuthenticationPremiumPurchase, setAuthenticationPremiumPurchaseTransaction` | no | Needs a live App Store StoreKit purchase tied to the modern Telegram product id; unreachable from this build. |
| Profile accent color and emoji status | `setProfileAccentColor, setAccentColor, getDefaultProfilePhotoCustomEmojiStickers` | no | Depends on premium-gated colors and animated custom emoji rendering that our 2013-style design deliberately does not have. |
| Profile audio (profile song) | `getUserProfileAudios, addProfileAudio, setProfileAudioPosition` | no | Premium-only modern feature requiring media picker plus streaming playback on the profile; not worth 4S budget and gated server-side. |
| Hide sponsored messages | `toggleHasSponsoredMessagesEnabled` | no | Toggle is one call but it only takes effect for Premium subscribers. |
| Telegram Passport data and authorization forms | `getAllPassportElements, setPassportElement, getPassportAuthorizationForm` | no | Enormous document-capture UI plus client-side encryption; disproportionate for a 4S port and rarely used. |
| Temporary password for wallet/withdrawal confirmations | `getTemporaryPasswordState, createTemporaryPassword, temporaryPasswordState` | no | Only meaningful for the payments/withdrawal flows, which are out of scope on this client. |

## bots
27 capabilities - 12 trivial, 8 design, 7 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Callback button press (get answer, show alert/toast, open URL) | `getCallbackQueryAnswer, callbackQueryPayloadData, callbackQueryPayloadGame` | no | tap handler on an inline button, result shown via TGAlertView or TGSnackbar, url opened with UIApplication openURL |
| Callback with password (2FA-protected buttons) | `callbackQueryPayloadDataWithPassword, getCallbackQueryAnswer` | no | password prompt alert before re-issuing the callback |
| Reply keyboard special buttons: share phone / share location / create poll | `keyboardButtonTypeRequestPhoneNumber, keyboardButtonTypeRequestLocation, keyboardButtonTypeRequestPoll` | no | confirmation action sheet, then reuse existing contact/location/poll send paths |
| Start a bot / deep-link start parameter | `sendBotStartMessage, internalLinkTypeBotStart, internalLinkTypeBotStartInGroup` | no | a full-width START button replacing the input bar in an empty bot chat |
| Bot profile header: description, short description, about | `botInfo, getBotInfoDescription, getBotInfoShortDescription` | no | extra rows in TGProfileViewController for bot users |
| Inline results switch-pm button (Switch to private chat) | `inlineQueryResultsButtonTypeStartBot, inlineQueryResultsButton` | no | a header row on top of the inline results panel |
| Recently used inline bots | `getRecentInlineBots` | no | suggestion rows shown when the user types a bare '@' in the input bar |
| switchInline inline-keyboard button (query hand-off to another chat) | `inlineKeyboardButtonTypeSwitchInline, targetChatCurrent, targetChatChosen` | no | prefills the input bar, or opens TGForwardPicker to choose a target chat first |
| Bot write-access permission (Allow bot to message you) | `canBotSendMessages, allowBotToSendMessages` | no | a confirmation action sheet, usually triggered from a bot start or link |
| Bot service messages (write access allowed, users shared, chat shared, bot refunded) | `messageBotWriteAccessAllowed, messageUsersShared, messageChatShared` | no | centered grey service-text line in ChatViewCell |
| Message-is-from-inline-bot attribution (via @bot) | `message.via_bot_user_id, getUser` | no | a 'via @bot' suffix in the message header line |
| Bot similar bots suggestions | `getBotSimilarBots, getBotSimilarBotCount, openBotSimilarBot` | no | a 'Similar bots' section on the bot profile screen |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Inline keyboard rendering under messages | `replyMarkupInlineKeyboard, inlineKeyboardButton, inlineKeyboardButtonTypeUrl` | no | a button grid laid out under the bubble in ChatViewCell, sized into the cell height |
| Custom reply keyboard (show/hide, resize, one-time, persistent) | `replyMarkupShowKeyboard, keyboardButton, keyboardButtonTypeText` | no | a keyboard-substitute panel above the input bar in TGChatViewController plus a toggle button in the input accessory |
| Request users / request chat buttons | `keyboardButtonTypeRequestUsers, keyboardButtonTypeRequestChat, shareUsersWithBot` | no | a filtered picker built on TGForwardPicker / TGContactsViewController, then the share call |
| Bot command list and slash-command autocomplete | `botCommand, botCommands, botInfo` | no | a dropdown list above the input bar when the text starts with '/', and a slash button in the input bar |
| Inline query results (@bot query in the input bar) | `getInlineQueryResults, inlineQueryResults, inlineQueryResultArticle` | no | a results panel above the input bar (list for articles, grid for media) with paging on next_offset |
| Bot menu button (the button left of the input bar) | `botMenuButton, getMenuButton, botInfo.menu_button` | no | a small labelled button in the input bar of a bot chat that opens a web app or the command list |
| Bot verification badge on senders | `botVerification, setMessageSenderBotVerification, removeMessageSenderBotVerification` | no | small custom-emoji badge next to a name in profile/chat header |
| Bot management console (create/rename bots, tokens, media previews, usernames) | `createBot, checkBotUsername, getOwnedBots` | no | a whole bot-owner settings stack under Settings |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Web apps (openWebApp / bot mini apps) | `openWebApp, closeWebApp, getWebAppUrl` | no | Mini apps require WKWebView-class JS bridging, modern TLS and ES6; iOS 6 UIWebView cannot run current Telegram Web App JS, and the 512MB 4S would not survive a modern SPA anyway. |
| Attachment menu bots | `getAttachmentMenuBot, attachmentMenuBot, toggleBotIsAddedToAttachmentMenu` | no | Every attachment-menu bot entry point launches a web app, which is blocked; the icons alone would be dead buttons. |
| Games (play, high scores) | `messageGame, game, setGameScore` | no | The game bubble itself is drawable (messageGame is already recognised in TGClient), but playing requires loading an HTML5 game URL in a modern web view; only a static, non-playable card plus the high-score list is achievable, so treat playing as blocked. |
| Inline message editing (editing messages sent via inline bots) | `editInlineMessageText, editInlineMessageCaption, editInlineMessageReplyMarkup` | no | These require a bot token session (checkAuthenticationBotToken); a user client can never call them. |
| Business connected bot management | `getBusinessConnectedBot, setBusinessConnectedBot, deleteBusinessConnectedBot` | no | Telegram Business features require an active Premium/Business subscription on the account; unusable for the target user. |
| Prepared inline messages and prepared keyboard buttons | `savePreparedInlineMessage, getPreparedInlineMessage, savePreparedKeyboardButton` | no | Only ever triggered from inside a running Web App, which we cannot host. |
| Grossing web app bots / web app placeholder / guard bot url | `getGrossingWebAppBots, getWebAppPlaceholder, getGuardBotWebAppUrl` | no | All are support calls for the mini-app runtime that iOS 6 cannot provide. |

## calls
28 capabilities - 17 trivial, 3 design, 8 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Outgoing 1-to-1 voice call | `createCall, callProtocol, updateCall` | yes | already-existing TGCallViewController full-screen call screen, launched from profile 'Call' row |
| Incoming call ring + accept/decline | `updateCall, acceptCall, discardCall` | yes | incoming call screen with Accept/Decline, plus local notification when backgrounded |
| Call signaling data channel | `sendCallSignalingData, updateNewCallSignalingData` | yes | none, transport only |
| Emoji key verification (call fingerprint) | `callStateReady` | yes | four emoji shown at top of the active call screen with a tap-to-explain alert |
| Mute microphone and speakerphone toggle | `` | yes | two toggle buttons on the call screen |
| End call with correct discard reason and duration | `discardCall, callDiscardReasonHungUp, callDiscardReasonMissed` | yes | end-call button plus a status line reflecting the reason |
| Call quality rating prompt | `sendCallRating, callStateDiscarded, callProblemEcho` | no | star-rating alert after call end plus a problem-checkbox action sheet when rating is low |
| Call debug information and log upload | `sendCallDebugInformation, sendCallLog, inputCallDiscarded` | no | none, silent background submit when need_debug_information/need_log is set |
| Call bubbles inside chat history | `messageCall` | yes | in-chat call row with direction arrow, duration and tap-to-call-back |
| Call-back from a past call message | `createCall, inputCallFromMessage` | no | tap on a call row in chat or in the call log |
| Callability gating (can_be_called / privacy restricted) | `userFullInfo, getUserFullInfo` | yes | show/hide the Call row on the profile screen and an explanatory alert on refusal |
| Use less data for calls | `getAutoDownloadSettingsPresets, setAutoDownloadSettings, autoDownloadSettings` | no | a Never/On mobile/Always segmented row in Settings > Data and Storage |
| Per-session 'accept calls on this device' toggle | `toggleSessionCanAcceptCalls, session` | no | a switch row on the active-session detail screen |
| Call network usage statistics | `getNetworkStatistics, networkStatisticsEntryCall, resetNetworkStatistics` | no | a 'Calls' line with sent/received bytes and total duration in a Network Usage screen |
| Group call service messages in chat history | `messageVideoChatScheduled, messageVideoChatStarted, messageVideoChatEnded` | no | grey centered service lines in the chat, same style as other service messages |
| Decline a group call invitation from a message | `declineGroupCallInvitation, messageGroupCall` | no | a Decline button on the incoming group-call message row |
| Top-called contacts suggestion | `getTopChats, topChatCategoryCalls, removeTopChat` | no | a frequently-called row strip at the top of the call log or contact picker |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Call log / recent calls list | `searchCallMessages, messageCall, deleteAllCallMessages` | no | a Calls tab or a Recent Calls screen listing call messages with direction icon, plus 'Clear' and an only-missed filter |
| Calls privacy settings (who can call me, P2P) | `getUserPrivacySettingRules, setUserPrivacySettingRules, userPrivacySettingAllowCalls` | no | two rows in Settings > Privacy leading to Everybody/Contacts/Nobody pickers with exception lists |
| Group call invite links (open / preview) | `internalLinkTypeGroupCall, linkPreviewTypeGroupCall, linkPreviewTypeVideoChat` | no | link preview cell and an alert when such a link is tapped |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Upgrade a 1-to-1 call into a group call | `createGroupCall, callDiscardReasonUpgradeToGroupCall, callStateReady` | no | Group calls require the modern tgcalls WebRTC stack (SFU, DTLS-SRTP, simulcast) which does not exist for us; our media layer is libtgvoip 1-to-1 reflector only. |
| 1-to-1 video call | `createCall, acceptCall, callStateReady` | no | Video calls need tgcalls with VP8/H.264 realtime encode; the vendored libtgvoip build is audio-only and a single-core A5 under iOS 6 has no usable realtime encoder API, so is_video must stay NO. |
| Join / leave a video chat in a group | `joinVideoChat, leaveGroupCall, groupCallJoinParameters` | no | joinVideoChat requires a WebRTC join payload produced by tgcalls; without that stack the join cannot be constructed at all. |
| Create / schedule / start / end a video chat | `createVideoChat, startScheduledVideoChat, toggleVideoChatEnabledStartNotification` | no | Creating one without being able to join it is a dead end; the whole feature depends on the missing media stack. |
| Video chat participant management (mute, volume, raise hand, ban, invite) | `getGroupCallParticipants, loadGroupCallParticipants, toggleGroupCallParticipantIsMuted` | no | Only meaningful while joined to a call we cannot join. |
| Video chat / live stream playback (RTMP, stream segments) | `getGroupCallStreams, getGroupCallStreamSegment, groupCallVideoQualityThumbnail` | no | Segments are WebM/VP8+Opus needing realtime demux and decode plus a WebRTC-derived join; the 4S under iOS 6 has no path to decode this in software at rate. |
| Live story group calls, paid group-call messages and reactions | `joinLiveStory, sendGroupCallMessage, addPendingLiveStoryReaction` | no | Depends on both the missing WebRTC stack and on Telegram Stars payments, neither of which is reachable here. |
| End-to-end encrypted group call data (encrypt/decrypt helpers) | `encryptGroupCallData, decryptGroupCallData, updateGroupCallVerificationState` | no | Only used by a WebRTC media pipeline we do not have. |

## channels
43 capabilities - 26 trivial, 11 design, 6 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Channel signatures toggle | `toggleSupergroupSignMessages, supergroup.sign_messages, supergroup.show_message_sender` | no | Two UISwitch rows ("Sign Messages", "Show Author Profiles") in channel admin/edit screen |
| Render author signature on channel posts | `message.author_signature, message.is_channel_post` | yes | Small grey name label in the message bubble footer next to the timestamp, chat view |
| Discussion group linking | `setChatDiscussionGroup, getSuitableDiscussionChats, supergroupFullInfo.linked_chat_id` | no | "Discussion" row in channel admin screen opening a picker list of suitable groups, plus an unlink confirmation action sheet |
| Channel statistics overview (numbers only) | `getChatStatistics, chatStatisticsChannel, supergroupFullInfo.can_get_statistics` | no | "Statistics" row in channel profile pushing a grouped table of statisticalValue pairs (followers, mean views, shares, notification %) |
| Supergroup statistics (discussion group side) | `getChatStatistics, chatStatisticsSupergroup` | no | Same statistics screen in supergroup variant: top senders / top admins / top inviters member rows |
| Post view counter on channel messages | `messageInteractionInfo.view_count, messageInteractionInfo.forward_count, viewMessages` | yes | Eye glyph + count in the bubble footer of channel posts, chat view |
| Boosters list | `getChatBoosts, getUserChatBoosts, foundChatBoosts` | no | Paginated member-style list of boosters with expiry subtitle, pushed from the boost screen; admin only |
| Boost level features explainer | `getChatBoostFeatures, getChatBoostLevelFeatures, chatBoostLevelFeatures` | no | Static per-level feature checklist inside the boost sheet |
| Boost deep link handling | `getChatBoostLinkInfo, linkPreviewTypeChannelBoost, linkPreviewTypeSupergroupBoost` | no | URL handler that resolves a t.me boost link and opens the boost sheet |
| Subscription-expiry member state | `chatMemberStatusMember.member_until_date, getChatInviteLinkMembers` | no | Expiry subtitle in member rows and an "expired subscribers" filter in the link members list |
| Join requests approval queue | `toggleSupergroupJoinByRequest, getChatJoinRequests, processChatJoinRequest` | no | Toggle in admin screen, a chat-header pending-requests bar, and a requests list with Approve/Dismiss buttons per row |
| Channel history visibility for new subscribers | `toggleSupergroupIsAllHistoryAvailable, supergroupFullInfo.is_all_history_available` | no | Toggle row in the discussion group's admin screen |
| Slow mode for discussion group | `setChatSlowModeDelay, supergroupFullInfo.slow_mode_delay, supergroupFullInfo.slow_mode_delay_expires_in` | no | Slow-mode value picker row (off/10s/30s/1m/5m/15m/1h) in group admin, plus a countdown label above the composer |
| Boost-based slow mode exemption | `setSupergroupUnrestrictBoostCount, supergroupFullInfo.unrestrict_boost_count` | no | Stepper/option row under slow mode in group admin |
| Channel admin list and permissions | `getSupergroupMembers, supergroupMembersFilterAdministrators, setChatMemberStatus` | yes | "Administrators" list plus a per-admin rights screen of toggles and a custom-title field |
| Channel subscriber removal / ban list | `getSupergroupMembers, supergroupMembersFilterBanned, supergroupMembersFilterRestricted` | yes | "Removed Users" list with swipe-to-unban in the channel admin screen |
| Hidden members in discussion group | `toggleSupergroupHasHiddenMembers, supergroupFullInfo.can_hide_members, supergroupFullInfo.has_hidden_members` | no | Toggle row in group admin |
| Aggressive anti-spam for discussion group | `toggleSupergroupHasAggressiveAntiSpamEnabled, reportSupergroupAntiSpamFalsePositive, supergroupFullInfo.can_toggle_aggressive_anti_spam` | no | Toggle row plus a "Report false positive" item in the message action sheet |
| Report spam in supergroup | `reportSupergroupSpam` | no | "Report Spam" item in the message long-press action sheet for admins |
| Convert channel to broadcast group / gigagroup | `toggleSupergroupIsBroadcastGroup` | no | Destructive row plus a confirmation alert in group admin |
| Channel description and photo editing | `setChatDescription, setChatTitle, setChatPhoto` | no | Editable title field, multi-line description text view and photo cell in the channel edit screen |
| Inactive channels cleanup prompt | `getInactiveSupergroupChats, leaveChat` | yes | List of inactive channels with a leave action, surfaced when channel creation hits the limit |
| Channel sticker set / custom emoji set for discussion group | `setSupergroupStickerSet, setSupergroupCustomEmojiStickerSet, supergroupFullInfo.can_set_sticker_set` | no | "Group Sticker Set" row with a set search field in group admin |
| Join to send messages (discussion group gate) | `toggleSupergroupJoinToSendMessages` | no | Toggle row in the linked group's admin screen |
| Chat boost event in message feed | `messageChatBoost` | no | Centered service-message line in chat ("X boosted the channel") |
| Sender boost badge on discussion group messages | `message.sender_boost_count` | yes | Small boost icon with count next to the sender name in group bubbles |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Comments button on channel posts (open discussion thread) | `getMessageThreadHistory, getMessageThread, messageInteractionInfo.reply_info` | yes | "N Comments" footer button under channel posts that pushes a thread chat view |
| Channel statistics graphs | `getChatStatistics, getStatisticalGraph, statisticalGraphData` | no | Line/bar chart cards inside the statistics screen, with zoom-token drilldown |
| Per-post statistics | `getMessageStatistics, messageStatistics, messageProperties.can_get_statistics` | no | "View Statistics" item in the message long-press action sheet, pushing a per-message stats screen |
| Boost status and boost this channel | `getChatBoostStatus, chatBoostStatus, getAvailableChatBoostSlots` | no | "Boost" row / level progress bar sheet in channel profile, with a boost confirm alert and share-link action |
| My channel subscriptions (Stars) management | `getStarSubscriptions, editStarSubscription, reuseStarSubscription` | no | "Subscriptions" list in Settings with a cancel action sheet per row |
| Channel invite link management | `createChatInviteLink, editChatInviteLink, getChatInviteLinks` | no | "Invite Links" screen: primary link cell with copy/share, list of additional links, per-link action sheet, creation form with expiry/usage limit |
| Channel public username / private link switch | `setSupergroupUsername, checkChatUsername, toggleSupergroupUsernameIsActive` | no | "Channel Type" screen: Public/Private segmented choice, username text field with live availability check, link preview |
| Create a new channel | `createNewSupergroupChat, createSupergroupChat, setChatDescription` | no | New Channel flow: name/description form, then a type screen, then an invite-members screen |
| Star revenue statistics for channel | `getStarRevenueStatistics, getStarTransactions, supergroupFullInfo.can_get_star_revenue_statistics` | no | Stars balance and transaction list rows inside the monetization screen |
| Automatic translation of channel posts | `toggleSupergroupHasAutomaticTranslation, supergroup.has_automatic_translation, translateMessageText` | no | Toggle in channel admin plus a "Translate" bar above the chat |
| Channel post scheduling and silent posting | `sendMessage, messageSchedulingStateSendAtDate, messageSendOptions.disable_notification` | yes | Long-press on the send button giving "Send Silently" / "Schedule" options, plus a scheduled-messages screen |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Boost-gated channel appearance (accent color, emoji status, custom background) | `setChatAccentColor, setChatProfileAccentColor, setChatEmojiStatus` | no | Animated custom emoji statuses and custom emoji backgrounds cannot render on a 4S/iOS 6 (no TGS/lottie playback path, memory-prohibitive), and these settings are meaningless without the rendering; flat accent color alone could be revisited later. |
| Star subscription invite links (paid channel subscriptions) | `createChatSubscriptionInviteLink, editChatSubscriptionInviteLink, starSubscriptionPricing` | no | Creating them requires the channel owner to be eligible server side, and joining requires an in-app Stars purchase flow (StoreKit product for Stars) that does not exist for this client on iOS 6. |
| Sponsored messages in channel feed | `getChatSponsoredMessages, clickChatSponsoredMessage, reportChatSponsoredMessage` | no | Deliberately out of scope: rendering ads in a third-party legacy client provides no user value, and reporting/hiding paths need Premium; the owner-side toggleSupergroupCanHaveSponsoredMessages could be shipped alone as a trivial admin toggle if wanted. |
| Channel ad revenue statistics and withdrawal | `getChatRevenueStatistics, getChatRevenueTransactions, getChatRevenueWithdrawalUrl` | no | Withdrawal requires a password-confirmed web checkout at Fragment which needs a real browser view; iOS 6 has no WKWebView and the flow is a payment surface we should not fake. |
| Paid reactions on channel posts | `addPendingPaidMessageReaction, commitPendingPaidMessageReaction, removePendingPaidMessageReaction` | no | Sending requires a Stars balance, and topping up needs an in-app purchase flow this client cannot provide; display of an existing paid-reaction count could be added later as a plain counter. |
| Channel giveaways and prepaid giveaways | `getPremiumGiveawayPaymentOptions, getStarGiveawayPaymentOptions, giveawayParameters` | no | Creating a giveaway is an in-app purchase of Premium/Stars, unavailable here; rendering an incoming messageGiveaway bubble as a plain informational card plus getGiveawayInfo is separable and would be trivial. |

## chat-list
27 capabilities - 15 trivial, 11 design, 1 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Main chat list loading & pagination | `loadChats, getChats, chatListMain` | yes | existing chat list table with infinite scroll at the bottom; TGChatListViewController |
| Archived chats list | `chatListArchive, loadChats, getChats` | yes | an 'Archived chats' row at the top of the chat list opening a second chat-list screen |
| Archive / unarchive a chat | `addChatToList, chatListArchive, chatListMain` | yes | swipe action or long-press action sheet on a chat row |
| Pin / unpin chat in a list | `toggleChatIsPinned` | yes | long-press action sheet entry plus a pinned-background tint on the row |
| Mark chat as unread / read | `toggleChatIsMarkedAsUnread, viewMessages` | no | action-sheet entry on a chat row; renders as the blue dot badge |
| Mark whole list as read | `readChatList, chatListMain, chatListArchive` | no | 'Mark all as read' button in the chat list edit menu or nav action sheet |
| Unread counters per list (badge, muted-aware) | `updateUnreadChatCount, updateUnreadMessageCount, updateChatReadInbox` | no | app icon badge, archive row counter, folder tab counters |
| Reorder folders / position of main list | `reorderChatFolders` | no | edit-mode table of folders with reorder controls |
| Recommended chat folders | `getRecommendedChatFolders, recommendedChatFolder, createChatFolder` | no | a 'Recommended' section with Add buttons in the folder settings list |
| Archive settings (auto-archive unknown senders, keep unmuted archived) | `getArchiveChatListSettings, setArchiveChatListSettings, archiveChatListSettings` | no | three switch rows on an 'Archive settings' page under Privacy/Settings |
| Recent / top chats in search | `getTopChats, removeTopChat, getRecentlyOpenedChats` | no | a 'Recent' section shown when the search field is focused but empty |
| Chat positions / correct global ordering | `chatPosition, updateChatPosition, updateChatLastMessage` | yes | no visible UI beyond correct sort order of the existing list |
| Public service announcement / proxy pseudo-chats in the list | `chatSourcePublicServiceAnnouncement, chatSourceMtprotoProxy, chatPosition` | no | a chat row rendered with a special subtitle and no reordering, at the very top of the list |
| Add chat to another list (list picker) | `getChatListsToAddChat, addChatToList, chatLists` | yes | 'Add to folder' action sheet listing eligible folders |
| Chat list previews / drafts and last-message rendering | `updateChatDraftMessage, draftMessage, updateChatLastMessage` | no | the subtitle line of each chat row: red 'Draft:' prefix and 'typing…' replacement |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Reorder pinned chats | `setPinnedChats` | no | UITableView edit mode with reorder controls limited to the pinned section |
| Chat folders: list and switch between them | `updateChatFolders, chatFolderInfo, chatListFolder` | yes | a horizontal folder tab strip under the nav bar, or a 2014-style segmented/list picker above the chat list |
| Chat folder create / edit / delete | `getChatFolder, createChatFolder, editChatFolder` | no | a folder editor screen: name field, included/excluded chat pickers, contact/bot/group/channel type toggles |
| Chat folder icon picker | `getChatFolderDefaultIconName, chatFolderIcon` | no | grid of folder icons inside the folder editor |
| Shareable folder invite links | `getChatFolderInviteLinks, createChatFolderInviteLink, editChatFolderInviteLink` | no | invite-link sub-screen inside the folder editor with per-link chat selection |
| Join a folder by invite link | `checkChatFolderInviteLink, addChatFolderByInviteLink, chatFolderInviteLinkInfo` | no | modal confirm sheet listing the chats that would be joined, triggered by a t.me/addlist URL |
| New chats added to a shared folder | `getChatFolderNewChats, processChatFolderNewChats, updateChatFolders` | no | banner above the folder's chat list offering to add the new chats |
| Chat list search (local + server + public) | `searchChats, searchChatsOnServer, searchPublicChats` | no | search bar pinned above the chat list producing grouped results (chats / global / messages) |
| Sponsored chats in search results | `getSearchSponsoredChats, sponsoredChat, sponsoredChats` | no | an ad-labelled chat row inside search results with a context menu offering report/hide |
| Chat list swipe actions (delete, mute, archive) | `deleteChatHistory, leaveChat, setChatNotificationSettings` | yes | swipe-to-reveal buttons on a chat row |
| Forum topic list as a chat list | `getForumTopics, forumTopic, updateForumTopic` | yes | topic list screen entered from a forum supergroup row |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Folder tags (colored labels on rows) | `updateChatFolders, chatFolderInfo, toggleChatFolderTags` | no | Folder tags are a Telegram Premium feature; toggleChatFolderTags fails without an active subscription. |

## chat-management
39 capabilities - 19 trivial, 17 design, 3 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Edit group/channel title | `setChatTitle` | no | Text field row in a new "Edit group" screen pushed from the group profile (TGProfileViewController) |
| Edit group/channel description (About) | `setChatDescription, getSupergroupFullInfo, getBasicGroupFullInfo` | no | Multiline text view row on the same Edit group screen; description shown on group profile header |
| Slow mode delay | `setChatSlowModeDelay, supergroupFullInfo.slow_mode_delay` | no | Row on Permissions screen opening an action sheet of presets (Off/10s/30s/1m/5m/15m/1h) |
| Copy / share primary invite link | `getChatInviteLink, createChatInviteLink, replacePrimaryChatInviteLink` | no | Single row on group profile showing the t.me link, tap -> action sheet Copy / Share / Revoke |
| Open / preview / join by invite link (t.me/+hash) | `checkChatInviteLink, joinChatByInviteLink, chatInviteLinkInfo` | no | Preview alert (title, photo, member count) with Join button, triggered from the QR scanner and from tapped links in chat |
| Require admin approval to join / join-to-send | `toggleSupergroupJoinByRequest, toggleSupergroupJoinToSendMessages` | no | Two switch rows on the group type / permissions screen |
| Public link / username for group or channel | `setSupergroupUsername, checkChatUsername, checkChatUsernameResult` | no | "Group Type" screen: Private/Public segmented choice, username field with live availability label, and a "too many public links" list |
| Chat history visibility for new members | `toggleSupergroupIsAllHistoryAvailable` | no | Two-option radio rows (Visible / Hidden) on the Group Type screen |
| Channel signatures / show sender | `toggleSupergroupSignMessages` | no | Switch row on channel admin screen |
| Restrict content saving/forwarding | `toggleChatHasProtectedContent` | no | Switch row on Permissions screen |
| Hide member list | `toggleSupergroupHasHiddenMembers` | no | Switch row on Permissions screen |
| Aggressive anti-spam + report false positive | `toggleSupergroupHasAggressiveAntiSpamEnabled, reportSupergroupSpam` | no | Switch row on Permissions screen; "Report as not spam" in the event log row action sheet |
| Message auto-delete timer for a chat | `setChatMessageAutoDeleteTime` | yes | Existing row on chat profile; extend preset list |
| Delete / leave / clear chat | `deleteChat, deleteChatHistory, leaveChat` | yes | Existing swipe action and profile action sheet |
| Ban / kick / restrict a member | `banChatMember, setChatMemberStatus, chatMemberStatusRestricted` | no | Long-press action sheet on a member row: Remove from group / Ban; full restriction editor deferred |
| Removed users (blacklist) list | `getSupergroupMembers, supergroupMembersFilterBanned, supergroupMembersFilterRestricted` | yes | Filtered member list screen with unban swipe |
| Member search inside a chat | `searchChatMembers, chatMembersFilterAdministrators, chatMembersFilterSearch` | no | Search bar above the existing members list |
| Convert channel comments group to a broadcast group (gigagroup) | `toggleSupergroupIsBroadcastGroup` | no | Irreversible-action row with a confirm alert on the group management screen |
| Convert group to forum with topics | `toggleSupergroupIsForum, createForumTopic, editForumTopic` | yes | Switch row on group management; topic list already exists in TGTopicsViewController |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Set / remove group photo | `setChatPhoto, inputChatPhotoStatic, inputChatPhotoPrevious` | no | Tappable avatar on Edit group screen -> action sheet (Take Photo / Choose / Remove) -> UIImagePickerController |
| Default chat permissions (restrict everyone) | `setChatPermissions, chatPermissions` | no | "Permissions" grouped table with ~10 switches (send messages, media, polls, links, pin, change info, invite, topics) plus a members-restricted counter |
| Invite link manager (create, edit, revoke, delete) | `createChatInviteLink, editChatInviteLink, getChatInviteLinks` | no | "Invite Links" list screen (active/revoked sections) plus a link editor with name, expiry date picker, member limit, request-approval switch |
| Members who joined via a link | `getChatInviteLinkMembers, chatInviteLinkMember` | no | Member list section inside the link detail screen, reusing the contacts cell |
| Join requests inbox (approve / decline) | `getChatJoinRequests, processChatJoinRequest, processChatJoinRequests` | no | "N join requests" row on group profile opening a list of user rows with Approve/Dismiss buttons and bio text; plus an in-chat banner |
| Admin list and rights editor | `getChatAdministrators, chatAdministrator, setChatMemberStatus` | no | "Administrators" list plus a per-admin rights screen with ~10 switches and a custom title field |
| Add members to a group | `addChatMember, addChatMembers, failedToAddMembers` | no | Multi-select contact picker pushed from the members list, plus a failure alert for privacy-restricted users |
| Create new group / channel | `createNewBasicGroupChat, createNewSupergroupChat, upgradeBasicGroupChatToSupergroupChat` | no | Two-step flow: member multi-picker then title/photo screen; entry from the chat list compose button |
| Chat event log (recent actions) | `getChatEventLog, chatEvent, chatEventLogFilters` | no | Chronological list screen with a filter sheet (event categories + admin picker); each row renders one of ~45 chatEventAction variants |
| Transfer chat ownership | `canTransferOwnership, transferChatOwnership, canTransferOwnershipResultPasswordNeeded` | no | Destructive row in the admin rights screen -> 2FA password prompt -> confirmation alert |
| Link a discussion group to a channel | `setChatDiscussionGroup, getSuitableDiscussionChats` | no | "Discussion" row on channel profile opening a picker of eligible groups |
| Group sticker set | `setSupergroupStickerSet, searchStickerSet, getSupergroupFullInfo` | no | "Group Stickers" screen: short-name field plus a preview grid of the set |
| Allowed reactions in a chat | `setChatAvailableReactions, chatAvailableReactionsAll, chatAvailableReactionsSome` | no | "Reactions" screen: All/Some/Disabled radio plus an emoji multi-select list |
| Set chat location (location-based group) | `setChatLocation, chatLocation, createNewSupergroupChat` | no | Map picker plus address field on the group type screen |
| Post as channel (message sender in a chat) | `setChatMessageSender, getChatAvailableMessageSenders` | no | Avatar button inside the compose bar opening a sender list sheet |
| Report a chat or chat photo | `reportChat, reportChatPhoto, reportChatResultOptionRequired` | no | "Report" action sheet driven by the server-returned option list, with an optional free-text step |
| Per-chat wallpaper | `setChatBackground, deleteChatBackground, inputBackgroundLocal` | no | "Chat Background" row leading to a wallpaper grid |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Chat accent color, profile accent color, emoji status | `setChatAccentColor, setChatProfileAccentColor, setChatEmojiStatus` | no | Gated behind channel boost levels the account will not have, and the visual payload is animated custom emoji which the 4S cannot render at acceptable cost; also alien to the 2013 visual language we are targeting. |
| Channel boosts, boost-gated unrestrict count, sponsored message controls | `getChatBoostStatus, getChatBoosts, getChatBoostLink` | no | Boosting requires an active Telegram Premium subscription and server-side boost state we cannot provision; the whole surface would render empty. |
| Similar channels recommendation strip | `getChatSimilarChats, getChatSimilarChatCount` | no | Full list is Premium-only (returns a truncated teaser otherwise) and a horizontally scrolling avatar-card strip is a post-2013 idiom with no UICollectionView available. |

## forums
24 capabilities - 16 trivial, 7 design, 1 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Topic list for a forum chat | `getForumTopics, forumTopics, forumTopic` | yes | Existing TGTopicsViewController table of topic rows, opened instead of the chat when chat.isForum |
| Topic list paging beyond 100 | `getForumTopics, forumTopics` | no | Infinite scroll on the topics table using next_offset_date/next_offset_message_id/next_offset_forum_topic_id |
| Search topics by name | `getForumTopics` | no | UISearchBar header over the topics table, reusing the same call with a non-empty query |
| Close / reopen a topic | `toggleForumTopicIsClosed, messageForumTopicIsClosedToggled` | no | Action sheet item on a topic row, plus a locked composer bar inside a closed topic |
| Hide / unhide the General topic | `toggleGeneralForumTopicIsHidden, messageForumTopicIsHiddenToggled` | no | Action sheet item shown only on the row whose info.is_general is true |
| Pin / unpin topics and reorder pins | `toggleForumTopicIsPinned, setPinnedForumTopics, chatEventForumTopicPinned` | no | Action sheet item for pin/unpin; reordering via UITableView editing mode in a separate pass |
| Delete a topic (all its messages) | `deleteForumTopic, chatEventForumTopicDeleted` | no | Destructive action sheet item with a confirmation TGAlertView on a topic row |
| Per-topic notification settings (mute/unmute) | `setForumTopicNotificationSettings, chatNotificationSettings` | no | Mute/Unmute item in the topic action sheet; mute icon on the row |
| Mark topic read: mentions, reactions, poll votes | `readAllForumTopicMentions, readAllForumTopicReactions, readAllForumTopicPollVotes` | no | Invoked implicitly when a topic is opened, plus a Mark as read action sheet item |
| Unpin all messages in a topic | `unpinAllForumTopicMessages` | no | Action sheet item inside the topic's pinned-message banner |
| Copy topic link | `getForumTopicLink, messageLink` | no | Copy link item in the topic action sheet, writing to UIPasteboard |
| Topic icon rendering: colored circle fallback | `forumTopicIcon` | no | 28pt circular icon on each topic row, drawn in code from icon.color plus the first letter of the name |
| Convert a supergroup to a forum / toggle forum tabs | `toggleSupergroupIsForum, chatEventIsForumToggled, createNewSupergroupChat` | no | Topics toggle row in group admin settings |
| View chat as topics toggle | `toggleChatViewAsTopics, updateChatViewAsTopics` | no | Switch row in chat info deciding whether the chat opens as a topic list or a flat message list |
| Topic permission and rights gating | `chatPermissions, chatAdministratorRights, setChatMemberStatus` | no | can_create_topics switch in group permissions, can_manage_topics switch in the admin rights editor |
| Topic service messages in the message list | `messageForumTopicCreated, messageForumTopicEdited, messageForumTopicIsClosedToggled` | no | Centered grey service-message bubbles in the chat transcript |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Open a topic and read its history | `getForumTopicHistory, messageTopicForum, messageSourceForumTopicHistory` | no | TGChatViewController opened with a forumTopicId, title showing the topic name |
| Create a topic | `createForumTopic, forumTopicIcon, forumTopicInfo` | no | Plus bar button on the topics screen opening a small compose screen: name field plus a row of six color swatches |
| Edit topic title and icon | `editForumTopic` | no | Same create form reused in edit mode, reached from a long-press action sheet on a topic row |
| Open an incoming t.me topic link | `getMessageLinkInfo, messageLinkInfo, internalLinkTypeMessage` | no | Link tap handler routing into the topic chat screen |
| Custom-emoji topic icons | `getForumTopicDefaultIcons, forumTopicIcon, getCustomEmojiStickers` | no | Emoji grid in the create/edit topic form and the real icon glyph on each row |
| Forum events in the admin recent-actions log | `getChatEventLog, chatEventLogFilters, chatEventForumTopicCreated` | no | Rows in an admin Recent Actions screen |
| Topic-scoped member mention suggestions | `chatMembersFilterMention, supergroupMembersFilterMention, searchChatMembers` | no | Autocomplete popup above the composer when typing @ inside a topic |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Topic tabs strip above the message list | `has_forum_tabs, getForumTopics` | no | The modern tab strip is a horizontally paging collection of live chat histories; with 512MB and one A5 core keeping several topic histories resident and swipeable is not feasible, and UICollectionView does not exist on iOS 6.1 — use the plain topic list instead. |

## groups
40 capabilities - 20 trivial, 15 design, 5 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Upgrade basic group to supergroup | `upgradeBasicGroupChatToSupergroupChat, messageChatUpgradeTo, messageChatUpgradeFrom` | no | single destructive-styled row in group info ('Convert to Supergroup') with confirm action sheet; chat id changes so the open chat must be reopened |
| Group full info fetch (basic and supergroup) | `getBasicGroup, getBasicGroupFullInfo, getSupergroup` | yes | data source for the chat profile screen header and counters |
| Member list with paging and filters | `getSupergroupMembers, supergroupMembersFilterRecent, supergroupMembersFilterAdministrators` | yes | members table section on the chat profile screen, with a segmented/filtered list screen for the admin views |
| Search members inside a group | `searchChatMembers, chatMembersFilterMembers, chatMembersFilterAdministrators` | no | search bar above the members list on the members screen |
| Remove member / kick | `setChatMemberStatus, chatMemberStatusLeft, messageChatDeleteMember` | no | swipe-to-delete or long-press action sheet on a member row |
| Ban member and revoke their messages | `banChatMember, chatMemberStatusBanned, deleteChatMessagesBySender` | no | action sheet on a member row: Remove / Ban / Ban and delete all messages |
| Banned users list and unban | `getSupergroupMembers, supergroupMembersFilterBanned, setChatMemberStatus` | no | 'Removed Users' list screen reached from group admin settings; swipe to unban |
| Administrators list | `getChatAdministrators, chatAdministrators, chatAdministrator` | no | 'Administrators' row in group settings opening a list with creator/admin subtitles |
| Primary invite link and revoke | `replacePrimaryChatInviteLink, chatInviteLink` | no | invite link cell in group info with Copy / Share / Revoke action sheet |
| Join group by invite link | `checkChatInviteLink, chatInviteLinkInfo, joinChatByInviteLink` | no | preview alert with group title/photo/member count and a Join button, triggered by a t.me/joinchat URL |
| Leave and delete group | `leaveChat, deleteChat, deleteChatHistory` | yes | destructive rows at the bottom of group info with confirm action sheet |
| Slow mode | `setChatSlowModeDelay, supergroupFullInfo` | no | row in group admin settings with a value picker (off/10s/30s/1m/5m/15m/1h) |
| Chat history visibility for new members | `toggleSupergroupIsAllHistoryAvailable` | no | two-option row (Visible / Hidden) in group settings |
| Hide member list | `toggleSupergroupHasHiddenMembers, supergroupFullInfo` | no | switch row in group settings, gated on can_hide_members |
| Aggressive anti-spam | `toggleSupergroupHasAggressiveAntiSpamEnabled, reportSupergroupSpam` | no | switch row in group settings plus a 'Report Spam' item in the message action sheet |
| Restrict saving content | `toggleChatHasProtectedContent` | no | switch row in group settings |
| Linked discussion group for channels | `setChatDiscussionGroup, getSuitableDiscussionChats` | no | 'Discussion' row in channel settings opening a chooser list of suitable groups |
| Group signature and sender display | `toggleSupergroupSignMessages` | no | switch row in channel settings |
| Join to send / join by request gating | `toggleSupergroupJoinToSendMessages, toggleSupergroupJoinByRequest` | no | two switch rows in group type settings |
| Convert supergroup to broadcast group / gigagroup | `toggleSupergroupIsBroadcastGroup` | no | destructive one-way row in group settings with confirm alert |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Create new basic group | `createNewBasicGroupChat, createdBasicGroupChat, failedToAddMembers` | no | contact multi-select + title entry, two-step 'New Group' flow reached from the chats list compose button |
| Create new supergroup / channel | `createNewSupergroupChat` | no | same New Group flow with a type step (group vs channel) plus optional description field |
| Group info: title, photo, description editing | `setChatTitle, setChatPhoto, inputChatPhotoStatic` | no | editable header on the existing chat profile screen: text field for title, tap-avatar photo picker, multiline description cell |
| Add members to a group | `addChatMember, addChatMembers, failedToAddMembers` | no | 'Add Members' row on group profile opening the contact picker; failure list shown as an alert |
| Restrict member (per-user permissions, timed) | `setChatMemberStatus, chatMemberStatusRestricted, chatPermissions` | no | per-user restrictions screen: toggle rows per permission plus a duration picker |
| Promote member to administrator with rights | `setChatMemberStatus, chatMemberStatusAdministrator, chatAdministratorRights` | no | admin rights screen: toggle rows for each right, custom title field, 'Dismiss admin' destructive row |
| Default group permissions | `setChatPermissions, chatPermissions` | no | 'Permissions' screen with a toggle per right, shown for groups where we are admin |
| Transfer group ownership | `transferChatOwnership, chatMemberStatusCreator` | no | 'Transfer Ownership' row plus a 2FA password prompt alert |
| Public group username | `setSupergroupUsername, checkChatUsername, checkChatUsernameResultOk` | no | 'Group Type' screen: Private/Public selector, username field with live availability check, invite link display |
| Additional invite links management | `createChatInviteLink, editChatInviteLink, getChatInviteLinks` | no | 'Invite Links' list screen with a create form (name, expiry, member limit, request-approval switch) |
| Join requests approval | `getChatJoinRequests, processChatJoinRequest, processChatJoinRequests` | no | 'Join Requests' badge row on group info opening a list with Approve/Dismiss buttons per row |
| Group sticker set | `setSupergroupStickerSet, searchStickerSet, supergroupFullInfo` | no | row showing current set, opening a sticker-set search/pick screen |
| Recent actions / admin event log | `getChatEventLog, chatEvent, chatEvents` | no | 'Recent Actions' screen rendering each event as a message-like row, with a filter sheet |
| Report group | `reportChat, reportChatResultOptionRequired, reportChatResultTextRequired` | no | 'Report' row opening an action sheet of server-provided options, then optional text entry |
| Forum topics mode for groups | `toggleSupergroupIsForum, getForumTopics, createForumTopic` | no | switch row plus a topic-list chat variant |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Location-based groups | `setChatLocation, chatLocation, createNewSupergroupChat` | no | Needs a map picker and nearby-chat discovery; MapKit on iOS 6 uses the withdrawn Apple Maps tile service and the nearby-chats server surface is effectively dead. |
| Group boosts and boost level requirements | `getChatBoostStatus, boostChat, getChatBoostLinks` | no | Boosting requires an active Telegram Premium subscription on the account and premium-gated server flows we cannot exercise from this client. |
| Paid messages in groups | `setChatPaidMessageStarCount, supergroupFullInfo.can_enable_paid_messages` | no | Depends on the Telegram Stars balance/payment stack, which needs in-app purchase plumbing unavailable on this legacy build. |
| Group statistics | `getChatStatistics, chatStatisticsSupergroup, getStatisticalGraph` | no | Statistics are delivered as JSON graph specs meant for a JS/web chart renderer; no WKWebView on iOS 6 and no charting stack, so this is out of reach for a reasonable effort. |
| Group video chats | `createVideoChat, getGroupCall, joinGroupCall` | no | Multi-party WebRTC audio mixing on a single-core A5 with 512MB is not viable, and the group-call protocol is far beyond the 1:1 call path we already have. |

## media-download
30 capabilities - 20 trivial, 7 design, 3 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Basic file download by id | `downloadFile, file, localFile` | yes | no new UI; existing progress callback onFileProgress used by chat bubbles and avatars |
| Cancel an in-flight download | `cancelDownloadFile` | no | tap-to-cancel X button on the media bubble's circular progress indicator, plus a cancel row in the download list |
| Pause/resume individual download | `toggleDownloadIsPaused, updateFileDownload` | no | pause/play glyph inside the progress ring and a swipe action in the downloads list |
| Pause/resume all downloads | `toggleAllDownloadsArePaused` | no | single header button in the downloads screen |
| Add a message file to the downloads list | `addFileToDownloads` | no | 'Save to Downloads' entry in the long-press message action sheet |
| Remove file(s) from downloads | `removeFileFromDownloads, removeAllFilesFromDownloads` | no | row swipe-to-delete plus a 'Clear' button in the downloads screen |
| Delete a downloaded file from local cache | `deleteFile` | no | 'Delete from cache' row in the media action sheet and in storage settings |
| Re-fetch file state / refresh a stale file id | `getFile` | no | none, internal plumbing behind image loading |
| Resolve a persistent remote file id | `getRemoteFile, fileTypePhoto, fileTypeDocument` | no | none, internal; enables caching remote ids across sessions since local int32 file ids are not stable |
| Read arbitrary file bytes through TDLib | `readFilePart` | no | none, internal accessor |
| Suggested file name for saving/exporting | `getSuggestedFileName` | no | used in the 'Save' / share flow label |
| Photo/document upload from the device | `inputFileLocal, inputMessagePhoto, inputMessageVideo` | yes | existing attachment sheet; add an upload progress ring and cancel on the outgoing bubble |
| Thumbnail rendering (photoSize / thumbnail) | `thumbnail, photoSize, thumbnailFormatJpeg` | no | message bubbles, media grid, avatars; pick the smallest photoSize that fits and downscale before display |
| Auto-download settings (photos/videos/files, per network type) | `getAutoDownloadSettingsPresets, setAutoDownloadSettings, autoDownloadSettings` | no | 'Auto-Download Media' settings screen: Wi-Fi / Cellular sections with toggles and size steppers, exactly a 2013 grouped table |
| Network type reporting for correct auto-download | `setNetworkType, networkTypeWiFi, networkTypeMobile` | no | none, driven by Reachability at launch and on change |
| Network usage statistics screen | `getNetworkStatistics, networkStatistics, networkStatisticsEntryFile` | no | 'Network Usage' grouped table listing bytes sent/received per file type, with a Reset button |
| Clear cache with filters (age, size, types, chats) | `optimizeStorage, fileTypePhoto, fileTypeVideo` | yes | existing clear-cache action; could grow a 'Keep media for' picker and per-type checkboxes |
| MIME/extension/filename helpers | `getFileMimeType, getFileExtension, cleanFileName` | no | document row icon and label |
| Application download link | `getApplicationDownloadLink` | no | an 'Invite friends' share text |
| Saving media to the camera roll | `downloadFile, getSuggestedFileName` | no | 'Save Image'/'Save Video' rows in the media action sheet |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Downloads list screen (active/paused/completed) | `searchFileDownloads, foundFileDownloads, fileDownload` | no | new UITableView screen with sections for active and completed, per-row progress bar, reached from Settings or a search-page tab |
| Streaming download by byte range (partial download) | `downloadFile, getFileDownloadedPrefixSize, fileDownloadedPrefixSize` | no | no direct UI; feeds an AVPlayer/AVAudioPlayer resource loader for play-while-downloading video and audio |
| Upload progress and cancel for outgoing media | `updateFile, remoteFile, cancelPreliminaryUploadFile` | no | circular progress with an X over the outgoing photo/video bubble, 2013-style |
| Minithumbnail blurred placeholder | `minithumbnail` | no | instant blurred placeholder behind every photo/video bubble before the real thumb arrives |
| Storage usage: fast size and full per-chat breakdown | `getStorageStatisticsFast, getStorageStatistics, getDatabaseStatistics` | yes | existing storage row shows total; the per-chat breakdown list is a new table |
| File generation protocol (client-side conversion) | `updateFileGenerationStart, updateFileGenerationStop, writeGeneratedFilePart` | no | none, background plumbing for re-encoding video/images before upload |
| Full-size photo viewer with progressive load | `downloadFile, photoSize, thumbnail` | no | full-screen media viewer: thumbnail shown immediately, full size faded in on completion, pinch-zoom scroll view |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Animated thumbnail formats (tgs/webm/mpeg4/webp) | `thumbnailFormatTgs, thumbnailFormatWebm, thumbnailFormatMpeg4` | no | iOS 6 has no WebP or WebM decoder and no Lottie/tgs renderer; MPEG4 thumb playback per-cell is beyond the 4S. Fall back to the static JPEG thumbnail instead. |
| Detect file type of an imported file head | `getMessageFileType` | no | Only useful for the chat-import feature, which needs a file picker and document access iOS 6 does not provide. |
| Progressive JPEG sizes (progressive_sizes) | `photoSize` | no | Requires incremental JPEG decoding of arbitrary prefixes; CGImageSourceCreateIncremental on iOS 6 is unreliable for these progressive prefixes and the CPU cost on an A5 outweighs the benefit. |

## messages-content
41 capabilities - 17 trivial, 16 design, 8 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Markdown parse on send / entity extraction | `parseTextEntities, textParseModeMarkdown, textParseModeHTML` | no | none — invisible transform applied to composer text before sendMessage |
| Photo message send and view | `messagePhoto, inputMessagePhoto, inputFileLocal` | yes | bubble thumbnail in chat plus a full-screen viewer |
| Photo/video caption with entities and edit caption | `editMessageCaption, editMessageMedia, messagePhoto` | no | caption line under media in the bubble; an edit sheet reusing the composer |
| Video message send and playback | `messageVideo, inputMessageVideo, inputVideo` | yes | thumbnail with play badge and duration in bubble; MPMoviePlayerViewController for playback |
| Voice note record, send, play | `messageVoiceNote, inputMessageVoiceNote, inputVoiceNote` | yes | hold-to-record button and waveform bubble with play control |
| Round video note playback | `messageVideoNote, videoNote, openMessageContent` | yes | circular video bubble with tap-to-play |
| Static sticker send and display | `messageSticker, inputMessageSticker, inputSticker` | yes | borderless sticker in bubble; sticker keyboard panel |
| Static location message send and map view | `messageLocation, inputMessageLocation, location` | yes | map thumbnail bubble; MKMapView detail screen with directions action |
| Contact message send and display | `messageContact, inputMessageContact, contact` | yes | contact bubble with avatar and name; tap opens profile or add-contact |
| Poll voting and results display | `messagePoll, poll, pollOption` | yes | interactive poll bubble with option rows and result bars |
| Poll voter list | `getPollVoters, pollVoters` | no | per-option voter list pushed from the poll bubble |
| Expired media placeholders | `messageExpiredPhoto, messageExpiredVideo, messageExpiredVoiceNote` | no | italic service-style bubble text |
| Unsupported content placeholder | `messageUnsupported` | no | grey bubble text telling the user to view on another device |
| Media timestamp links in captions | `textEntityTypeMediaTimestamp, getMessageLink` | no | tappable timestamp in text that seeks the referenced audio/video |
| Save incoming media to camera roll / share | `downloadFile, messagePhoto, messageVideo` | yes | action sheet entry on long-press of a media message |
| Message translation | `translateMessageText, translateText` | no | Translate row in the message action sheet, result shown under the bubble |
| Copy media link / message link | `getMessageLink, getMessageLinkInfo` | no | Copy Link row in the message action sheet |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Rich text entities (bold/italic/code/pre/links/mentions) | `formattedText, textEntity, textEntityTypeBold` | no | attributed-string rendering inside the chat bubble label (TGChatViewController/ChatViewCell) plus tap regions |
| Spoiler and expandable blockquote entities | `textEntityTypeSpoiler, textEntityTypeBlockQuote, textEntityTypeExpandableBlockQuote` | no | masked/blurred text run that reveals on tap, and an indented quote block in the bubble |
| Media spoiler (has_spoiler) send/reveal | `inputMessagePhoto, inputMessageVideo, messagePhoto` | no | blurred cover over the media thumb, tap to reveal; a toggle in the attach sheet |
| Self-destructing photo/video (view-once) | `inputMessagePhoto, messageSelfDestructTypeTimer, messageSelfDestructTypeImmediately` | no | timer picker in attach sheet; countdown overlay in viewer; expired placeholder bubble |
| GIF / animation messages | `messageAnimation, inputMessageAnimation, inputAnimation` | no | auto-looping thumbnail in bubble with GIF badge; saved-GIFs picker in attach sheet |
| Music/audio file messages | `messageAudio, inputMessageAudio, inputAudio` | no | track row in bubble (cover, title, performer, duration) with play/pause; ties into the existing voice player |
| Generic document / file messages | `messageDocument, inputMessageDocument, inputDocument` | no | file row in bubble with icon, name, size, download ring; QLPreviewController or share sheet on tap |
| Animated (TGS) and video (WEBM) stickers | `stickerFormatTgs, stickerFormatWebm, messageSticker` | no | animated sticker in bubble, loops on tap |
| Animated emoji messages and tap effect | `messageAnimatedEmoji, animatedEmoji, getAnimatedEmoji` | no | large emoji sticker in bubble, tap triggers effect |
| Live location sharing | `inputMessageLiveLocation, liveLocation, editMessageLiveLocation` | no | duration picker sheet, live bubble with countdown, stop-sharing bar |
| Venue message send and display | `messageVenue, inputMessageVenue, venue` | no | venue bubble (title, address, pin) and a nearby-venue picker in the attach sheet |
| Poll creation and stopping | `inputMessagePoll, inputPollOption, inputPollTypeRegular` | no | poll composer screen (question, option rows, anonymous/multiple/quiz toggles); stop action in message menu |
| Dice / slot machine messages | `messageDice, inputMessageDice, diceStickersRegular` | no | animated dice sticker in bubble; emoji entries in the attach or emoji panel |
| Story shared into a chat | `messageStory, getStory, openStory` | no | story preview bubble; full-screen story viewer |
| Link preview (web page) attached to text | `messageText, linkPreview, linkPreviewTypeArticle` | no | vertical accent bar block under the text with site name, title, description and optional image |
| Media album grouping | `sendMessageAlbum, message.media_album_id` | no | grid of photos in one bubble; multi-select in the attach sheet |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Custom emoji entity | `textEntityTypeCustomEmoji, getCustomEmojiStickers` | no | Inline TGS/WEBM animated glyphs at text scale would need per-run animated layers on a single-core A5; also premium-gated for sending. |
| Video streaming / alternative qualities / storyboards | `alternativeVideo, videoStoryboard, getFileDownloadedPrefixSize` | no | Streaming from a partially downloaded TDLib file needs a local HTTP/HLS shim and seek logic well beyond what a 512MB 4S build can carry; storyboards are pure decoration on top of that. |
| Voice/video note speech recognition transcript | `recognizeSpeech, speechRecognitionResultText, speechRecognitionResultPending` | no | Server-side transcription is Telegram Premium only; without a subscription the call errors. |
| Round video note recording | `inputMessageVideoNote, inputVideoNote` | no | Needs live square-cropped H.264 capture and mux on a 4S with no hardware pipeline exposed through iOS 6 AVFoundation at usable quality. |
| Game messages | `messageGame, game, messageGameScore` | no | HTML5 games need a modern web runtime; iOS 6 UIWebView cannot run current Telegram game bundles and there is no WKWebView. |
| Invoice / payment messages | `messageInvoice, productInfo, getPaymentForm` | no | Checkout requires a provider web flow and card entry through a modern web view; not viable on iOS 6, and star payments are account-gated. |
| Paid media messages | `messagePaidMedia, inputMessagePaidMedia, paidMediaPreview` | no | Unlocking requires a Telegram Stars balance and purchase flow we cannot reach on this client. |
| Instant View article reader | `getWebPageInstantView, webPageInstantView` | no | Rendering the IV block tree is a large custom renderer and the practical shortcut (a web view) is unusable on iOS 6 for modern pages. |

## messages-core
38 capabilities - 21 trivial, 14 design, 3 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Send text message | `sendMessage, inputMessageText, formattedText` | yes | compose bar in TGChatViewController |
| Reply to a message | `sendMessage, inputMessageReplyToMessage, messageReplyToMessage` | yes | reply banner above compose bar plus quoted header inside the bubble in TGChatViewController |
| Edit message text | `editMessageText, inputMessageText` | yes | 'Edit' row in message action sheet, compose bar switches to edit mode |
| Edit media caption | `editMessageCaption, formattedText` | no | same edit-mode compose bar, entered from a photo/video bubble |
| Check what a message allows (edit/delete/forward permissions) | `getMessageProperties` | no | drives which rows appear in the long-press action sheet |
| Delete messages for me / for everyone | `deleteMessages, getMessageProperties` | yes | action sheet with two destructive rows, plus the existing undo snackbar |
| Delete all messages from one sender / by date range | `deleteChatMessagesBySender, deleteChatMessagesByDate` | no | rows in a group member's context sheet and in a chat-admin menu |
| Clear chat history | `deleteChatHistory` | yes | row in chat profile / chat-list swipe menu |
| Forward messages | `forwardMessages, messageSendOptions` | yes | TGForwardPicker chat chooser |
| Forward as copy / hide sender / remove captions | `forwardMessages, messageCopyOptions` | no | toggle rows on the forward-picker confirmation sheet |
| Message sending state (clock / check / double check) | `messageSendingStatePending, messageSendingStateFailed, updateMessageSendSucceeded` | no | small status glyph in the bubble timestamp row |
| Silent send and protected content | `messageSendOptions` | no | toggles in the long-press-on-Send menu |
| Forum topics as message threads | `getForumTopics, getForumTopic, getForumTopicHistory` | yes | TGTopicsViewController list feeding a topic-scoped chat |
| Typing / recording chat action indicator | `sendChatAction, chatActionTyping, chatActionRecordingVoiceNote` | no | navigation subtitle in the chat screen, replacing 'last seen' |
| Mark messages read and open media content | `viewMessages, openMessageContent, readAllChatMentions` | yes | invisible, driven by scroll position; plus a mentions jump button |
| Copy message link (t.me permalink) | `getMessageLink, getMessageLinkInfo` | no | 'Copy Link' row in the message action sheet |
| Local unsent placeholder messages | `addLocalMessage` | no | none directly; used for optimistic local echo |
| Translate message text | `translateMessageText, translateText` | no | 'Translate' row in the action sheet showing result in an alert or an expanded bubble |
| Message read date and viewer list | `getMessageReadDate, getMessageViewers` | no | 'Seen by' row in the action sheet opening a small member list |
| Auto-delete timer for a chat | `setChatMessageAutoDeleteTime` | yes | picker row in the chat profile |
| Embed code for a public message | `getMessageEmbeddingCode` | no | 'Copy embed code' row |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Reply with text quote (partial-selection quoting) | `inputTextQuote, textQuote, inputMessageReplyToMessage` | no | text-selection menu in a message bubble feeding a quote into the reply banner |
| Reply to a message in another chat (external reply) | `inputMessageReplyToExternalMessage` | no | 'Reply in another chat' entry in the message action sheet reusing TGForwardPicker |
| Replace media in a sent message | `editMessageMedia, inputMessagePhoto, inputMessageVideo` | no | 'Replace photo' action leading to the image picker |
| Resend failed messages | `resendMessages, messageSendingStateFailed` | no | tap on the red failed-send badge in a bubble, offering Resend / Delete |
| Per-chat drafts (save and restore compose text) | `setChatDraftMessage, draftMessage, draftMessageContentText` | no | automatic on leaving a chat; draft preview shown in red in the chat-list row |
| Scheduled messages (send at date / when online) | `messageSendOptions, messageSchedulingStateSendAtDate, messageSchedulingStateSendWhenOnline` | no | long-press on Send opens a date picker; a separate scheduled-messages screen listing pending sends |
| Comment threads on channel posts | `getMessageThread, messageThreadInfo, getMessageThreadHistory` | no | 'N comments' footer bar under channel posts opening a thread chat screen |
| Message reactions | `addMessageReaction, setMessageReactions, getMessageAvailableReactions` | yes | reaction chips under the bubble plus an emoji picker strip on long-press |
| Jump to message / jump to date | `getChatMessageByDate, getChatHistory, getMessage` | yes | calendar sheet and tapping a reply header to scroll to the original |
| Search inside a chat | `searchChatMessages, searchMessagesFilter*, getChatMessageByDate` | yes | search bar over the chat with up/down result navigation |
| Quick reply shortcut messages | `quickReplyShortcut, sendQuickReplyShortcutMessages, checkQuickReplyShortcutName` | no | settings screen listing shortcuts plus a '/' autocomplete in the compose bar |
| Inline keyboard button presses | `getCallbackQueryAnswer, callbackQueryPayloadData, replyMarkupInlineKeyboard` | no | tappable button rows drawn under a bot message bubble |
| Media album (grouped) send | `sendMessageAlbum, inputMessagePhoto, inputMessageVideo` | no | multi-select image picker and a grid layout inside one bubble |
| Report messages | `reportChat, reportChatResultOptionRequired, reportChatResultTextRequired` | no | multi-step action sheet driven by the returned option list |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Message view/forward statistics | `getMessageStatistics, getMessagePublicForwards` | no | The payload is JSON graph data meant for a charting engine; no charting stack exists on iOS 6 here and it is admin-only for large channels. |
| Message effects on send | `getMessageEffect, messageSendOptions` | no | Requires premium and full-screen animated sticker playback; the 4S cannot render those effects and non-premium accounts cannot set effect_id. |
| Sponsored message view metrics | `sendMessageViewMetrics, reportChatSponsoredMessage` | no | Only meaningful for sponsored-ad rendering we do not and should not implement. |

## misc-settings
28 capabilities - 15 trivial, 7 design, 6 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Solid-color / gradient wallpaper (no image download) | `setDefaultBackground, backgroundTypeFill, backgroundFillSolid` | no | Colour swatch list row in the background picker |
| Search background by name / background deep link | `searchBackground, getBackgroundUrl` | no | Handled from a t.me/bg/... link, plus a share-link action sheet item on the current wallpaper |
| Auto-download presets (low/medium/high) | `getAutoDownloadSettingsPresets, autoDownloadSettingsPresets, autoDownloadSettings` | no | Settings > Data and Storage: three-row preset chooser with checkmark |
| Auto-download settings per network type | `setAutoDownloadSettings, networkTypeWiFi, networkTypeMobile` | no | Two sub-screens (Using Wi-Fi / Using Mobile) of toggles and size steppers |
| Report network type to TDLib | `setNetworkType` | no | No UI; called from reachability changes in TGClient |
| Network usage statistics + reset | `getNetworkStatistics, resetNetworkStatistics, networkStatistics` | no | Settings > Data and Storage > Network Usage: grouped value rows plus a destructive reset row |
| Autosave media to gallery settings | `getAutosaveSettings, setAutosaveSettings, scopeAutosaveSettings` | no | Settings > Data and Storage > Save to Camera Roll: three scope rows with toggles |
| Storage usage: fast stats and full per-chat stats | `getStorageStatisticsFast, getStorageStatistics, getDatabaseStatistics` | yes | Settings > Data and Storage > Storage Usage: total size header plus per-chat rows |
| Clear cache / cache TTL | `optimizeStorage, fileTypePhoto, fileTypeVideo` | yes | Destructive 'Clear Cache' row + 'Keep Media' TTL chooser (3 days / 1 week / 1 month / forever) |
| Archive settings (auto-archive unknown senders, keep unmuted/folder chats archived) | `getArchiveChatListSettings, setArchiveChatListSettings, archiveChatListSettings` | no | Archived Chats screen > gear item, or Settings > Privacy: three toggle rows |
| Application config JSON | `getApplicationConfig, jsonValueObject, jsonValueString` | no | No UI; feature flags consumed by TGCapabilities |
| TDLib options read/write (per-user limits, flags) | `getOption, setOption, optionValueBoolean` | yes | No UI; internal, plus a hidden debug list |
| App update / download link and deep-link info | `getApplicationDownloadLink, getDeepLinkInfo, deepLinkInfo` | no | Alert shown when an unsupported deep link is opened; 'need to update' text |
| Scope notification settings (private / group / channel defaults) | `getScopeNotificationSettings, setScopeNotificationSettings, scopeNotificationSettings` | no | Settings > Notifications: three sections of toggles and preview switches |
| Reset all chat backgrounds / theme back to default | `deleteDefaultBackground, setChatTheme` | no | 'Reset' destructive row at the bottom of the appearance screen |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| App theme selection (light/dark/classic) | `` | no | Settings > Appearance: table with theme rows + checkmark, applied through our TGTheme; purely local, no TDLib |
| Chat wallpaper: list installed backgrounds | `getInstalledBackgrounds, background, backgrounds` | no | Settings > Chat Background: grid/thumbnail picker; on iOS 6 a plain UITableView of downscaled preview rows is safer than a grid |
| Set / clear default chat background | `setDefaultBackground, deleteDefaultBackground, inputBackgroundLocal` | no | Row action + confirm in the background picker; result must repaint TGChatViewController message-list backdrop |
| Per-chat theme (emoji themes) | `setChatTheme, inputChatThemeEmoji, chatThemeEmoji` | no | Chat info screen row opening a horizontal emoji-theme strip |
| Suggested actions banner (set password, check phone number, enable archive-and-mute) | `updateSuggestedActions, suggestedActionEnableArchiveAndMuteNewChats, suggestedActionCheckPassword` | no | Dismissible header cell at the top of the chat list, tapping routes to the relevant settings screen |
| Interface language selection | `getLocalizationTargetInfo, getLanguagePackInfo, getLanguagePackStrings` | yes | Settings > Language: table of languages with checkmark |
| Custom notification sounds library | `getSavedNotificationSounds, getSavedNotificationSound, addSavedNotificationSound` | no | Settings > Notifications > Sound: list of built-in and saved sounds |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Freeform multi-point gradient and animated pattern wallpapers | `backgroundFillFreeformGradient, backgroundTypePattern` | no | Four-point animated mesh gradients and animated SVG pattern masks need per-frame GPU compositing that the single-core A5 with no Metal cannot sustain behind a scrolling table. |
| Gift chat themes | `getGiftChatThemes, inputChatThemeGift, chatThemeGift` | no | Requires owned gift NFTs and Stars-era account state that this client cannot obtain; the themes also rely on animated backdrops we cannot render. |
| Accent colour / profile accent colour for own account | `setAccentColor, setProfileAccentColor, profileAccentColor` | no | Name/profile accent colours beyond the default palette are a Premium-gated server feature and the accompanying custom-emoji backdrops cannot be rendered here. |
| Premium-related suggested actions | `suggestedActionUpgradePremium, suggestedActionRestorePremium, suggestedActionSubscribeToAnnualPremium` | no | These lead to in-app purchase and Stars flows that require a current App Store receipt path and Premium server state unavailable to this client; they must simply be filtered out. |
| Custom local language pack (translation platform) | `addCustomServerLanguagePack, setCustomLanguagePack, setCustomLanguagePackString` | no | Depends on the full string-lookup layer plus deep-link handling; no value for a legacy client and would double the localisation work. |
| Default background custom-emoji stickers / themed emoji statuses | `getDefaultBackgroundCustomEmojiStickers, getThemedEmojiStatuses, getDefaultChatEmojiStatuses` | no | Animated custom emoji require TGS/lottie rendering that a 4S cannot do at acceptable frame rates, and emoji statuses are Premium-only. |

## notifications
27 capabilities - 17 trivial, 6 design, 4 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Per-scope notification on/off (private / groups / channels) | `getScopeNotificationSettings, setScopeNotificationSettings, notificationSettingsScopePrivateChats` | yes | three switch rows on the existing Notifications settings page (already built in TGSettingsViewController.m) |
| Message preview toggle per scope | `scopeNotificationSettings, setScopeNotificationSettings, getScopeNotificationSettings` | no | one extra switch row per scope section, 'Message Preview', on the Notifications page |
| Pinned-message and mention notification suppression per scope | `scopeNotificationSettings, setScopeNotificationSettings` | no | two switch rows under each group/channel scope section |
| Live scope-settings sync from other devices | `updateScopeNotificationSettings` | no | no new UI: refresh the toggles on the Notifications page when the update arrives |
| Mute / unmute a single chat | `setChatNotificationSettings, chatNotificationSettings, updateChatNotificationSettings` | yes | chat list swipe/long-press action sheet and the profile screen's Notifications row |
| Mute a chat for a chosen duration (1 hour / 8 hours / 2 days / forever) | `setChatNotificationSettings, chatNotificationSettings` | no | TGActionSheet with four duration options, launched from the profile Notifications row |
| Reset all notification settings | `resetAllNotificationSettings` | no | a destructive red row at the bottom of the Notifications page with a confirm TGAlertView |
| Per-chat default 'send silently' flag | `toggleChatDefaultDisableNotification, updateChatDefaultDisableNotification` | no | toggle row on the chat's notification sub-page; optionally a bell icon in the compose bar |
| Reaction and poll-vote notification settings | `setReactionNotificationSettings, reactionNotificationSettings, reactionNotificationSourceNone` | no | a 'Reactions' section with two picker rows (Everyone / Contacts / Off) and a preview toggle |
| Dismissing notifications the user already read | `removeNotification, removeNotificationGroup` | no | none, called when a chat is opened |
| Push message content rendering (preview text for each media type) | `notificationTypeNewPushMessage, pushMessageContentText, pushMessageContentPhoto` | no | no screen: a formatter producing the alert body string |
| Pending-notification keepalive hint | `updateHavePendingNotifications` | no | none |
| Auto-archive and mute new chats from unknown users | `getArchiveChatListSettings, setArchiveChatListSettings, archiveChatListSettings` | no | two or three switch rows in a Privacy or Notifications section |
| Forum topic notification settings | `setForumTopicNotificationSettings, forumTopic, updateForumTopic` | no | mute row on the topic list rows in TGTopicsViewController |
| In-app sounds, vibrate and in-app banner preferences | `settingsSectionNotifications` | no | an 'In-App Notifications' section of local switches |
| Service notifications from the server (including AUTH_KEY_DROP) | `updateServiceNotification` | no | a TGAlertView, with Cancel plus Log Out buttons when the type begins with AUTH_KEY_DROP_ |
| Badge count and unread counters feeding the app icon | `updateUnreadChatCount, updateUnreadMessageCount` | no | applicationIconBadgeNumber plus the chat list tab badge |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Per-chat override of preview / sound / mentions (use_default_* flags) | `setChatNotificationSettings, chatNotificationSettings, getChat` | no | a dedicated per-chat 'Notifications' sub-page: toggles plus a 'Default' reset row |
| Notification exceptions list (chats that differ from the scope default) | `getChatNotificationSettingsExceptions, notificationSettingsScopePrivateChats, notificationSettingsScopeGroupChats` | no | 'Exceptions' row per scope opening a chat list with per-row muted/unmuted subtitle, plus 'Delete All Exceptions' |
| Send a single message silently | `messageSendOptions, sendMessage` | no | long-press on the send button showing a 'Send without sound' action sheet |
| Custom notification sound picker (saved/uploaded sounds) | `getSavedNotificationSounds, getSavedNotificationSound, addSavedNotificationSound` | no | a 'Sound' row opening a list of sounds with a checkmark and tap-to-preview |
| Local alerts driven by TDLib notification groups | `updateNotificationGroup, updateNotification, updateActiveNotifications` | no | UILocalNotification banners while backgrounded plus an in-app top banner while foregrounded |
| Notification settings deep links (tg://settings/notifications subsections) | `settingsSectionNotifications, getInternalLinkType` | no | routing only, opens the relevant Notifications sub-page |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Story notification settings and story exceptions | `scopeNotificationSettings, chatNotificationSettings, getStoryNotificationSettingsExceptions` | no | The client has no stories feature at all; story notification settings are meaningless without the story surface, and stories themselves are out of scope on a 4S. |
| APNs push registration (device token upload) | `registerDevice, deviceTokenApplePush, pushReceiverId` | no | A sideloaded, ldid-signed build cannot obtain a valid APNs token for Telegram's push certificate, and Telegram's server would push to the official bundle id anyway; no path to a working token here. |
| Processing an APNs push payload in an extension | `processPushNotification, getPushReceiverId` | no | iOS 6 has no notification service extensions and no mutable push content, and there is no valid push token in the first place. |
| VoIP push for incoming calls | `registerDevice, deviceTokenApplePushVoIP` | no | PushKit does not exist on iOS 6, and the token problem above applies; incoming calls can only be caught while the socket is alive. |

## premium
35 capabilities - 14 trivial, 11 design, 10 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Premium status badge for users | `user.is_premium, user.emoji_status, userFullInfo.premium_gift_options` | yes | Small star badge next to the name in chat list rows, chat header title and profile screen header |
| Premium limits inspector (default vs boosted values) | `getPremiumLimit, premiumLimit, premiumLimitTypePinnedChatCount` | no | A grouped table in Settings > Telegram Premium listing each limit as 'default N / premium M' rows |
| Enforce the correct client-side limits for the current account | `getPremiumLimit, getOption` | no | No screen of its own; caption/bio/message length counters, pinned-chat cap, folder cap in existing editors |
| Current premium state and subscription info | `getPremiumState, premiumState, premiumStatePaymentOption` | yes | Header block on the Premium settings screen: active/inactive, expiry date, price options as read-only rows |
| Redeem a Premium gift code | `checkPremiumGiftCode, premiumGiftCodeInfo, applyPremiumGiftCode` | no | Action sheet from a t.me/giftcode link or a 'Redeem code' row with a text field in Settings |
| Giveaway participation status / 'How it works' sheet | `getGiveawayInfo, giveawayInfoOngoing, giveawayInfoCompleted` | no | Action sheet or modal with explanatory text and one action button, launched by tapping the giveaway bubble |
| Channel boost status and level | `getChatBoostStatus, chatBoostStatus, getChatBoostLink` | no | 'Boosts' section on the channel profile: current level, boost count, progress to next level, copy-link row |
| Who boosted this channel | `getChatBoosts, foundChatBoosts, chatBoost` | no | Paged user list on the channel boost screen, one avatar row per booster with expiry subtitle |
| Boost level feature table | `getChatBoostFeatures, getChatBoostLevelFeatures, chatBoostFeatures` | no | 'What boosts unlock' table, one section per level |
| Star subscriptions management | `getStarSubscriptions, starSubscription, starSubscriptions` | no | Table of active subscriptions with chat title, period and price; tap opens a sheet with Cancel / Renew |
| Premium info sticker for gift/promo headers | `getPremiumInfoSticker` | no | Header image on the Premium or gift screens |
| Premium-gated upload size and download speed options | `getOption('premium_upload_speedup'), getOption('premium_download_speedup'), getOption('is_premium_available')` | no | Informational rows on the Premium screen; also gates the max file size in the attach flow |
| Premium-only privacy toggles (last seen, message privacy, read receipts) | `userPrivacySettingAllowUnpaidMessages, setUserPrivacySettingRules, userPrivacySettingShowStatus` | yes | Extra rows in the existing Privacy settings screen, disabled with a premium hint when not subscribed |
| Ad-free experience / sponsored message removal | `getChatSponsoredMessages, premiumFeatureDisabledAds, chatBoostLevelFeatures.can_disable_sponsored_messages` | no | None; simply not rendering sponsored messages |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Premium feature list / promo screen | `getPremiumFeatures, premiumFeatures, premiumFeatureIncreasedLimits` | no | A dedicated 'Telegram Premium' screen reachable from Settings, one row per feature with icon and subtitle |
| Gift code / giveaway deep link handling | `getInternalLinkType, internalLinkTypePremiumGiftCode, internalLinkTypePremiumGift` | no | URL handler routing t.me links into the redeem or boost sheet |
| Gift Premium to a user with Stars | `getPremiumGiftPaymentOptions, premiumGiftPaymentOption, giftPremiumWithStars` | no | 'Gift Premium' row on a user profile opening a duration picker sheet (3/6/12 months) with star prices |
| View giveaway message and its results | `messageGiveaway, messageGiveawayCreated, messageGiveawayWinners` | no | A custom message bubble in the chat: prize sticker, 'N x Premium for M months', participating channels, winners date |
| Launch a prepaid giveaway the channel already owns | `launchPrepaidGiveaway, prepaidGiveaway, chatBoostStatus.prepaid_giveaways` | no | Row in channel boost screen listing prepaid giveaways, opening a parameters form (date, only-new-members, countries) |
| Boost a channel with your own slots | `getAvailableChatBoostSlots, chatBoostSlot, chatBoostSlots` | no | 'Boost this channel' button plus a slot-reassignment action sheet when all slots are used |
| Star balance and transaction history | `getStarTransactions, starTransactions, starTransaction` | no | 'Stars' row in Settings opening a balance header plus a paged transaction list |
| Received gifts on a profile | `getReceivedGifts, receivedGift, getReceivedGift` | yes | 'Gifts' section on the profile showing gift stickers in a grid, tap opens a detail sheet with Save/Hide and Convert to Stars |
| Sending a star gift | `getAvailableGifts, availableGifts, gift` | no | 'Send a gift' entry on a profile opening a gift catalogue grid with prices, then a message-and-privacy sheet |
| Voice-to-text recognition (premium-gated) | `recognizeSpeech, rateSpeechRecognitionResult, messageVoiceNote.speech_recognition_result` | no | A small 'A' button on voice note bubbles expanding to show transcribed text |
| Business features catalogue | `getBusinessFeatures, businessFeatures, businessFeatureOpeningHours` | no | 'Telegram Business' list of feature rows under the Premium screen |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Buying a Premium subscription in-app | `canPurchaseFromStore, assignStoreTransaction, storePaymentPurposePremiumSubscription` | no | Requires the official Telegram App Store product IDs bound to their bundle ID; our sideloaded bundle cannot fetch or transact those SKProducts, and TDLib will reject a receipt from a foreign bundle. |
| Buying Premium via the payment link (web checkout) | `premiumPaymentOption.payment_link, internalLinkTypeInvoice, getPaymentForm` | no | The Telegram invoice checkout flow is a modern web/native payment form; iOS 6 UIWebView plus no card-entry UI on our side makes a real purchase unreachable, and TDLib's native form needs card tokenization we cannot implement safely. |
| Gift Premium via App Store purchase | `storePaymentPurposePremiumGift, storePaymentPurposePremiumGiftCodes, telegramPaymentPurposePremiumGift` | no | Same App Store product-ID problem as buying a subscription; the alternate telegramPaymentPurpose path needs a card payment form we cannot build on iOS 6. |
| Creating a giveaway in a channel | `getPremiumGiveawayPaymentOptions, premiumGiveawayPaymentOption, storePaymentPurposePremiumGiveaway` | no | Creation is fundamentally a purchase, and every purchase path (App Store product IDs, card form) is unreachable for us; the multi-step composer would be dead UI. |
| Buying Stars | `getStarPaymentOptions, starPaymentOption, storePaymentPurposeStars` | no | In-app purchase against Telegram's own App Store products, impossible from our bundle; the card-payment alternative is equally out of reach. |
| Star revenue and withdrawal for owned channels | `getStarRevenueStatistics, starRevenueStatus, getStarWithdrawalUrl` | no | Needs 2FA password entry then an external web withdrawal page; the statistical graph is a modern chart format with no renderer available to us, and the flow ends in a browser we cannot secure. |
| Upgraded (unique) gifts and their attributes | `getGiftUpgradePreview, upgradeGift, upgradedGift` | no | The entire visual identity is animated custom-emoji models, symbol patterns and gradient backdrops rendered per-frame; a 4S with no lottie renderer and 512MB cannot present these, and every action costs stars we do not have. |
| Emoji status (premium and gift-based) | `setEmojiStatus, emojiStatus, emojiStatusTypeCustomEmoji` | no | Statuses are custom emoji identified only by a document id that must be downloaded and animated; we have no custom-emoji rendering pipeline, so the picker would show empty cells. |
| Premium stickers and premium sticker examples | `getPremiumStickers, getPremiumStickerExamples, stickerFullTypeRegular.premium_animation` | no | The whole point is the premium animation overlay, which is a TGS/webm effect we cannot play; showing the static sticker adds nothing over the normal packs. |
| Gift auctions and crafting | `getGiftAuctionState, getGiftAuctionAcquiredGifts, giftAuction` | no | Real-time bidding UI on top of animated unique-gift art, requiring a large star balance; nothing about it is reachable on this device or this account. |

## privacy-security
30 capabilities - 14 trivial, 8 design, 8 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Privacy rules for Last Seen / Photo / Calls / Groups / Forwards / Phone / Bio | `getUserPrivacySettingRules, setUserPrivacySettingRules, userPrivacySettingShowStatus` | yes | Privacy and Security screen: one grouped table row per setting pushing a 3-option radio list (Everybody / My Contacts / Nobody) |
| Peer-to-peer call privacy | `userPrivacySettingAllowPeerToPeerCalls, getUserPrivacySettingRules, setUserPrivacySettingRules` | yes | Radio row inside the Calls privacy submenu |
| Blocked users list | `getBlockedMessageSenders, blockListMain, messageSenderUser` | yes | Blocked Users table pushed from Privacy screen: avatar + name + phone cell, swipe-to-delete |
| Block / unblock a sender | `setMessageSenderBlockList, blockListMain, canSendMessageToUser` | yes | Action-sheet item on the user profile screen and delete action in the Blocked list |
| Add user to blocked list via contact picker | `setMessageSenderBlockList, searchContacts, getContacts` | yes | Plus button in the Blocked Users nav bar opening the existing contact picker |
| Active sessions list | `getActiveSessions, sessions, session` | yes | Sessions screen: 'current session' header block plus a grouped list of other sessions with app name, device, IP and location subtitle |
| Terminate one session / terminate all other sessions | `terminateSession, terminateAllOtherSessions` | no | Swipe-delete on a session row plus a red 'Terminate All Other Sessions' button row with a UIActionSheet confirm |
| Auto-terminate old sessions after N days | `setInactiveSessionTtl, sessions` | no | Row on Sessions screen showing the current TTL, pushing a radio list (1 week / 1 month / 3 months / 6 months) |
| Connected websites (Telegram Login) | `getConnectedWebsites, connectedWebsites, connectedWebsite` | no | Section under Sessions listing domain + bot + last active, swipe to disconnect, plus 'Disconnect All' |
| Two-step verification status | `getPasswordState, passwordState` | no | Row on Privacy screen with On/Off detail label, pushing the 2SV screen |
| Account self-destruct TTL | `getAccountTtl, setAccountTtl, accountTtl` | yes | Row on Privacy screen with the current period, pushing a radio list (1/3/6/12 months) |
| Delete account | `deleteAccount` | no | Red destructive row at the bottom of Privacy with a UIActionSheet confirm and an optional reason field |
| Default auto-delete timer for new chats | `getDefaultMessageAutoDeleteTime, setDefaultMessageAutoDeleteTime, messageAutoDeleteTime` | no | Row on Privacy screen pushing a radio list (Off / 1 day / 1 week / 1 month) |
| Per-chat auto-delete timer | `setChatMessageAutoDeleteTime` | yes | Row in the chat info screen with a period picker |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Privacy exception lists (Always Allow / Never Allow specific users) | `userPrivacySettingRuleAllowUsers, userPrivacySettingRuleRestrictUsers, userPrivacySettingRuleAllowChatMembers` | yes | Two sub-rows under each privacy setting showing counts, each opening a multi-select contact picker |
| Session detail: allow calls / allow secret chats toggles | `toggleSessionCanAcceptCalls, toggleSessionCanAcceptSecretChats` | no | Pushed session detail screen with two UISwitch rows |
| Unconfirmed session banner and confirm/terminate | `confirmSession, terminateSession, updateUnconfirmedSession` | no | Yellow banner above the chat list with Confirm / Terminate actions |
| Set / change / disable 2-step verification password | `setPassword, getPasswordState, passwordState` | no | Multi-step wizard: enter password, re-enter, hint, recovery email; plus a 'Turn Password Off' red row |
| Recovery email address (get / set / verify code) | `getRecoveryEmailAddress, setRecoveryEmailAddress, checkRecoveryEmailAddressCode` | no | Email entry screen plus a 6-digit code entry screen inside the 2SV flow |
| Password recovery at login (forgot password) | `requestPasswordRecovery, checkRecoveryEmailAddressCode, recoverPassword` | no | 'Forgot password?' link on the existing auth password screen leading to code entry and new-password entry |
| Local passcode lock (app-level PIN) | `` | no | Passcode Lock screen: enable/disable, change passcode, auto-lock interval radio list, plus a full-screen keypad lock overlay on foreground |
| Report a chat or user for spam/abuse | `reportChat, getChatReportOptions, reportChatResultOptionRequired` | no | 'Report' action-sheet item on profile/chat info, then an options list and optional comment field |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Voice/video message privacy (premium-gated) | `userPrivacySettingAllowPrivateVoiceAndVideoNoteMessages, setUserPrivacySettingRules` | yes | Server rejects setting it without an active Telegram Premium subscription (premiumFeature), which we cannot obtain. |
| Read receipts / read date privacy | `getReadDatePrivacySettings, setReadDatePrivacySettings, readDatePrivacySettings` | no | Setting show_read_date to false is premium-only server-side; only reading the current value would work, so the toggle is useless. |
| Restrict new chats from unknown users | `setNewChatPrivacySettings, newChatPrivacySettings, getUserPrivacySettingRules` | no | allow_new_chats_from_unknown_users=false is a premium-gated server restriction; the paid-messages half is Stars-only. |
| Stories block list | `blockListStories, getBlockedMessageSenders, setMessageSenderBlockList` | no | We do not implement stories at all on this client, so a stories-only block list has no surface to attach to. |
| Login email address | `setLoginEmailAddress, checkLoginEmailAddressCode, isLoginEmailAddressRequired` | no | Only changeable when the account already has a login email set on a modern client; unusable entry point here and easy to lock the user out. |
| Temporary password for payments | `createTemporaryPassword, getTemporaryPasswordState, temporaryPasswordState` | no | Only meaningful with the payments UI, which this client does not implement. |
| Sponsored messages toggle | `toggleHasSponsoredMessagesEnabled` | no | Disabling sponsored messages is premium-only and we never render sponsored messages anyway. |
| Autosave gifts / gift privacy | `userPrivacySettingAutosaveGifts, userPrivacySettingAllowUnpaidMessages, setUserPrivacySettingRules` | yes | Belongs to the Stars/gifts economy which this client does not and will not implement. |

## proxies-network
20 capabilities - 15 trivial, 5 design, 0 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Proxy list screen (added proxies, enable/disable) | `getProxies, addedProxies, addedProxy` | no | Grouped table of proxy rows with a checkmark on the enabled one plus a master 'Use proxy' switch; new Proxy Settings screen pushed from TGSettingsViewController |
| Proxy latency ping | `pingProxy` | no | Detail text on each proxy row showing 'checking...' then 'NNN ms' or 'unavailable', refreshed when the list appears |
| Connection state indicator in the title bar | `updateConnectionState, connectionStateWaitingForNetwork, connectionStateConnecting` | yes | Navigation-bar title swapping to 'Connecting...' / 'Updating...' / 'Waiting for network' with a small spinner, on chat list and inside chats |
| Distinct 'Connecting to proxy' state | `connectionStateConnectingToProxy` | yes | Same title-bar indicator with separate wording when a proxy is in use |
| Report actual network type to TDLib | `setNetworkType, networkTypeNone, networkTypeMobile` | no | No UI; an SCNetworkReachability observer in AppDelegate/TGClient pushing the current type on change and on foreground |
| Network usage statistics screen | `getNetworkStatistics, networkStatistics, networkStatisticsEntryFile` | no | Grouped table of sent/received bytes per file type and for calls, split mobile vs WiFi, with a destructive 'Reset statistics' row and a 'since date' footer; next to TGStorageViewController |
| Contribute call traffic to network statistics | `addNetworkStatistics, networkStatisticsEntryCall` | no | No UI; called from TGCall when a voice call ends |
| Open tg://proxy links to add a proxy | `getInternalLinkType, internalLinkTypeProxy, addProxy` | no | Confirmation alert 'Add this proxy?' from a URL-scheme open in AppDelegate or a tapped proxy link in a message |
| Share a proxy as a t.me link | `getInternalLink, internalLinkTypeProxy` | no | Share row or long-press action sheet on a proxy row that copies the generated link to the pasteboard |
| Scan a proxy QR code | `getInternalLinkType, internalLinkTypeProxy, addProxy` | no | Bar button on the proxy list reusing TGQRViewController, then the same add-proxy confirmation |
| Test a proxy against a datacenter before saving | `testProxy` | no | No dedicated screen; the validation step in the add-proxy form |
| Sponsored-by-proxy chat badge | `chatSourceMtprotoProxy` | no | 'Proxy sponsor' caption line on the promoted chat row in the chat list |
| Waiting-for-network banner | `updateConnectionState, connectionStateWaitingForNetwork` | yes | TGSnackbar or a thin bar under the navigation bar reading 'Waiting for network' |
| Connection diagnostics / app config debug screen | `getApplicationConfig, getOption, getLogTags` | no | Hidden debug screen reachable by long-pressing the settings version footer, listing raw key/value rows |
| Data saver master switch | `getAutoDownloadSettingsPresets, setAutoDownloadSettings` | no | Single 'Data Saver' toggle in Data and Storage applying the low preset to every network type |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Add / edit proxy (SOCKS5, HTTP, MTProto) | `addProxy, editProxy, proxy` | no | Form screen with type selector, server, port, username, password or MTProto secret fields and a Save bar button; pushed from the proxy list |
| Auto-download settings per network type | `getAutoDownloadSettingsPresets, setAutoDownloadSettings, autoDownloadSettings` | no | Two sub-screens (Mobile / Wi-Fi) of toggles for photos, videos and other files plus size limits, under Data and Storage |
| Use less data for calls | `setAutoDownloadSettings, autoDownloadSettings` | no | Single toggle row in call settings flipping use_less_data_for_calls |
| Use proxy for calls | `setOption, optionValueBoolean` | yes | Toggle row at the bottom of the proxy list |
| Proxy auto-rotation (pick the fastest reachable proxy) | `getProxies, pingProxy, enableProxy` | no | No new screen; background logic plus a toggle on the proxy list |

## reactions
24 capabilities - 10 trivial, 7 design, 7 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Add / remove emoji reaction on a message | `addMessageReaction, removeMessageReaction, reactionTypeEmoji` | yes | long-press message action sheet with a row of emoji, plus tap-to-toggle on the reaction chip under the bubble; chat message list screen |
| Set the full reaction set on a message at once (multi-reaction) | `setMessageReactions` | no | multi-select emoji sheet honouring max_reaction_count; chat screen |
| Big / animated reaction send flag | `addMessageReaction` | yes | is_big flag on double-tap-to-react gesture; chat screen |
| Per-message available reactions (which emoji the user may use here) | `getMessageAvailableReactions, availableReactions, availableReaction` | no | populates the emoji row in the reaction picker, and shows a disabled state / reason label; chat screen |
| Global default (quick) reaction | `setDefaultReactionType, updateDefaultReactionType, getOption default_reaction` | no | a single settings row 'Quick reaction' opening an emoji chooser; Settings > Stickers/Emoji, plus double-tap gesture in chat |
| Recent reactions list and clearing it | `clearRecentReactions, availableReactions.recent_reactions` | no | 'Clear recent reactions' row with confirmation; Settings |
| Mark all reactions in a chat as read | `readAllChatReactions` | no | tap on the unread-reactions badge, or a chat-list swipe/long-press action |
| Reaction notification settings (source, sound, preview) | `setReactionNotificationSettings, reactionNotificationSettings, reactionNotificationSourceNone` | no | a Reactions section in Notifications settings: two choice rows (messages / stories) with None-Contacts-All, a show-preview toggle, a sound row |
| Moderation: delete another user's reactions | `deleteMessageReactionsFromSender, deleteAllRecentMessageReactionsFromSender, messageProperties.can_delete_reactions` | no | action-sheet items in the reaction list screen (long-press a reactor); reaction list |
| Report a reaction as spam | `reportMessageReactions, messageProperties.can_report_reactions` | no | 'Report' item in the reaction-list action sheet |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Reaction chips under a message bubble with counts and chosen state | `messageReactions, messageReaction, messageInteractionInfo` | yes | new drawn row of rounded count chips inside the bubble layout, highlighted when is_chosen; chat message cell |
| Reaction list — who reacted with what | `getMessageAddedReactions, addedReactions, addedReaction` | no | paged table of avatar + name + emoji, opened from tapping a reaction chip; new modal list screen with per-emoji filter tabs |
| Active emoji reactions catalogue and per-emoji metadata | `getEmojiReaction, emojiReaction, updateActiveEmojiReactions` | no | backs the emoji picker grid; static_icon sticker downloaded and drawn as a small image |
| Unread reactions badge and jump-to-next-reaction | `updateMessageUnreadReactions, updateChatUnreadReactionCount, chat.unread_reaction_count` | no | a small reaction badge button floating above the input bar that scrolls to the next unread reaction; chat screen, plus a count badge in the chat list row |
| Mark all reactions read in a forum topic / direct-messages topic | `readAllForumTopicReactions, readAllDirectMessagesChatTopicReactions` | no | same badge inside a topic screen |
| Chat-level allowed reactions (admin) | `setChatAvailableReactions, chatAvailableReactionsAll, chatAvailableReactionsSome` | no | admin screen: All / Some / Disabled selector, a checklist of emoji and a max-reactions-per-message stepper; group or channel settings |
| Top paid reactors leaderboard on a post | `messageReactions.paid_reactors, paidReactor` | no | small avatar row above the reaction chips on channel posts |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Animated reaction effects (appear/select/activate/around/effect animations) | `emojiReaction, getCustomEmojiReactionAnimations, messageEffectTypeEmojiReaction` | no | All these assets are TGS (gzipped Lottie); there is no Lottie renderer for iOS 6 and a single-core A5 cannot render vector animation at frame rate — static icons only. |
| Custom emoji reactions | `reactionTypeCustomEmoji, getCustomEmojiStickers, availableReactions.allow_custom_emoji` | no | Requires Telegram Premium to send, and the icons are animated custom-emoji stickers (TGS/WEBM) we cannot render; incoming ones can at best be shown as a generic star chip. |
| Paid (star) reactions on channel posts | `reactionTypePaid, addPendingPaidMessageReaction, commitPendingPaidMessageReactions` | no | Sending requires a Telegram Stars balance topped up through in-app purchase, which we cannot perform on a sideloaded iOS 6 build; top paid reactors can only be shown read-only if we choose to. |
| Story reactions | `setStoryReaction, getStoryAvailableReactions, storyAreaTypeSuggestedReaction` | no | There is no story viewer on this client and stories themselves are out of reach on a 4S; the reaction calls are meaningless without it. |
| Live-story / group-call paid reactions | `addPendingLiveStoryReaction, commitPendingLiveStoryReactions, removePendingLiveStoryReactions` | no | Requires live-story group calls and a Stars balance, neither reachable here. |
| Saved Messages reaction tags | `getSavedMessagesTags, setSavedMessagesTagLabel, savedMessagesTag` | no | Tag filtering of Saved Messages is a Telegram Premium feature; without a subscription the tag strip is empty and setting labels fails server-side. |
| Reaction statistics graphs | `messageStatistics, chatStatisticsChannel.message_reaction_graph, storyStatistics` | no | Modern clients render these graphs in a WebView-backed chart component; iOS 6 has only UIWebView and drawing these ourselves is disproportionate — treat as out of scope for reactions. |

## saved-messages
17 capabilities - 6 trivial, 9 design, 2 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Open Saved Messages chat | `getMe, getChatHistory, createPrivateChat` | yes | Row in chat list plus a Saved Messages entry in the main menu/settings; opens the existing chat screen |
| Save (forward) messages to Saved Messages | `forwardMessages` | yes | Action-sheet item on message long-press: 'Save to Saved Messages', targeting savedMessagesChatId |
| Delete a Saved Messages topic / clear its history | `deleteSavedMessagesTopicHistory, deleteSavedMessagesTopicMessagesByDate` | no | Destructive row in the topic long-press action sheet with a confirm sheet |
| Rename a tag (set tag label) | `setSavedMessagesTagLabel, reactionTypeEmoji` | no | Long-press a tag chip -> UIAlertView with a text field on iOS 6 |
| tg://saved deep link handling | `internalLinkTypeSavedMessages, getInternalLinkType, getInternalLink` | no | No UI: URL handler routes to the Saved Messages screen |
| Pin the Saved Messages chat in the chat list | `toggleChatIsPinned` | yes | Existing chat-list swipe/long-press pin action |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Saved Messages topics list (chats-inside-Saved-Messages) | `loadSavedMessagesTopics, updateSavedMessagesTopic, updateSavedMessagesTopicCount` | no | A whole new chat-list-like screen that Saved Messages opens into, with avatar+title+last-message rows per origin author |
| Saved Messages topic history (per-author message stream) | `getSavedMessagesTopicHistory, getSavedMessagesTopicMessageByDate` | no | Reuses the chat screen but paginates through a topic id instead of chat history |
| Pin / unpin Saved Messages topics and reorder pins | `toggleSavedMessagesTopicIsPinned, setPinnedSavedMessagesTopics, premiumLimitTypePinnedSavedMessagesTopicCount` | no | Swipe action or long-press sheet on a topic row in the topics list; reorder via table edit mode |
| Saved Messages tags: list and display | `getSavedMessagesTags, savedMessagesTag, savedMessagesTags` | no | Horizontal tag chip strip pinned under the nav bar in Saved Messages, plus a small tag badge on message bubbles |
| Tag a saved message (add/remove tag reaction) | `addMessageReaction, removeMessageReaction, setMessageReactions` | yes | 'Tag' item on message long-press opening an emoji picker sheet |
| Filter Saved Messages by tag / search within saved | `searchSavedMessages` | no | Tapping a tag chip filters the stream; the existing search bar feeds the query argument |
| Per-topic draft messages | `setChatDraftMessage, messageTopicSavedMessages, draftMessage` | no | Compose bar text restored when reopening a topic; draft preview text on the topic row |
| Date jump / sparse scroll positions inside Saved Messages | `getChatSparseMessagePositions, getSavedMessagesTopicMessageByDate` | no | Fast-scroll date bubble or a 'jump to date' picker |
| Pin a message inside Saved Messages | `pinChatMessage, unpinChatMessage, unpinAllChatMessages` | no | Pinned-message banner at the top of the chat screen plus a long-press action |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Custom-emoji tags | `reactionTypeCustomEmoji, getCustomEmojiStickers` | no | Custom emoji tags require Telegram Premium to set and animated-sticker (TGS/lottie) rendering that a single-core A5 with 512MB cannot afford; plain emoji tags cover the feature. |
| Premium pinned-topic limit raise and premium tag features | `premiumFeatureSavedMessagesTags, premiumLimitTypePinnedSavedMessagesTopicCount, getPremiumLimit` | no | Depends on an active Premium subscription server-side; the client can only surface the limit error. |

## search
36 capabilities - 18 trivial, 13 design, 5 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Global message search | `searchMessages, foundMessages, chatListMain` | yes | results section in the existing dedicated search page (TGSearchViewController) |
| Global search paging (load more) | `searchMessages, foundMessages` | no | infinite-scroll footer cell on the search results table |
| Filtered global search by media type | `searchMessages, searchMessagesFilterPhotoAndVideo, searchMessagesFilterDocument` | no | segmented scope bar above the search results table |
| Search scoped to private/group/channel | `searchMessages, searchMessagesChatTypeFilterPrivate, searchMessagesChatTypeFilterGroup` | no | extra options in the same scope bar / action sheet |
| Local chat list search (chats by title) | `searchChats, searchChatsOnServer, searchChatTypeFilterBot` | no | 'Chats' section at the top of the search results table |
| Public chat / username search | `searchPublicChats, searchPublicChat` | yes | 'Global search' section below local results, same chat cell |
| Contact search | `searchContacts` | no | search bar on the contacts screen and a Contacts section on the search page |
| Search user by phone number | `searchUserByPhoneNumber` | yes | implicit: phone-shaped query yields a single user row |
| Chat member search | `searchChatMembers, chatMembersFilterMembers, chatMembersFilterAdministrators` | no | search bar over the group members list; also feeds mention autocomplete |
| Recent searches (recently found chats) | `getRecentlyFoundChats, searchRecentlyFoundChats, addRecentlyFoundChat` | no | 'Recent' section shown on the empty search page with a Clear button and swipe-to-delete |
| Recently opened chats | `getRecentlyOpenedChats` | no | alternative empty-state section on the search page |
| Public hashtag/cashtag post search | `searchPublicMessagesByTag, foundMessages` | no | results list opened by tapping a #hashtag in a message |
| Searched-for tag history | `getSearchedForTags, removeSearchedForTag, clearSearchedForTags` | no | recent-hashtags rows on the empty hashtag search state |
| Shared media search inside a chat | `searchChatMessages, searchMessagesFilterPhotoAndVideo, searchMessagesFilterDocument` | yes | tabs on the existing shared-media screen with a search field |
| Call log search / missed calls filter | `searchCallMessages` | no | 'Missed' segmented filter on a recent-calls list |
| Outgoing document search (for re-sharing files) | `searchOutgoingDocumentMessages` | no | file picker sheet in the attachment menu |
| Username availability check | `checkChatUsername, checkChatUsernameResultOk, checkChatUsernameResultUsernameOccupied` | no | inline validity label under the username text field in settings/group edit |
| Prefix search over local strings (country picker, language list) | `searchStringsByPrefix, foundPositions` | no | search bar over the country-code and language pickers |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| In-chat message search | `searchChatMessages, foundChatMessages` | yes | search bar over the conversation with prev/next result navigation bar at the bottom |
| In-chat search by sender | `searchChatMessages, messageSenderUser, messageSenderChat` | no | 'from:' sender picker chip inside the in-chat search bar |
| Search by date range | `searchMessages` | no | date range action sheet with UIDatePicker |
| Top / frequently contacted peers | `getTopChats, removeTopChat, topChatCategoryUsers` | no | horizontal avatar strip or a 'People' section on the empty search page |
| Hashtag prefix autocomplete | `searchHashtags, hashtags` | no | autocomplete strip above the keyboard in the composer, plus suggestions in the search field |
| Saved Messages tag search (filter saved messages by reaction tag) | `searchSavedMessages, getSavedMessagesTags, savedMessagesTag` | no | horizontal tag chip bar pinned under the nav bar in Saved Messages |
| Saved Messages topics list and pinning | `getSavedMessagesTopicHistory, toggleSavedMessagesTopicIsPinned, deleteSavedMessagesTopicHistory` | no | a topic list screen inside Saved Messages |
| Jump to date in history (calendar) | `getChatMessageByDate, getChatMessageCalendar, messageCalendar` | no | month-grid calendar modal reachable from in-chat search |
| Media grid scrollbar date positions | `getChatSparseMessagePositions, messagePositions` | no | fast-scroll date bubble on the shared media grid |
| Downloaded files search | `searchFileDownloads, foundFileDownloads` | no | 'Downloads' section on the search page |
| Sticker / sticker set / emoji search | `searchStickers, searchStickerSet, searchInstalledStickerSets` | no | search field on the sticker panel and the sticker-set settings list |
| Live location message search in a chat | `searchChatRecentLocationMessages` | no | 'live locations' banner and list in a chat |
| Quote position search (locating a quoted fragment) | `searchQuote, foundPosition` | no | none directly; supports reply-with-quote highlighting |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Secret chat search | `searchSecretMessages` | no | Secret chats need active local E2E sessions and per-device key handling that this client does not implement, so the search has nothing to search. |
| Public post search (paid global post search) | `searchPublicPosts, foundPublicPosts` | no | Requires spending Telegram Stars (star_count) per query, i.e. a paid balance and payments stack we cannot reach. |
| Story search by tag / location / venue | `searchPublicStoriesByTag, searchPublicStoriesByLocation, searchPublicStoriesByVenue` | no | Stories require a full-screen video story viewer and mostly H.264 story playback/upload that a 512MB single-core 4S cannot sustain; no story UI exists at all. |
| Sponsored chat search results | `getSearchSponsoredChats, sponsoredChats` | no | Ad surface with view/click reporting obligations; no user value in a legacy client and best left out. |
| Nearby / location-based public chat discovery | `searchPublicChats, publicChatTypeIsLocationBased` | no | The dedicated searchChatsNearby method was removed from the schema and the server feature was discontinued. |

## secret-chats
27 capabilities - 19 trivial, 7 design, 1 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Enable secret chat support in TDLib | `setTdlibParameters, use_secret_chats` | no | no UI; one parameter flip in TGClient setTdlibParameters (currently use_secret_chats:@NO) |
| Start a new secret chat with a user | `createNewSecretChat, chatTypeSecret` | no | 'New Secret Chat' row in the contacts picker / an action-sheet button on TGProfileViewController, then push TGChatViewController on the returned chat |
| Open/rejoin an existing secret chat by secret_chat_id | `createSecretChat, chatTypeSecret` | no | internal only — resolving chatTypeSecret.secret_chat_id from updates or deep links into a Chat object |
| Close/terminate a secret chat | `closeSecretChat, deleteChatHistory` | no | destructive row in the secret-chat profile screen and a swipe/long-press action in TGChatListViewController |
| Per-chat self-destruct timer (TTL) picker | `setChatMessageAutoDeleteTime, updateChatMessageAutoDeleteTime, chat.message_auto_delete_time` | yes | TGActionSheet with the classic ladder (Off, 1s, 2s, 5s, 10s, 30s, 1m, 1h, 1d, 1w) opened from the clock button in the chat nav bar / input bar |
| TTL-change service message in the timeline | `messageChatSetMessageAutoDeleteTime` | no | centered service-message row in TGChatViewController ('X set the self-destruct timer to 5 seconds') |
| Global default auto-delete timer | `getDefaultMessageAutoDeleteTime, setDefaultMessageAutoDeleteTime, messageAutoDeleteTime` | no | Privacy section row in TGSettingsViewController with the same duration action sheet |
| Mark self-destructing content as opened (starts the timer) | `openMessageContent` | no | called when a photo/voice/video-note bubble is tapped or a secret media viewer opens |
| Send self-destructing photo | `inputMessagePhoto, messageSelfDestructTypeTimer, messageSelfDestructTypeImmediately` | yes | a timer toggle in the photo-send confirmation, adding self_destruct_type to the existing inputMessagePhoto dictionary |
| Send self-destructing voice note / video note | `inputMessageVoiceNote, inputMessageVideoNote, messageSelfDestructTypeImmediately` | yes | long-press option on the record button, or automatic when the chat TTL is set |
| Expired media placeholders | `messageExpiredPhoto, messageExpiredVideo, messageExpiredVideoNote` | yes | italic grey placeholder bubble in ChatViewCell |
| Incoming screenshot notification | `messageScreenshotTaken` | yes | centered service row 'X took a screenshot!' |
| New-secret-chat notification handling | `notificationTypeNewSecretChat, notificationGroupTypeSecretChat` | no | local notification text and a chat-list row highlight when an incoming secret chat request arrives |
| Allow/deny this session to accept secret chats | `toggleSessionCanAcceptSecretChats, session.can_accept_secret_chats` | no | switch row in the session detail view of TGSessionsViewController |
| Account self-destruct period | `getAccountTtl, setAccountTtl, accountTtl` | yes | Privacy settings row with 1/3/6/12-month action sheet |
| Secret-chat capability gating by peer layer | `secretChat.layer` | no | hides reply/rich-entity/edit affordances when the partner's layer is too low |
| Secret-chat send restrictions | `inputMessagePoll, inputMessageForwarded, messageProperties.can_be_copied_to_secret_chat` | no | grey out polls/checklists/story-forwards/quoted replies in the attachment sheet and forward picker for chatTypeSecret targets |
| No message editing or scheduling in secret chats | `editMessageText, messageSendOptions.scheduling_state, deleteMessages` | yes | hide Edit and Schedule from the message context menu for secret chats; keep Delete with revoke:true |
| Secret-chat file handling | `fileTypeSecret, fileTypeSecretThumbnail, fileTypeSelfDestructingPhoto` | yes | none — download/cache path must not reuse remote file ids across secret chats and must skip these types in TGStorageViewController's reusable cache stats |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Secret chat state tracking (pending / ready / closed) | `getSecretChat, updateSecretChat, secretChat` | no | a per-chat state cache in TGClient plus a status line in the chat header ('waiting for X to come online', 'cancelled') and input-bar disabling |
| Secret-chat visual identity (green lock, green title, green chat-list row) | `chatTypeSecret, secretChat` | no | lock glyph plus green title colour in TGChatListViewController cells, chat nav-bar title, and the profile header |
| Encryption key visualization / key hash comparison | `secretChat, getSecretChat` | no | a dedicated 'Encryption Key' screen drawing the 36-byte key_hash as a 12x12 four-colour pixel grid plus explanatory text |
| Self-destruct countdown on messages | `message.self_destruct_type, message.self_destruct_in, messageSelfDestructTypeTimer` | no | burning-fuse / shrinking-clock indicator inside ChatViewCell plus a local timer that removes the row when it hits zero |
| Send self-destructing video | `inputMessageVideo, messageSelfDestructTypeTimer` | yes | same timer toggle on the video-send path |
| Blurred tap-to-view secret media (is_secret) | `messagePhoto.is_secret, messageVideo.is_secret, messageVideoNote.is_secret` | no | blurred/obscured thumbnail with a 'Tap to view' overlay that reveals full-screen only while held |
| Local database encryption key | `setDatabaseEncryptionKey, checkDatabaseEncryptionKey, setTdlibParameters.database_encryption_key` | no | none visible; a keychain-backed random key generated on first launch |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Outgoing screenshot detection | `messageScreenshotTaken` | no | UIApplicationUserDidTakeScreenshotNotification is iOS 7+, and current TDLib exposes no sendChatScreenshotTakenNotification function in the schema, so we can neither detect nor report it. |

## stars-payments
31 capabilities - 9 trivial, 15 design, 7 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Star balance display | `updateOwnedStarCount, starAmount, getOption` | no | A value label on a Settings row and a header label on the Stars screen; fed by a cached balance property on TGClient |
| Saved payment credentials | `savedCredentials, inputCredentialsSaved, deleteSavedCredentials` | no | Saved-card row inside the checkout screen plus a 'Clear saved payment info' destructive row in Settings/Privacy |
| Received gifts on a profile | `getReceivedGifts, receivedGift, getReceivedGift` | yes | Gifts section on TGProfileViewController: list rows with sticker, sender and star value; long-press actions for hide/pin/convert-to-stars |
| Gift notifications for channels | `toggleChatGiftNotifications` | no | Single switch row in a channel's gift section |
| Gift transfer and original-details drop | `transferGift, dropGiftOriginalDetails, upgradedGiftOriginTransfer` | no | Action sheet on a unique gift plus a recipient picker reusing TGForwardPicker |
| Gift collections | `getGiftCollections, createGiftCollection, deleteGiftCollection` | no | Tab strip above the profile gifts list plus an edit screen with rename/delete rows |
| Paid messages (charge per incoming DM) | `setChatPaidMessageStarCount, getPaidMessageRevenue, allowUnpaidMessagesFromUser` | no | A star-price row in Privacy settings, an 'allow free messages' row on a profile, and a confirm-cost alert before sending into a paid chat |
| Star payment refunds | `refundStarPayment` | no | Refund row on a star transaction detail sheet |
| Premium gift codes | `checkPremiumGiftCode, applyPremiumGiftCode, premiumGiftCodeInfo` | no | Gift-code link handler showing an info alert with an Apply button |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Star transaction history | `getStarTransactions, starTransactions, starTransaction` | no | New pushed table screen with balance header, paged rows (title, date, +/- star amount), and an incoming/outgoing segmented filter |
| Star transaction detail sheet | `starTransaction, starTransactionTypeBotInvoicePurchase, starTransactionTypeUserDeposit` | no | Modal detail view over the transactions list showing product photo, peer, transaction id and amount |
| Bot invoice message rendering | `messageInvoice, invoice, productInfo` | yes | Chat bubble showing product title, description, photo and a Pay button; already summarised as text in TGClient message preview |
| Payment form for Stars-priced invoices | `getPaymentForm, paymentFormTypeStars, sendPaymentForm` | no | Confirmation sheet: product info, star price, Confirm button, then success toast |
| Card payment form (regular provider) | `getPaymentForm, paymentFormTypeRegular, validateOrderInfo` | no | Multi-step checkout: card entry form, shipping address form, shipping option picker, tip picker, final confirm screen |
| Payment receipt view | `getPaymentReceipt, paymentReceipt, paymentReceiptTypeRegular` | no | Read-only receipt screen reached by tapping the 'payment successful' service message |
| Star gift catalogue and sending a gift | `getAvailableGifts, availableGift, gift` | no | Gift picker grid opened from a profile, with a message field, anonymity toggle and confirm; plus 'who can gift me' toggles in Settings |
| Unique gift upgrade | `getGiftUpgradePreview, getUpgradedGiftVariants, upgradeGift` | no | Upgrade preview sheet that cycles model/symbol/backdrop, plus a full unique-gift detail card with gradient backdrop and attribute rows |
| Gift resale marketplace | `searchGiftsForResale, setGiftResalePrice, sendResoldGift` | no | Browsable marketplace grid with model/symbol/backdrop attribute filters and a price-setting sheet |
| Gift crafting | `getGiftsForCrafting, craftGift, giftsForCrafting` | no | Multi-select gift picker showing per-attribute persistence probabilities and a result reveal |
| Gift auctions | `getGiftAuctionState, openGiftAuction, closeGiftAuction` | no | Live auction screen with countdown, round position and bid entry |
| Paid message reactions (star reactions) | `addPendingPaidMessageReaction, commitPendingPaidMessageReactions, removePendingPaidMessageReactions` | no | Star reaction button on channel post bubbles with an undo window; our TGSnackbar already provides the undo banner |
| Paid media (locked media purchase) | `messagePaidMedia, paidMediaPreview, paidMediaPhoto` | yes | Blurred minithumbnail bubble with a 'Unlock for N stars' button, unlocking into the normal media bubble |
| Star subscriptions management | `getStarSubscriptions, starSubscription, starSubscriptionPricing` | no | Subscriptions list screen with per-row cancel/renew action sheet |
| Gifting Premium with Stars | `giftPremiumWithStars, getPremiumGiftPaymentOptions, messageGiftedPremium` | no | Duration picker sheet from a profile with a star price per option |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Buying Stars via in-app purchase | `getStarPaymentOptions, starPaymentOption, canPurchaseFromStore` | no | Requires StoreKit products registered to Telegram's App Store account; a sideloaded legacy build has no valid product identifiers and cannot complete an Apple IAP, and the alternate Fragment/web top-up path needs a modern browser session. |
| Gifting Stars to a user | `getStarGiftPaymentOptions, storePaymentPurposeGiftedStars, messageGiftedStars` | no | Same StoreKit dependency as buying Stars; only the incoming messageGiftedStars service message can be rendered. |
| Apple Pay checkout | `inputCredentialsApplePay, paymentOption` | no | PassKit payment requests require iOS 8 and Secure Element hardware the iPhone 4S lacks. |
| Star revenue statistics and withdrawal | `getStarRevenueStatistics, starRevenueStatus, getStarWithdrawalUrl` | no | Withdrawal requires the 2FA password check plus an external Fragment web session; the returned URL cannot be completed inside a UIWebView on iOS 6 and only applies to bot/channel owners. |
| Star and Premium giveaways | `getStarGiveawayPaymentOptions, getPremiumGiveawayPaymentOptions, launchPrepaidGiveaway` | no | Creating a giveaway needs the App Store purchase path we cannot use; only launchPrepaidGiveaway would work and it requires an already-prepaid boost, so the feature is not usable end to end here. |
| Creating invoice links (bot/business side) | `createInvoiceLink, inputMessageInvoice, answerPreCheckoutQuery` | no | These are bot-account APIs; a user session cannot call them meaningfully. |
| Business account star balance and gift settings | `getBusinessAccountStarAmount, transferBusinessAccountStars, setBusinessAccountGiftSettings` | no | Requires an active business connection granted to a bot; no path to it from this client. |

## stickers-emoji
31 capabilities - 12 trivial, 12 design, 7 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Recent stickers strip | `getRecentStickers, addRecentSticker, removeRecentSticker` | yes | horizontal scroll row of sticker thumbnails at the top of the sticker keyboard panel above the chat input |
| Send a sticker to a chat | `inputMessageSticker, sendMessage, messageSticker` | yes | tap on any sticker cell in the sticker panel; rendered in the message list as a transparent bubble-less image |
| Installed sticker sets list | `getInstalledStickerSets, stickerTypeRegular, stickerSetInfo` | no | grouped UITableView of sets with cover thumbnail, title and sticker count — a new 'Stickers' screen under Settings |
| Install / uninstall / archive a sticker set | `changeStickerSet` | no | Add/Remove button in the set preview screen plus swipe-to-delete on the installed-sets table row |
| Reorder installed sticker sets | `reorderInstalledStickerSets` | no | UITableView editing mode with reorder controls on the Stickers settings screen |
| Archived sticker sets | `getArchivedStickerSets, changeStickerSet` | no | 'Archived Stickers' table pushed from the Stickers settings screen, each row restorable |
| Favourite stickers | `getFavoriteStickers, addFavoriteSticker, removeFavoriteSticker` | no | a starred first tab in the sticker panel plus 'Add to Favorites' in the long-press action sheet on a sticker |
| Search sticker sets (installed and global) | `searchInstalledStickerSets, searchStickerSets` | no | UISearchBar over the Stickers settings table, results as the same set rows |
| Emoji suggestion by typed keyword (:smile) | `searchEmojis, getKeywordEmojis, emojiKeywords` | no | a thin horizontal suggestion bar above the chat input, same shape as the existing mention/hashtag suggestion strip |
| Static WEBP sticker rendering | `stickerFormatWebp, sticker, downloadFile` | yes | sticker image in bubbles, grids and set covers |
| Attached sticker sets on a photo/video | `getAttachedStickerSets` | no | a 'Stickers' button in the media viewer that opens a set list sheet |
| Sticker set as group sticker pack | `setSupergroupStickerSet, setSupergroupCustomEmojiStickerSet, supergroupFullInfo.sticker_set_id` | no | a row in group admin settings opening a set-name entry field |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Trending / featured sticker sets with unread badge | `getTrendingStickerSets, viewTrendingStickerSets, updateTrendingStickerSets` | no | 'Trending' tab inside the sticker panel and a badged row in Stickers settings; each entry shows up to 5 cover stickers and an Add button |
| Sticker set preview / open by name from t.me link | `getStickerSet, searchStickerSet, internalLinkTypeStickerSet` | no | modal sheet-style set preview: grid of all stickers in the set with title bar and a full-width Add Stickers button at the bottom |
| Sticker keyboard panel (set tab bar + grid) | `getInstalledStickerSets, getStickerSet, getRecentStickers` | no | input-accessory panel replacing the keyboard, with a bottom tab strip of set covers and a paged/scrolling sticker grid — the central new UI of this area |
| Search stickers by emoji / query | `searchStickers, getStickers, getAllStickerEmojis` | no | search field at the top of the sticker panel; results fill the same grid |
| Sticker suggestion for a lone typed emoji | `searchStickers, getStickers, getOption("is_sticker_suggestion_enabled")` | no | popup strip of matching stickers above the input when the composed text is a single emoji |
| Emoji categories / greeting stickers | `getEmojiCategories, emojiCategoryTypeDefault, emojiCategoryTypeRegularStickers` | no | category icon row inside the emoji keyboard; greeting stickers shown in an empty chat |
| Emoji keyboard with recent/sections | `getEmojiCategories, searchEmojis` | no | tabbed emoji picker panel (Recent, Smileys, Animals, ...) sharing the same input-accessory container as the sticker panel |
| Animated (.tgs) sticker playback | `stickerFormatTgs, sticker, downloadFile` | yes | in-bubble playing sticker in the message list and in the sticker grid |
| Custom emoji in message text | `textEntityTypeCustomEmoji, getCustomEmojiStickers, stickerFullTypeCustomEmoji` | no | inline images substituted into message text in the chat bubble and in chat-list previews |
| Sticker long-press preview | `getStickerSet, sticker` | no | enlarged floating sticker overlay while the finger is held down, with 'view pack' and favourite actions on release |
| Animated emoji in message (single-emoji big animation) | `getAnimatedEmoji, messageAnimatedEmoji, clickAnimatedEmojiMessage` | yes | oversized animated emoji instead of a text bubble when the message is one emoji; tap triggers the click animation |
| Sticker outline placeholder | `getStickerOutline, getStickerOutlineSvgPath, outline` | no | grey vector silhouette drawn while a sticker file downloads |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Video (WEBM/VP9) stickers | `stickerFormatWebm, thumbnailFormatWebm` | no | iOS 6 AVFoundation cannot decode VP9-in-WEBM and the A5 has no hardware path for it; only the static WEBP/PNG thumbnail can be shown, so treat animation as unavailable and fall back to the thumbnail. |
| Custom emoji sticker sets picker (send custom emoji) | `getInstalledStickerSets, stickerTypeCustomEmoji, getCustomEmojiStickers` | no | Sending custom emoji requires an active Telegram Premium subscription; without it the server rejects the message, so only read-side rendering is worth building. |
| Emoji status on own profile / other users | `setEmojiStatus, getDefaultEmojiStatuses, getThemedEmojiStatuses` | no | Setting an emoji status is Premium-only; displaying someone else's status is just a custom-emoji glyph and folds into the custom-emoji rendering feature rather than standing alone. |
| Create / edit own sticker sets | `uploadStickerFile, createNewStickerSet, addStickerToSet` | no | Real users do this through @stickers bot, and the flow needs image processing plus a multi-screen editor that is far out of proportion to its value on a 4S; deliberately out of scope. |
| Emoji suggestions URL (animated emoji suggestion data) | `getEmojiSuggestionsUrl` | no | The returned URL is meant to be opened in a modern web view; iOS 6 has only UIWebView and the page relies on current JS, so it cannot be usefully rendered. |
| Mask stickers | `stickerTypeMask, stickerFullTypeMask, maskPosition` | no | Requires a photo editor with face detection and interactive mask placement; no such editor exists in our client and it is not worth building for a 4S. |
| Premium stickers and premium sticker examples | `getPremiumStickers, getPremiumStickerExamples, getPremiumInfoSticker` | no | Requires an active Premium subscription for the effect to play, and the promo surfaces are pure upsell UI we have no reason to port. |

## storage-cache
22 capabilities - 15 trivial, 6 design, 1 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Fast storage overview (total size + file count) | `getStorageStatisticsFast, storageStatisticsFast` | yes | Header label with total cache size on the existing Storage and cache screen (TGStorageViewController) |
| Database / language pack / log size breakdown | `getStorageStatisticsFast, storageStatisticsFast` | yes | Three extra static value rows in a 'Local database' section of the storage screen |
| Exact storage usage by file type | `getStorageStatistics, storageStatistics, storageStatisticsByFileType` | no | Per-category size labels on the existing three clear rows (Photos / Video / Documents) of the storage screen |
| Clear cache by file-type category | `optimizeStorage, storageStatistics` | yes | Existing rows + confirm action sheet on the storage screen |
| Clear entire cache | `optimizeStorage` | yes | Destructive 'Clear everything' row with confirmation on the storage screen |
| Keep media for (cache TTL) setting | `optimizeStorage` | no | Action sheet picking 3 days / 1 week / 1 month / forever, stored in NSUserDefaults, applied on launch via optimizeStorage ttl: |
| Maximum cache size setting | `optimizeStorage` | no | Action sheet picking 5 GB / 16 GB / 32 GB / No limit, persisted locally, applied via optimizeStorage size: |
| Database statistics (debug) | `getDatabaseStatistics, databaseStatistics` | no | A monospaced scrollable text view behind a debug row on the storage screen |
| Delete a single cached file | `deleteFile` | no | 'Delete from cache' entry in the media/document long-press action sheet in a chat |
| Add file from a message to the download list | `addFileToDownloads, removeFileFromDownloads` | no | 'Save to downloads' entry in the message action sheet |
| Report network type to TDLib for correct stats and auto-download | `setNetworkType, networkTypeWiFi, networkTypeMobile` | no | No UI; reachability observer in AppDelegate/TGClient |
| Suggested filename / MIME type helpers for saving files | `getSuggestedFileName, getFileMimeType, cleanFileName` | no | Used silently when exporting a document via the share sheet |
| Native data-and-storage settings deep links | `settingsSectionDataAndStorage, getInternalLink, internalLinkTypeSettings` | no | tg://settings/storage links opening our storage screen |
| Automatic background cache trimming on low disk | `optimizeStorage, getStorageStatisticsFast` | yes | No UI; runs on didReceiveMemoryWarning / app launch, optional snackbar afterwards |
| Per-chat 'Clear cache' from chat profile | `getStorageStatistics, optimizeStorage` | no | A 'Clear cache (N MB)' row in TGProfileViewController for a chat |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Storage usage by chat (top offenders list) | `getStorageStatistics, storageStatisticsByChat, optimizeStorage` | no | New scrolling list of chats sorted by cache size with avatar, title, size, and per-chat clear action |
| Immunity delay / exclude chats from cleanup | `optimizeStorage` | no | Multi-select chat picker feeding exclude_chat_ids, plus a toggle for recently-used immunity |
| Download / cancel download of a file | `downloadFile, cancelDownloadFile, getFile` | yes | Progress ring on media bubbles; tap to cancel |
| Downloads manager (list of active/paused/completed downloads) | `searchFileDownloads, foundFileDownloads, fileDownload` | no | New Downloads screen reachable from search or settings: rows with filename, progress bar, pause/resume, swipe-to-remove, plus a pause-all button |
| Auto-download settings (photos/video/files, per network type) | `getAutoDownloadSettingsPresets, setAutoDownloadSettings, autoDownloadSettings` | no | Three sub-screens (Using Wi-Fi / Using mobile data / Roaming) each with toggles and size sliders, under Data and Storage |
| Network usage statistics | `getNetworkStatistics, networkStatistics, networkStatisticsEntryFile` | no | 'Network usage' screen with sent/received totals grouped by media type and by Wi-Fi vs mobile, plus a reset row |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Partial download prefix size (streaming readiness) | `getFileDownloadedPrefixSize, readFilePart` | no | Only useful for streaming playback; the 4S has no practical way to stream-decode video and our player requires a complete local file, so this buys nothing. |

## stories
40 capabilities - 17 trivial, 17 design, 6 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Marking stories read / unread ring state | `openStory, closeStory, chatActiveStories` | no | no UI of its own; drives ring colour in the tray and avatar rings on profiles |
| Story caption with entities | `formattedText, story.caption, premiumLimitTypeStoryCaptionLength` | no | caption label overlaid at the bottom of the viewer, expandable on tap |
| Delete own story | `deleteStory` | no | action sheet item in the viewer / my-stories list |
| Story privacy settings (Everyone / Contacts / Close Friends / Selected) | `setStoryPrivacySettings, storyPrivacySettingsEveryone, storyPrivacySettingsContacts` | no | grouped table with four radio rows plus an exception contact picker; reachable from the composer and from the viewer action sheet |
| Close Friends list | `setCloseFriends, getCloseFriends, user.is_close_friend` | no | contact multi-select screen under Privacy settings |
| Hide stories from a user (stories block list) | `setMessageSenderBlockList, blockListStories, getBlockedMessageSenders` | no | action-sheet item in the viewer plus a "Hidden" list in Privacy settings |
| Archive a poster's stories (move between main and archive list) | `setChatActiveStoriesList, storyListArchive, chatActiveStories.can_be_archived` | no | long-press menu on a tray avatar plus an Archived Stories screen |
| Story view/forward/reaction counters | `storyInteractionInfo` | no | eye icon plus counts in the viewer footer for own stories |
| Report a story | `reportStory, reportStoryResultOk, reportStoryResultOptionRequired` | no | action sheet leading into the same multi-step report option list we need for messages |
| Story notification settings (mute stories per chat / scope) | `setChatNotificationSettings, chatNotificationSettings.mute_stories, chatNotificationSettings.show_story_poster` | no | toggles in the chat notifications screen and a global Stories section in Notification settings |
| Story reaction notifications | `setReactionNotificationSettings, reactionNotificationSettings.story_reaction_source` | no | segmented row (All / Contacts / None) in Notification settings |
| Story deep links | `internalLinkTypeStory, internalLinkTypeStoryAlbum, internalLinkTypeNewStory` | no | no UI; URL handling that resolves a username plus story id and opens the viewer |
| Can-post gating and limit feedback | `canPostStory, canPostStoryResultOk, canPostStoryResultPremiumNeeded` | no | alert text shown before opening the composer |
| Choosing which chat to post as | `getChatsToPostStories, chatAdministratorRights.can_post_stories` | no | chat picker row at the top of the composer |
| Channel story admin rights | `setChatMemberStatus, chatAdministratorRights.can_post_stories, chatAdministratorRights.can_edit_stories` | no | three extra switch rows on the admin-rights screen |
| Story auto-download preloading | `setAutoDownloadSettings, autoDownloadSettings.preload_stories` | no | switch row in Data and Storage settings |
| Story file types in storage cleanup | `optimizeStorage, fileTypePhotoStory, fileTypeVideoStory` | yes | existing Storage Usage screen; add story file types to the clear list |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Active stories list (story tray) | `loadActiveStories, storyListMain, storyListArchive` | no | horizontal avatar-ring strip pinned above the chat list on the Dialogs screen, plus a model that keeps chatActiveStories in memory |
| Story viewer (photo stories) | `getStory, openStory, closeStory` | no | full-screen modal viewer with segmented progress bar, tap-to-advance, caption overlay, poster header; pushed from the tray |
| Video story playback | `getStory, storyContentVideo, storyVideo` | no | AVPlayer layer inside the story viewer |
| Story reactions (quick reaction + picker) | `setStoryReaction, getStoryAvailableReactions` | no | heart button in the story viewer footer and a small reaction strip on long-press |
| Reply to a story from the viewer | `inputMessageReplyToStory, sendMessage, messageReplyToStory` | no | text field pinned at the bottom of the story viewer, sends into the poster's private chat |
| Story shared as a chat message bubble | `messageStory, inputMessageStory, linkPreviewTypeStory` | yes | new message cell type in the chat history plus a share sheet entry |
| Forward / repost a story | `postStory, storyFullId, storyRepostInfo` | no | share action sheet in the viewer; repost reuses the post composer |
| Post a photo story | `postStory, inputStoryContentPhoto, canPostStory` | no | camera/library picker then a full-screen composer with caption field, privacy row and Post button |
| Edit own story (caption / content) | `editStory, editStoryCover, story.can_be_edited` | no | reopens the post composer prefilled |
| My stories archive (all my expired stories) | `getChatArchivedStories, stories` | no | grid or plain list of thumbnails on a My Stories screen in Settings |
| Stories saved to profile page | `getChatPostedToChatPageStories, toggleStoryIsPostedToChatPage, story.is_posted_to_chat_page` | no | a Stories section on the user/channel profile screen plus a Save-to-Profile toggle in the viewer sheet |
| Pinned stories on profile | `setChatPinnedStories, stories.pinned_story_ids, supergroupFullInfo.has_pinned_stories` | no | multi-select mode over the profile stories grid |
| Story viewers list (interactions) | `getStoryInteractions, getChatStoryInteractions, storyInteraction` | no | bottom sheet or pushed table of avatars with reaction badges, opened from the eye-count in the viewer footer |
| Story albums (create, rename, reorder, delete) | `getChatStoryAlbums, createStoryAlbum, setStoryAlbumName` | no | tabs or a segmented header over the profile stories grid plus an editable album list |
| Story album contents management | `getStoryAlbumStories, addStoryAlbumStories, removeStoryAlbumStories` | no | multi-select over the archive grid with an Add to Album action sheet |
| Story interactive areas (location, venue, link, message, weather, gift, suggested reaction) | `storyArea, storyAreaPosition, storyAreaTypeLocation` | no | tappable overlay rectangles positioned by percentage over the story image in the viewer |
| Search public stories by tag / location / venue | `searchPublicStoriesByTag, searchPublicStoriesByLocation, searchPublicStoriesByVenue` | no | results grid reached by tapping a hashtag or a location area |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Post a video story | `postStory, inputStoryContentVideo, editStoryCover` | no | A 4S can capture 1080p but the client must transcode/trim to the story profile; no usable trimming stack on iOS 6 within 512MB, and uploads of that size are impractical. Photo stories only. |
| Live stories (RTMP / group-call based) | `startLiveStory, storyContentLive, joinLiveStory` | no | Requires the group-call/WebRTC stack and real-time video decode; not achievable on iOS 6 / A5 in this client. |
| Stealth mode | `activateStoryStealthMode, updateStoryStealthMode, premiumStoryFeatureStealthMode` | no | Premium-only server side; the call exists but returns an error without a subscription. |
| Custom story expiration period | `postStory, premiumStoryFeatureCustomExpirationDuration` | no | active_period other than 86400 requires Premium; keep the composer hard-coded to 24h. |
| Story statistics | `getStoryStatistics, storyStatistics, chatStatisticsObjectTypeStory` | no | Returns StatisticalGraph JSON meant for a charting webview; no WKWebView on iOS 6 and no charting stack here. |
| Business account stories (edit/delete via bot connection) | `editBusinessStory, deleteBusinessStory, businessBotRights.can_manage_stories` | no | Requires a business connection and a connected bot; irrelevant to a personal legacy client. |

## translation-language
20 capabilities - 11 trivial, 5 design, 4 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Translate a single message | `translateMessageText, formattedText` | no | "Translate" entry in the existing message long-press TGActionSheet in TGChatViewController, result shown in a TGAlertView or an inline expanded bubble |
| Translate arbitrary text (input field, bios, captions) | `translateText` | no | Optional "Translate" action on selected text / composer, result in TGAlertView |
| Translation tone selection (formal / neutral / casual) | `translateText, translateMessageText` | no | Extra TGActionSheet with three tone options before translating, or a settings default |
| Target-language picker for translation | `getLocalizationTargetInfo, languagePackInfo, setOption` | no | Grouped table of languages pushed from Settings and from the translate sheet; stores chosen code in NSUserDefaults |
| Show Translate Button setting | `toggleChatIsTranslatable` | no | UISwitch row in a new Language section of TGSettingsViewController |
| Do Not Translate language list | `getLocalizationTargetInfo` | no | Multi-select checkmark table pushed from the Language settings section, stored locally |
| Rate a speech transcription | `rateSpeechRecognition` | no | Two-option action sheet (Good / Bad) after a transcript is shown |
| Speech recognition free-trial counter | `updateSpeechRecognitionTrial` | no | Footer text under the transcript or an alert when the weekly quota is exhausted |
| Interface language list and switching | `getLocalizationTargetInfo, getLanguagePackInfo, setOption` | no | "Language" row in TGSettingsViewController pushing a checkmark table of installed/official packs; setOption "language_pack_id" applies |
| Language pack synchronisation and local database path | `synchronizeLanguagePack, getLanguagePackString` | no | Invisible; a pull-to-refresh or automatic call after choosing a language |
| Language pack deep links (t.me/setlanguage) | `internalLinkTypeLanguagePack, getLanguagePackInfo, addCustomServerLanguagePack` | no | Confirmation TGAlertView on tapping such a link, then apply |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Inline translated-text bubble under original message | `translateMessageText` | no | ChatViewCell gains a second text block plus a "Show original"/"Translate" footer row, with per-message translated state cached |
| Per-chat "Translate this chat" bar | `toggleChatIsTranslatable, updateChatIsTranslatable, translateMessageText` | no | A dismissible bar under the chat navigation bar in TGChatViewController plus batch translation of visible messages |
| Speech recognition of voice notes | `recognizeSpeech, speechRecognitionResultPending, speechRecognitionResultText` | no | Small transcribe glyph on the voice-note bubble; transcript text appended inside the cell, updated as pending -> text |
| Speech recognition of video notes | `recognizeSpeech, videoNote` | no | Same transcribe affordance on the round video-note cell |
| Applying language pack strings to our own UI | `getLanguagePackStrings, getLanguagePackString, updateLanguagePackStrings` | no | No screen: a TGLang lookup layer replacing every hardcoded literal across all view controllers |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Custom / translator-platform language packs | `setCustomLanguagePack, editCustomLanguagePackInfo, setCustomLanguagePackString` | no | An in-app translation editor over thousands of keys is unusable on a 3.5-inch 512MB device and the real client sends users to translations.telegram.org in a browser; no value here. |
| RTL language support | `languagePackInfo` | no | iOS 6 has no semantic-direction layout attributes and we are frame-based only, so mirroring would mean hand-flipping every frame in the app; not worth it and the 2014 client did not do it either. |
| Channel automatic translation for viewers | `toggleSupergroupHasAutomaticTranslation, chatEventAutomaticTranslationToggled, chatBoostLevelFeatures` | no | Only meaningful for channel owners whose channel has the required boost level; we have no channel-admin screens and the payoff is nil for this client. |
| Premium real-time chat translation upsell | `premiumFeatureRealTimeChatTranslation` | no | Needs an active Telegram Premium subscription and an in-app purchase flow that iOS 6 StoreKit here cannot complete; surface the error instead. |

## user-status
24 capabilities - 11 trivial, 7 design, 6 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Last seen / online text for a user | `userStatusOnline, userStatusOffline, userStatusRecently` | yes | subtitle label in chat navigation bar, chat list row and profile header |
| Live status updates via updateUserStatus | `updateUserStatus, updateUser` | yes | no new UI; notification-driven refresh of existing labels |
| Relative 'last seen' time formatting (today/yesterday/date) | `userStatusOffline` | yes | same subtitle label; formatting-only |
| 'Last seen recently' hidden-because-you-hid-yours hint | `userStatusRecently, userStatusLastWeek, userStatusLastMonth` | yes | alert or inline note when tapping the status label |
| Last Seen & Online privacy setting | `userPrivacySettingShowStatus, getUserPrivacySettingRules, setUserPrivacySettingRules` | yes | Everybody/My Contacts/Nobody selection table in Settings > Privacy |
| Other status-adjacent privacy toggles (profile photo, phone, bio, calls, invites) | `userPrivacySettingShowProfilePhoto, userPrivacySettingShowPhoneNumber, userPrivacySettingShowBio` | yes | additional rows in the same Privacy table |
| Mark self online/offline on app foreground/background | `setOption, optionValueBoolean` | yes | none, lifecycle glue in app delegate |
| openChat/closeChat to receive fine-grained status and member counts | `openChat, closeChat` | no | none, controller lifecycle glue |
| 'N members, M online' group header subtitle | `updateChatOnlineMemberCount, getBasicGroupFullInfo, getSupergroupFullInfo` | no | navigation bar subtitle in group chats and group profile header |
| Premium badge / verified mark next to a name | `user.is_premium, verificationStatus, user.is_support` | no | small glyph after the name in chat list, header and profile |
| Contacts list sorted by last seen with status subtitles | `getContacts, getUser, updateUserStatus` | yes | subtitle line per row in the contacts table, with a sort using the existing status rank |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Green online dot on chat list and profile avatars | `updateUserStatus, userStatusOnline` | yes | small badge overlay drawn on the avatar view in chat list cells and contacts list |
| Privacy exception lists (Always/Never share status) | `userPrivacySettingRuleAllowUsers, userPrivacySettingRuleRestrictUsers, userPrivacySettingRuleAllowChatMembers` | no | two 'Add Users' sub-screens with contact multi-select feeding an id list |
| Show other users' emoji status (badge next to name) | `emojiStatus, emojiStatusTypeCustomEmoji, getCustomEmojiStickers` | no | small square icon after the title in chat list rows, chat header and profile name |
| Display peer accent colour on names and reply/quote bars | `updateAccentColors, accentColor, user.accent_color_id` | no | name label colour in chat list and group messages, reply-line and link colour inside bubbles |
| Profile accent colour and profile header gradient | `profileAccentColor, profileAccentColors, updateProfileAccentColors` | no | tinted gradient behind the avatar and name in the profile header |
| Profile background custom emoji pattern | `user.background_custom_emoji_id, user.profile_background_custom_emoji_id, getCustomEmojiStickers` | no | tiled, low-alpha emoji pattern layer inside the profile header behind the avatar |
| Channel/group emoji status and accent colour display | `updateChatEmojiStatus, updateChatAccentColors, setChatEmojiStatus` | no | same title badge and header tint, on chat rows and channel profile |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Set my own emoji status | `setEmojiStatus, getDefaultEmojiStatuses, getRecentEmojiStatuses` | no | setEmojiStatus is rejected by the server for non-Premium accounts, so the whole picker would be dead UI for our users. |
| Emoji status expiration countdown | `emojiStatus, emojiStatusTypeCustomEmoji` | no | Only meaningful once we can set a status, which requires Premium; displaying another user's expiry has no value. |
| Upgraded-gift emoji status (collectible badge with backdrop colours) | `emojiStatusTypeUpgradedGift, upgradedGiftBackdropColors, upgradedGiftColors` | no | Requires the whole gifts/collectibles subsystem and animated model+symbol custom emoji layering; far beyond the 4S render budget and the client's scope. |
| Set my own accent colour / name colour | `setAccentColor, updateAccentColors` | no | setAccentColor is a Premium-only feature (premiumFeatureAccentColor); the server rejects it for free accounts. |
| Set my own profile accent colour | `setProfileAccentColor` | no | Premium-gated on the server, same as setAccentColor. |
| Hide my last seen while still seeing others (Premium last-seen times) | `premiumFeatureLastSeenTimes, userPrivacySettingShowStatus` | no | Reciprocity is enforced server-side; only Premium accounts get exact times while hiding their own. |

## users-contacts
33 capabilities - 16 trivial, 12 design, 5 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Contact list (fetch + display) | `getContacts, getUser, createPrivateChat` | yes | table view of contacts with avatar + last-seen subtitle; the Contacts tab |
| Contact search | `searchContacts` | no | UISearchBar above the contacts table |
| Remove contact / delete contact | `removeContacts` | no | destructive row on user profile and swipe-to-delete in contacts list |
| Find user by phone number | `searchUserByPhoneNumber` | yes | search field result section 'not in your contacts' |
| Find user by username / t.me deep token | `searchPublicChat, searchUserByToken` | no | global search results section |
| Share my phone number with a user | `sharePhoneNumber` | no | banner/button in a private chat when need_phone_number_privacy_exception is set |
| User profile: core fields display | `getUser, getUserFullInfo, userFullInfo` | yes | profile screen header + info rows (phone, username, bio) |
| Own profile editing: name, bio, username | `setName, setBio, setUsername` | yes | Edit Profile screen with text fields and a bio character counter |
| Birthdate: set own, display, privacy | `setBirthdate, birthdate, userPrivacySettingShowBirthdate` | no | date picker row in Edit Profile plus a birthday row on profiles; privacy row in Privacy settings |
| Contact birthdays today (close birthdays) | `updateContactCloseBirthdays, closeBirthdayUser, hideContactCloseBirthdays` | no | a dismissible section at the top of the Contacts tab listing users with birthdays |
| Private note about a contact | `setUserNote, userFullInfo.note` | no | editable multiline note row on the contact's profile |
| Groups in common with a user | `getGroupsInCommon` | no | 'N groups in common' row on the profile opening a chat list |
| Block / unblock user, blocked users list | `setMessageSenderBlockList, getBlockedMessageSenders, blockListMain` | yes | Block row on profile + Blocked Users screen in Privacy settings |
| Last-seen and online status | `updateUserStatus, userStatusOnline, userStatusOffline` | no | subtitle string in chat header, contact rows and profile |
| Support user / support name | `getSupportUser, getSupportName` | no | 'Ask a Question' row in Settings opening a private chat |
| Contact registered notification | `messageContactRegistered, pushMessageContentContactRegistered` | no | service-message bubble '<name> joined Telegram' |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Add contact (manual entry) | `addContact, importedContact, contact` | no | modal form with first/last name + phone fields, plus 'share my phone number' toggle; from Contacts tab + button and from a user profile |
| Address Book import and sync | `importContacts, changeImportedContacts, getImportedContactCount` | yes | one-time permission prompt on first Contacts tab open + a 'Sync contacts' toggle and 'Delete synced contacts' row in Privacy settings |
| Temporary contact link (add-me QR/link) | `getUserLink, searchUserByToken` | no | 'Add People Nearby'-style share sheet showing a t.me link and expiry; row in Contacts tab |
| Close friends list | `setCloseFriends, getCloseFriends, user.is_close_friend` | no | multi-select contact picker screen reached from Privacy settings; star badge on profile |
| Multiple usernames (active/inactive, reorder) | `toggleUsernameIsActive, reorderActiveUsernames, usernames` | no | list of usernames with toggle switches and drag reorder in Edit Profile |
| Profile photo: set / delete / view history | `setProfilePhoto, deleteProfilePhoto, getUserProfilePhotos` | no | action sheet on avatar tap (Take Photo / Choose from Library / Delete) and a paged photo viewer |
| Personal photo set for another contact | `setUserPersonalProfilePhoto, suggestUserProfilePhoto, userFullInfo.personal_photo` | no | 'Set Photo for <name>' / 'Suggest Photo' rows in the contact's profile action sheet |
| Suggest a birthdate to a contact / birthdate suggestion message | `suggestUserBirthdate, messageSuggestBirthdate, setBirthdate` | no | profile action row, and an in-chat service-message bubble with an Accept button |
| Personal channel on profile | `setPersonalChat, getSuitablePersonalChats, userFullInfo.personal_chat_id` | no | picker of own channels in Edit Profile; a channel preview cell with its latest post on the viewed profile |
| Privacy settings for profile data | `getUserPrivacySettingRules, setUserPrivacySettingRules, userPrivacySettingShowStatus` | yes | Privacy settings list with a per-setting Everybody/Contacts/Nobody radio screen plus exception pickers |
| Main profile tab selection (Posts/Gifts/Media...) | `setMainProfileTab, profileTabPosts, profileTabMedia` | no | segmented tab strip on the profile screen |
| Share contact as a message / contact card | `inputMessageContact, messageContact, contact` | no | 'Share Contact' in attachment menu; contact bubble with avatar, name and Add/Call actions |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Animated / video profile photo | `inputChatPhotoAnimation, setProfilePhoto` | no | The 4S has no practical H.264 encode path for a trimmed looping avatar under iOS 6 and cannot play the animated avatar back inline; static photos only. |
| Emoji status on own and others' profiles | `setEmojiStatus, setUserEmojiStatus, emojiStatus` | no | Custom emoji statuses are animated TGS/webm premium assets; no Lottie/webm decode on a 4S under iOS 6, and setting one requires Premium. |
| Profile accent colors and background custom emoji | `setAccentColor, setProfileAccentColor, updateProfileAccentColors` | no | Requires Premium to set, the swatch grid wants UICollectionView which is unavailable pre-iOS 6 here, and the design brief targets the flat 2013 look which has no per-user accent colors. |
| Profile audio (profile song) | `addProfileAudio, removeProfileAudio, setProfileAudioPosition` | no | Premium-gated modern feature with no counterpart in the 2013 design; not worth the streaming plumbing. |
| Sponsored-messages opt-out on own profile | `toggleHasSponsoredMessagesEnabled, userFullInfo.has_sponsored_messages_enabled` | no | Disabling sponsored messages requires an active Premium subscription server-side; the toggle would always fail. |

## web-and-links
29 capabilities - 13 trivial, 13 design, 3 blocked.

### trivial

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Open external HTTP link with confirmation | `getExternalLinkInfo, getExternalLink, loginUrlInfoOpen` | no | UIActionSheet confirmation showing the domain, then [UIApplication openURL:] |
| Login-URL keyboard buttons (Seamless Telegram Login) | `inlineKeyboardButtonTypeLoginUrl, getLoginUrlInfo, getLoginUrl` | no | confirmation alert with the bot name and an optional 'allow write access' checkbox row, then opens Safari |
| tg:// unknown deep link handling | `internalLinkTypeUnknownDeepLink, getDeepLinkInfo, deepLinkInfo` | no | alert with server-supplied text and an optional 'Update App' button |
| Copy message link / permalink to a message | `getMessageLink, messageLink` | no | 'Copy Link' row in the existing message long-press action sheet |
| Public username / t.me/username resolution | `internalLinkTypePublicChat, searchPublicChat, internalLinkTypeUserPhoneNumber` | yes | pushes profile or chat screen; draft_text pre-fills the composer |
| Instant View footer chrome (view count, feedback link, share) | `webPageInstantView, internalLinkTypeMessage, getMessageLink` | no | view-count label and a 'Leave a comment' footer row plus a share action sheet in the reader nav bar |
| 'Instant View' button on link preview bubbles | `linkPreview, internalLinkTypeInstantView, getWebPageInstantView` | no | a full-width button strip at the bottom of the link preview bubble that pushes the reader |
| Link preview options: disable, force small/large, show above text | `linkPreviewOptions, inputMessageText, editMessageText` | no | action sheet from the composer preview strip with three toggles |
| Non-article link preview types rendered as media (photo, video, sticker, document, audio, voice) | `linkPreviewTypePhoto, linkPreviewTypeVideo, linkPreviewTypeDocument` | no | reuses the existing photo/video/document/voice attachment views inside the preview bubble |
| Sharing a chat/bot/game/sticker set as a t.me link | `getInternalLink, internalLinkTypePublicChat, internalLinkTypeStickerSet` | no | 'Copy Link' / 'Share' rows in profile and sticker set screens |
| Recently visited t.me URLs | `getRecentlyVisitedTMeUrls, tMeUrls, tMeUrl` | no | a suggestions section in the global search screen |
| Message embedding code and app download link | `getMessageEmbeddingCode, getApplicationDownloadLink` | no | 'Copy Embed Code' row in the message action sheet; download link used in the invite-friends flow |
| Instant View local cache / offline read | `getWebPageInstantView` | no | none, just the only_local flag on the reader load path |

### design

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Link preview bubble in chat messages | `messageText, linkPreview, linkPreviewTypeArticle` | no | new left-accent-bar attachment view inside the message bubble (site name, title, description, thumbnail) in TGChatViewController message cells |
| Large-media vs small-media preview layout | `linkPreview, linkPreviewOptions` | no | layout variant switch inside the link preview view (thumb on the right vs full-width image above text) |
| Tappable text entities (url, textUrl, email, phone, mention, hashtag, bank card) | `textEntity, textEntityTypeUrl, textEntityTypeTextUrl` | no | hit-testable link runs in the message text label plus a long-press action sheet (Open, Copy, Add to Reading List) |
| Link tap routing: internal vs external | `getInternalLinkType, internalLinkTypePublicChat, internalLinkTypeMessage` | no | no visible UI of its own: a central TGLinkRouter that dispatches to existing chat/profile/sticker screens or to Safari |
| Open a t.me message link (resolve to chat + scroll to message) | `getMessageLinkInfo, messageLinkInfo, internalLinkTypeMessage` | no | pushes the existing chat controller and jumps to the message id |
| Chat invite links (t.me/+hash, joinchat) | `internalLinkTypeChatInvite, checkChatInviteLink, joinChatByInviteLink` | no | modal join sheet with chat photo, title, member count and a Join button |
| Instant View article reader (v1 text blocks) | `getWebPageInstantView, webPageInstantView, pageBlockTitle` | no | a full-screen native reader controller: UITableView of heterogeneous block cells with a top-right share button |
| Instant View rich text renderer | `richTextPlain, richTextBold, richTextItalic` | no | shared CoreText attributed-string builder used by every Instant View block and by the message text label |
| Instant View media blocks (photo, animation, video, collage, slideshow, cover) | `pageBlockPhoto, pageBlockAnimation, pageBlockVideo` | no | image cells inside the reader with a caption strip; slideshow uses a paged UIScrollView |
| Instant View v2 blocks (tables, collapsible details, related articles, kicker, section headings) | `pageBlockTable, pageBlockTableCell, pageBlockDetails` | no | horizontally scrolling table view, expandable disclosure rows, and a related-articles list at the article end |
| Composer link preview panel | `getLinkPreview, linkPreviewOptions, inputMessageText` | no | a preview strip above the input bar with a close (x) button while typing a URL |
| External audio/video link playback (linkPreviewTypeExternalVideo/Audio) | `linkPreviewTypeExternalVideo, linkPreviewTypeExternalAudio` | no | tap the preview to open MPMoviePlayerViewController |
| Handling incoming tg:// and t.me URLs from other apps | `getInternalLinkType, getDeepLinkInfo` | no | app delegate openURL entry point feeding the link router; no visible UI |

### blocked

| feature | TDLib | wrapped | UI surface |
|---|---|---|---|
| Instant View embedded content blocks (YouTube, tweets, iframes) | `pageBlockEmbedded, pageBlockEmbeddedPost, linkPreviewTypeEmbeddedVideoPlayer` | no | the supplied html is modern JS that iOS 6 UIWebView cannot run, and current YouTube/Twitter embeds require TLS and JS features the 4S stack does not support; render the poster photo and hand the URL to Safari instead. |
| Instant View map block | `pageBlockMap, location` | no | MKMapSnapshotter is iOS 7+ and an offscreen MKMapView render on a 4S is slow and memory hungry; fall back to a tappable placeholder that opens Maps. |
| Telegram Mini Apps / Web Apps opened from links | `internalLinkTypeWebApp, internalLinkTypeMainWebApp, internalLinkTypeAttachmentMenuBot` | no | Mini Apps require WKWebView with a postMessage bridge and modern ES6/TLS support; iOS 6 only has UIWebView and its JS engine plus certificate stack cannot run today's telegram-web-app.js, so these links should show 'not supported in this app' and offer Safari. |
