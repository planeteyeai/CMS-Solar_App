import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/user_profile.dart';

/// Handles JWT authentication against POST /api/token/
/// and profile fetching from GET /api/accounts/me/.
///
/// Role routing is driven by the authenticated /api/accounts/me/ response.
/// Superadmin is identified by is_superuser=true or highest_role=SUPER_ADMIN.
/// Site Engineer is identified by highest_role=SITE_ENGINEER.
class AuthService extends ChangeNotifier {
  static const _kAccess  = 'jwt_access';
  static const _kRefresh = 'jwt_refresh';

  UserProfile? _profile;
  String?      _accessToken;
  String?      _refreshTok;
  bool         _loading = false;
  String?      _error;

  // ── Public getters ────────────────────────────────────────────────────────
  UserProfile? get profile      => _profile;
  bool         get loading      => _loading;
  String?      get error        => _error;
  bool         get isLoggedIn   => _profile != null && _accessToken != null;

  // ── Initialise (called once at startup) ──────────────────────────────────

  Future<void> init() async {
    _loading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _accessToken = prefs.getString(_kAccess);
      _refreshTok  = prefs.getString(_kRefresh);

      if (_accessToken != null) {
        final ok = await _fetchProfile();
        if (!ok) {
          final refreshed = await _doRefresh();
          if (refreshed) {
            await _fetchProfile();
          } else {
            await _clearSession();
          }
        }
      }
    } catch (_) {
      await _clearSession();
    }

    _loading = false;
    notifyListeners();
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  /// Calls POST /api/token/ with [username] + [password].
  /// On success, fetches /api/accounts/me/ and populates [profile].
  /// Returns true on success; check [error] on false.
  Future<bool> login(String username, String password) async {
    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.tokenUrl),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({
              'username': username.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _accessToken = data['access'] as String;
        _refreshTok  = data['refresh'] as String;

        // Persist tokens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAccess,  _accessToken!);
        await prefs.setString(_kRefresh, _refreshTok!);

        // Fetch user profile. Login is not considered complete unless the
        // authenticated profile can also be loaded.
        final profileLoaded = await _fetchProfile();
        if (!profileLoaded) {
          await _clearSession();
          _error = 'Login succeeded, but the user profile could not be loaded.';
          _loading = false;
          notifyListeners();
          return false;
        }

        // The profile is now authoritative. Notify the root router only after
        // both token and /me profile are ready.
        _loading = false;
        notifyListeners();
        return true;
      }

      // ── Error responses ────────────────────────────────────────────────
      if (response.statusCode == 401) {
        _error = 'Invalid username or password.';
      } else if (response.statusCode == 400) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final msgs = <String>[];
        data.forEach((key, val) {
          if (val is List && val.isNotEmpty) msgs.add(val.first.toString());
        });
        _error = msgs.isNotEmpty ? msgs.join(' ') : 'Invalid request.';
      } else {
        _error = 'Server error (${response.statusCode}). Try again.';
      }
    } on TimeoutException {
      _error = 'Server not responding. Check your network connection.';
    } on Exception catch (e) {
      _error = 'Could not reach server. Is it running?\n($e)';
    }

    _loading = false;
    notifyListeners();
    return false;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    await _clearSession();
    notifyListeners();
  }

  // ── Authenticated HTTP helpers (used by CheckInService) ──────────────────

  Future<http.Response?> authenticatedGet(String url) async {
    if (_accessToken == null) return null;
    try {
      var res = await http
          .get(Uri.parse(url), headers: ApiConfig.authHeaders(_accessToken!))
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 401) {
        if (await _doRefresh()) {
          res = await http
              .get(Uri.parse(url), headers: ApiConfig.authHeaders(_accessToken!))
              .timeout(const Duration(seconds: 15));
        }
      }
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Any HTTP method (used by the connection check, e.g. OPTIONS).
  Future<http.Response?> authenticatedRequest(String method, String url,
      {Map<String, dynamic>? body}) async {
    if (_accessToken == null) return null;
    Future<http.Response> send() async {
      final req = http.Request(method, Uri.parse(url))
        ..headers.addAll(ApiConfig.authHeaders(_accessToken!));
      if (body != null) req.body = jsonEncode(body);
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      return http.Response.fromStream(streamed);
    }

    try {
      var res = await send();
      if (res.statusCode == 401 && await _doRefresh()) res = await send();
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response?> authenticatedPost(
      String url, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 15)}) async {
    if (_accessToken == null) return null;
    try {
      var res = await http
          .post(
            Uri.parse(url),
            headers: ApiConfig.authHeaders(_accessToken!),
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (res.statusCode == 401) {
        if (await _doRefresh()) {
          res = await http
              .post(
                Uri.parse(url),
                headers: ApiConfig.authHeaders(_accessToken!),
                body: jsonEncode(body),
              )
              .timeout(timeout);
        }
      }
      return res;
    } catch (_) {
      return null;
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  Future<bool> _fetchProfile() async {
    if (_accessToken == null) return false;
    try {
      final res = await http
          .get(
            Uri.parse(ApiConfig.meUrl),
            headers: ApiConfig.authHeaders(_accessToken!),
          )
          // The production profile endpoint can take 15–20 seconds.
          // A 10-second timeout falsely treated valid logins as failures.
          .timeout(const Duration(seconds: 35));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is! Map<String, dynamic>) return false;
        final parsed = UserProfile.fromJson(decoded);
        if (parsed.id <= 0 || parsed.username.isEmpty) return false;
        _profile = parsed;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _doRefresh() async {
    if (_refreshTok == null) return false;
    try {
      final res = await http
          .post(
            Uri.parse(ApiConfig.tokenRefreshUrl),
            headers: ApiConfig.jsonHeaders,
            body: jsonEncode({'refresh': _refreshTok}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _accessToken = data['access'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kAccess, _accessToken!);
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _refreshTok  = null;
    _profile     = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
  }
}
