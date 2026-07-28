class AppConfig {
  static const String directusBaseUrl = String.fromEnvironment(
    'DIRECTUS_URL',
    defaultValue: 'https://dash.conntinuity.com',
  );

  static const String directusFallbackUrl = String.fromEnvironment(
    'DIRECTUS_FALLBACK_URL',
    defaultValue: '',
  );

  static const String inviteBaseUrl = String.fromEnvironment(
    'INVITE_BASE_URL',
    defaultValue: 'https://app.conntinuity.com',
  );

  static const String publicWebBaseUrl = String.fromEnvironment(
    'PUBLIC_WEB_BASE_URL',
    defaultValue: 'https://conntinuity.com',
  );

  static const String googleMobileExchangePath = String.fromEnvironment(
    'GOOGLE_MOBILE_EXCHANGE_PATH',
    defaultValue: '/auth/google/mobile-exchange',
  );

  static const String googleMobileExchangeBaseUrl = String.fromEnvironment(
    'GOOGLE_MOBILE_EXCHANGE_BASE_URL',
    defaultValue: 'https://conntinuity-mobile-auth.csiwm3.easypanel.host',
  );

  static const String scopedMemberIdentityPath = String.fromEnvironment(
    'SCOPED_MEMBER_IDENTITY_PATH',
    defaultValue: '/google-mobile-exchange/member-identities',
  );

  static const String googleMobileClientId = String.fromEnvironment(
    'GOOGLE_MOBILE_CLIENT_ID',
    defaultValue: '',
  );

  static const bool enablePushSubscriptionWrites = bool.fromEnvironment(
    'ENABLE_PUSH_SUBSCRIPTION_WRITES',
    defaultValue: false,
  );

  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '',
  );

  static const String aiServerUrl = String.fromEnvironment(
    'AI_SERVER_URL',
    defaultValue: 'https://conntinuity-ai-server.csiwm3.easypanel.host/process',
  );

  static const String accountDeletionUrl = String.fromEnvironment(
    'ACCOUNT_DELETION_URL',
    defaultValue: 'https://app.conntinuity.com/delete-account',
  );
}
