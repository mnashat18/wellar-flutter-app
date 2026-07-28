import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'utils/app_colors.dart';
import 'state/app_providers.dart';
import 'state/app_language_state.dart';
import 'state/session.dart';
import 'screens/invite_screen.dart';
import 'screens/employee_requests_screen.dart';
import 'screens/scan_request_open_screen.dart';
import 'utils/page_transition.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FLUTTER_ERROR] ${details.exceptionAsString()}');
    debugPrint(details.stack.toString());
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[ASYNC_ERROR] $error');
    debugPrint(stack.toString());
    return false;
  };

  final sessionInit = Session.init();
  final savedLanguageLoad = AppLanguageController.loadSavedLanguage();
  await sessionInit;
  final savedLanguage = await savedLanguageLoad;

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  final languageController = AppLanguageController(
    initialLanguage: savedLanguage,
    loaded: true,
  );
  runApp(
    MyApp(
      languageController: languageController,
    ),
  );

  // Deferred, non-blocking to avoid delaying first frame.
  if (!kIsWeb) {
    unawaited(_initFirebaseAndPush());
  }
}

Future<void> _initFirebaseAndPush() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await PushNotificationService.instance.initialize();
  } catch (e) {
    debugPrint('[STARTUP_ROUTE] firebase_init_failed=true');
  }
}

final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  final AppLanguageController languageController;

  const MyApp({
    super.key,
    required this.languageController,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        appLanguageControllerProvider.overrideWith((ref) => languageController),
      ],
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushNotificationService.instance.attachContainer(
        ProviderScope.containerOf(context),
      );
      PushNotificationService.instance.attachOpenHandler(_handlePushOpen);
    });
  }

  void _handlePushOpen(Map<String, dynamic> data) {
    if (!_isScanRequestOpenPayload(data)) return;
    final scanRequestId = _scanRequestIdFromPayload(data);
    final navigator = _navKey.currentState;
    if (navigator == null) return;
    if (scanRequestId.isEmpty) {
      navigator.push(
        MaterialPageRoute(builder: (_) => const EmployeeRequestsScreen()),
      );
      return;
    }
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ScanRequestOpenScreen(scanRequestId: scanRequestId),
      ),
    );
  }

  bool _isScanRequestOpenPayload(Map<String, dynamic> data) {
    final event = data['event']?.toString().trim() ?? '';
    final screen = data['screen']?.toString().trim() ?? '';
    final route = data['route']?.toString().trim() ?? '';
    final linkType =
        data['link_type']?.toString().trim() ?? data['type']?.toString().trim() ?? '';
    return event == 'scan_request_created' ||
        screen == 'scan_request_open' ||
        route == 'scan_requests' ||
        linkType == 'scan_request';
  }

  String _scanRequestIdFromPayload(Map<String, dynamic> data) {
    final linkId = data['link_id']?.toString().trim() ?? '';
    if (linkId.isNotEmpty) return linkId;
    final scanRequestId = data['scan_request_id']?.toString().trim() ?? '';
    if (scanRequestId.isNotEmpty) return scanRequestId;
    final requestId = data['request_id']?.toString().trim() ?? '';
    if (requestId.isNotEmpty) return requestId;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final languageController = ref.watch(appLanguageControllerProvider);
    final lang = languageController.language;
    final direction = lang.isRtl ? TextDirection.rtl : TextDirection.ltr;
    ErrorWidget.builder = (details) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.primarySoft, AppColors.primary],
                        ),
                      ),
                      child: const Text(
                        'W',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Something went wrong',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Please restart the app or try again in a moment.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 14),
                      Text(
                        details.exceptionAsString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    };
    return AutoRefreshGate(
      child: DeepLinkListener(
        child: MaterialApp(
          navigatorKey: _navKey,
          navigatorObservers: [RouteRefreshObserver()],
          debugShowCheckedModeBanner: false,
          title: 'Waller AI',
          locale: lang.locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Directionality(
            textDirection: direction,
            child: child ?? const SizedBox.shrink(),
          ),
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            cardTheme: CardThemeData(
              color: WellarTheme.surface,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: WellarTheme.border),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: WellarTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
                side: BorderSide(color: WellarTheme.border),
              ),
              titleTextStyle: const TextStyle(
                color: WellarTheme.text,
                fontWeight: FontWeight.w700,
              ),
              contentTextStyle: const TextStyle(color: WellarTheme.textMuted),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: WellarTheme.surface,
              modalBackgroundColor: WellarTheme.surface,
              showDragHandle: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
            textTheme: GoogleFonts.manropeTextTheme().apply(
              bodyColor: Colors.white,
              displayColor: Colors.white,
            ),
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary,
              brightness: Brightness.dark,
            ),
          ),
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

class DeepLinkListener extends StatefulWidget {
  final Widget child;

  const DeepLinkListener({super.key, required this.child});

  @override
  State<DeepLinkListener> createState() => _DeepLinkListenerState();
}

class _DeepLinkListenerState extends State<DeepLinkListener> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _lastInviteToken;

  @override
  void initState() {
    super.initState();
    _initLinks();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _initLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handleUri(initial);
      }
    } catch (_) {}

    _sub = _appLinks.uriLinkStream.listen(
      (uri) => _handleUri(uri),
      onError: (_) {},
    );
  }

  void _handleUri(Uri uri) {
    final token = _extractInviteToken(uri);
    if (token == null || token.isEmpty) return;
    if (_lastInviteToken == token) return;
    _lastInviteToken = token;
    Session.instance.setPendingInviteToken(token);

    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navKey.currentContext;
      if (context == null) return;
      Navigator.push(context, fadeSlideRoute(InviteScreen(token: token)));
    });
  }

  String? _extractInviteToken(Uri uri) {
    if (uri.scheme == 'app' && uri.host == 'invite') {
      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
    }

    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.pathSegments.isNotEmpty) {
      final segments = uri.pathSegments;
      final inviteIndex = segments.indexOf('invite');
      if (inviteIndex != -1 && inviteIndex + 1 < segments.length) {
        return segments[inviteIndex + 1];
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ============================================================
/// AUTO REFRESH GATE
/// ------------------------------------------------------------
/// - Single source of truth for app-wide refresh
/// - Fires only when app becomes foreground
/// - Guarded by session state
/// ============================================================

class AutoRefreshGate extends ConsumerStatefulWidget {
  final Widget child;

  const AutoRefreshGate({super.key, required this.child});

  @override
  ConsumerState<AutoRefreshGate> createState() => _AutoRefreshGateState();
}

class _AutoRefreshGateState extends ConsumerState<AutoRefreshGate>
    with WidgetsBindingObserver {
  bool _isForeground = true;
  bool _initialRefreshDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      _refreshAll(reason: 'app_resumed');
    }
  }

  void _initialRefresh() {
    if (_initialRefreshDone) return;
    _initialRefreshDone = true;
    _refreshAll(reason: 'initial');
  }

  void _refreshAll({required String reason}) {
    if (!_isForeground) return;
    final container = ProviderScope.containerOf(context, listen: false);
    container.read(refreshTickProvider.notifier).state++;
    container.invalidate(homeDataProvider);
    container.invalidate(homeScansProvider);
    container.invalidate(historyProvider);
    if (!kIsWeb && Session.instance.isLoggedIn) {
      if (reason == 'initial') {
        unawaited(PushNotificationService.instance.syncOnAppStarted());
      } else {
        unawaited(PushNotificationService.instance.syncOnAppResumed());
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// ============================================================
/// ROUTE REFRESH OBSERVER
/// ------------------------------------------------------------
/// - Lightweight refresh on navigation
/// - Does NOT invalidate providers
/// - Prevents stale UI without heavy refetch
/// ============================================================

class RouteRefreshObserver extends NavigatorObserver {
  RouteRefreshObserver();

  void _softRefresh() {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navKey.currentContext;
      if (context == null) return;
      final container = ProviderScope.containerOf(context, listen: false);
      container.read(refreshTickProvider.notifier).state++;
      container.invalidate(homeDataProvider);
      container.invalidate(homeScansProvider);
      container.invalidate(historyProvider);
    });
  }

  @override
  void didPush(Route route, Route? previousRoute) => _softRefresh();

  @override
  void didPop(Route route, Route? previousRoute) => _softRefresh();

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) => _softRefresh();
}
