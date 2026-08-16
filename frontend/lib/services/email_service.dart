import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import '../models/email_model.dart';

// ── Gmail scope ────────────────────────────────────────────────────
const _gmailReadonlyScope = 'https://www.googleapis.com/auth/gmail.readonly';

// ── Authenticated HTTP client ──────────────────────────────────────
/// Injects the OAuth access token into every request header.
class _GoogleAuthClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    request.headers['Content-Type'] = 'application/json';
    return _inner.send(request);
  }
}

// ── EmailService ───────────────────────────────────────────────────
class EmailService {
  static final EmailService _instance = EmailService._();
  factory EmailService() => _instance;
  EmailService._();

  // 7.x: always use the singleton instance
  final GoogleSignIn _signIn = GoogleSignIn.instance;

  GoogleSignInAccount? _currentUser;
  bool _initialized = false;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;

  bool get isSignedIn => _currentUser != null;
  String? get connectedEmail => _currentUser?.email;

  // ── Initialization ────────────────────────────────────────────

  /// Must be called once before any sign-in operations.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // 7.x: initialize() sets up the plugin.
      // clientId is not required on Android (uses google-services.json).
      await _signIn.initialize(
        serverClientId:
            '446937194320-13i4cbsbn6cdd8uurac70te20eu49hn0.apps.googleusercontent.com',
      );

      // Listen to authentication state changes
      _authSub = _signIn.authenticationEvents.listen(
        _onAuthEvent,
        onError: (e) => debugPrint('EmailService: auth stream error: $e'),
      );

      debugPrint('EmailService: initialized');
    } catch (e) {
      debugPrint('EmailService: initialize error: $e');
      _initialized = false; // allow retry
    }
  }

  void _onAuthEvent(GoogleSignInAuthenticationEvent event) {
    if (event is GoogleSignInAuthenticationEventSignIn) {
      _currentUser = event.user;
      debugPrint('EmailService: signed in → ${event.user.email}');
    } else if (event is GoogleSignInAuthenticationEventSignOut) {
      _currentUser = null;
      debugPrint('EmailService: signed out');
    }
  }

  // ── Authentication ────────────────────────────────────────────

  /// Check if already signed in without showing any UI.
  Future<bool> checkSignedIn() async {
    await _ensureInitialized();
    try {
      // 7.x: attemptLightweightAuthentication() fires an event
      // on the authenticationEvents stream if already signed in.
      // We wait briefly for the stream to emit.
      final completer = Completer<bool>();

      // If already have a user from the stream, return immediately
      if (_currentUser != null) return true;

      // Try lightweight (silent) auth — emits event on stream
      _signIn.attemptLightweightAuthentication();

      // Wait up to 3 seconds for the stream to confirm sign-in
      late StreamSubscription<GoogleSignInAuthenticationEvent> sub;
      final timer = Timer(const Duration(seconds: 3), () {
        if (!completer.isCompleted) completer.complete(false);
      });

      sub = _signIn.authenticationEvents.listen((event) {
        if (event is GoogleSignInAuthenticationEventSignIn) {
          _currentUser = event.user;
          timer.cancel();
          if (!completer.isCompleted) completer.complete(true);
        } else if (event is GoogleSignInAuthenticationEventSignOut) {
          _currentUser = null;
          timer.cancel();
          if (!completer.isCompleted) completer.complete(false);
        }
      });

      final result = await completer.future;
      await sub.cancel();
      return result;
    } catch (e) {
      debugPrint('EmailService: checkSignedIn error: $e');
      return false;
    }
  }

  /// Show the Google account picker and sign in.
  /// Must be called from a user interaction (button press).
  Future<bool> signIn() async {
    await _ensureInitialized();
    try {
      if (!_signIn.supportsAuthenticate()) {
        debugPrint(
            'EmailService: authenticate() not supported on this platform');
        return false;
      }

      // 7.x: authenticate() replaces signIn()
      // This triggers the system account picker / Credential Manager
      final account = await _signIn.authenticate();
      _currentUser = account;

      debugPrint('EmailService: authenticate() → ${account.email}');
      return true;
    } catch (e) {
      debugPrint('EmailService: signIn error: $e');
      return false;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _ensureInitialized();
    try {
      await _signIn.signOut();
      _currentUser = null;
    } catch (e) {
      debugPrint('EmailService: signOut error: $e');
    }
  }

  // ── Access Token ──────────────────────────────────────────────

  /// Get a fresh access token for the gmail.readonly scope.
  ///
  /// 7.x flow:
  ///   1. authenticate() gives us identity (who the user is)
  ///   2. authorizationClient.authorizeScopes() gives us the
  ///      access token for specific API scopes
  Future<String?> _getAccessToken() async {
    if (_currentUser == null) {
      debugPrint('EmailService: _getAccessToken — no current user');
      return null;
    }

    try {
      // 7.x: try existing authorization first (silent)
      var auth = await _currentUser!.authorizationClient
          .authorizationForScopes([_gmailReadonlyScope]);

      // If no existing authorization, request it
      auth ??= await _currentUser!.authorizationClient
          .authorizeScopes([_gmailReadonlyScope]);

      if (auth?.accessToken == null) {
        debugPrint('EmailService: authorizeScopes returned null token');
        return null;
      }

      debugPrint('EmailService: got access token');
      return auth!.accessToken;
    } catch (e) {
      debugPrint('EmailService: _getAccessToken error: $e');
      return null;
    }
  }

  // ── Gmail API Client ──────────────────────────────────────────

  Future<gmail.GmailApi?> _getGmailApi() async {
    if (_currentUser == null) {
      // Try signing in silently first
      final ok = await checkSignedIn();
      if (!ok) return null;
    }

    final token = await _getAccessToken();
    if (token == null) return null;

    return gmail.GmailApi(_GoogleAuthClient(token));
  }

  // ── Fetch Emails ──────────────────────────────────────────────

  /// Fetch recent emails with optional Gmail search query.
  /// [maxResults] is capped at 20.
  /// [query] uses Gmail search syntax e.g. "from:someone is:unread"
  Future<List<EmailModel>> fetchEmails({
    int maxResults = 10,
    String query = '',
  }) async {
    final api = await _getGmailApi();
    if (api == null) {
      debugPrint('EmailService: fetchEmails — could not get Gmail API');
      return [];
    }

    try {
      final listResponse = await api.users.messages.list(
        'me',
        maxResults: maxResults.clamp(1, 20),
        q: query.isEmpty ? 'newer_than:7d' : query,
      );

      final messages = listResponse.messages ?? [];
      debugPrint('EmailService: got ${messages.length} message IDs');

      final List<EmailModel> emails = [];

      for (final msg in messages) {
        if (msg.id == null) continue;
        try {
          final full = await api.users.messages.get(
            'me',
            msg.id!,
            // metadata format: headers + labels only, no body
            format: 'metadata',
            metadataHeaders: ['From', 'Subject', 'Date'],
          );

          final emailMap = {
            'id': full.id,
            'threadId': full.threadId,
            'snippet': full.snippet ?? '',
            'internalDate': full.internalDate,
            'labelIds': full.labelIds ?? [],
            'payload': {
              'headers': (full.payload?.headers ?? [])
                  .map((h) => {
                        'name': h.name,
                        'value': h.value,
                      })
                  .toList(),
            },
          };

          emails.add(EmailModel.fromGmailMessage(emailMap));
        } catch (e) {
          debugPrint('EmailService: error fetching msg ${msg.id}: $e');
        }
      }

      debugPrint('EmailService: returning ${emails.length} emails');
      return emails;
    } catch (e) {
      debugPrint('EmailService: fetchEmails error: $e');
      return [];
    }
  }

  // ── Convenience Fetchers ──────────────────────────────────────

  Future<List<EmailModel>> fetchTodayEmails() async =>
      fetchEmails(query: 'newer_than:1d', maxResults: 10);

  Future<List<EmailModel>> fetchUnreadEmails() async =>
      fetchEmails(query: 'is:unread newer_than:7d', maxResults: 10);

  Future<List<EmailModel>> fetchFromSender(String sender) async =>
      fetchEmails(query: 'from:$sender newer_than:30d', maxResults: 10);

  Future<List<EmailModel>> fetchBySubject(String keyword) async =>
      fetchEmails(query: 'subject:$keyword newer_than:30d', maxResults: 10);

  Future<List<EmailModel>> fetchImportantEmails() async =>
      fetchEmails(query: 'is:important newer_than:7d', maxResults: 10);

  // ── Serialization ─────────────────────────────────────────────

  List<Map<String, dynamic>> emailsToJson(List<EmailModel> emails) =>
      emails.map((e) => e.toJson()).toList();
}
