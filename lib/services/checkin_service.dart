import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/attendance.dart';
import 'api_helpers.dart';
import 'auth_service.dart';

enum PresenceState { notCheckedIn, checkedIn, checkedOut }

/// Attendance for the logged-in Site Engineer, driven by the real backend.
///
/// How the backend works (accounts/attendance.py):
///  • The FIRST GPS ping of the day creates the attendance record → CHECK-IN.
///  • Every later ping updates `check_out` / duration (it is always "the last
///    ping"), and the record stays ACTIVE.
///  • Geofencing decides the zone and whether the worker is inside the project.
///
/// So the app: check-in = send a ping; while checked in it keeps pinging every
/// few minutes (app open) so the end time stays accurate; check-out = send a
/// final ping and stop pinging. Team Lead / PM / Superadmin see all of this
/// through the dashboard endpoints.
class CheckInService extends ChangeNotifier {
  static const _kCheckoutDate = 'cms_checkout_date';
  static const pingInterval = Duration(minutes: 10);
  static const _kQueue = 'cms_ping_queue';

  AttendanceRecord? _today;
  bool _locallyCheckedOut = false;
  bool _busy = false;
  bool _syncing = false;
  String? _error;
  DateTime? _lastSync;
  DateTime? _lastPing;

  // From the last ping response
  bool? _insideProject;
  String? _geofenceProject;
  String? _zone;

  Timer? _pingTimer; // foreground fallback only
  StreamSubscription<Position>? _trackSub;
  DateTime? _lastTrackAttempt;

  AttendanceRecord? get today => _today;
  bool get busy => _busy;
  bool get syncing => _syncing;
  String? get error => _error;
  DateTime? get lastSync => _lastSync;
  DateTime? get lastPing => _lastPing;
  bool? get insideProject => _insideProject;
  String? get geofenceProject => _geofenceProject;
  String get zone => (_zone != null && _zone!.isNotEmpty) ? _zone! : (_today?.zone ?? '');

  PresenceState get state {
    if (_today == null) return PresenceState.notCheckedIn;
    return _locallyCheckedOut ? PresenceState.checkedOut : PresenceState.checkedIn;
  }

  bool get isCheckedIn => state == PresenceState.checkedIn;
  bool get isCheckedOut => state == PresenceState.checkedOut;

  String get statusLabel {
    switch (state) {
      case PresenceState.checkedIn:
        return 'CHECKED IN';
      case PresenceState.checkedOut:
        return 'CHECKED OUT';
      case PresenceState.notCheckedIn:
        return 'NOT CHECKED IN';
    }
  }

  DateTime? get checkInTime => _today?.checkIn;
  DateTime? get checkOutTime => isCheckedOut ? (_today?.checkOut) : null;

  Duration get timeOnSite {
    final start = _today?.checkIn;
    if (start == null) return Duration.zero;
    final end = isCheckedOut ? (_today?.checkOut ?? DateTime.now()) : DateTime.now();
    final d = end.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  // ── Sync with backend ────────────────────────────────────────────────────

  Future<void> refresh(AuthService auth, {bool silent = false}) async {
    final profile = auth.profile;
    if (!auth.isLoggedIn || profile == null || _syncing) return;
    _syncing = true;
    if (!silent) notifyListeners();

    try {
      final res =
          await auth.authenticatedGet(ApiConfig.workerAttendanceTodayUrl(profile.id));
      if (res == null) {
        _error = 'Offline – showing last known status.';
      } else if (res.statusCode == 200) {
        final d = decodeBody(res);
        if (d is Map) {
          _today = AttendanceRecord.fromJson(Map<String, dynamic>.from(d));
          _error = null;
        }
      } else if (res.statusCode == 404) {
        _today = null;
        _error = null;
      } else {
        _error = errorMessage(res, fallback: 'Could not sync attendance');
      }

      final prefs = await SharedPreferences.getInstance();
      _locallyCheckedOut = _today != null &&
          prefs.getString(_kCheckoutDate) == '${profile.id}|${fmtDate(DateTime.now())}';
      _lastSync = DateTime.now();
      _syncTracking(auth);
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  // ── Check-in / out ───────────────────────────────────────────────────────

  /// Returns an error message, or null on success.
  Future<String?> checkIn(AuthService auth) async {
    if (_busy) return null;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final err = await _sendPing(auth);
      if (err != null) {
        _error = err;
        return err;
      }
      await _setLocalCheckout(auth, false);
      await refresh(auth, silent: true);
      return null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<String?> checkOut(AuthService auth) async {
    if (_busy) return null;
    _busy = true;
    notifyListeners();
    try {
      // Final ping records the exact check-out time. If GPS fails we still
      // end the session; the backend keeps the last ping as the end time.
      final err = await _sendPing(auth);
      await _setLocalCheckout(auth, true);
      _stopTracking();
      await refresh(auth, silent: true);
      return err == null ? null : 'Checked out, but the final location could not be sent ($err).';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _setLocalCheckout(AuthService auth, bool value) async {
    final id = auth.profile?.id;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (value) {
      await prefs.setString(_kCheckoutDate, '$id|${fmtDate(DateTime.now())}');
    } else {
      await prefs.remove(_kCheckoutDate);
    }
    _locallyCheckedOut = value;
  }

  // ── GPS ping ─────────────────────────────────────────────────────────────

  Future<String?> _sendPing(AuthService auth) async {
    if (auth.profile == null) return 'Not logged in.';
    final pos = await _getPosition();
    if (pos is String) return pos;
    return _sendPosition(auth, pos as Position);
  }

  /// Sends one position. If there is no signal the point is kept on the phone
  /// and uploaded (oldest first, with its real time) on the next successful ping,
  /// so the travelled path has no gaps.
  Future<String?> _sendPosition(AuthService auth, Position position) async {
    final profile = auth.profile;
    if (profile == null) return 'Not logged in.';

    await _flushQueue(auth, profile.id);

    final lat = double.parse(position.latitude.toStringAsFixed(8));
    final lon = double.parse(position.longitude.toStringAsFixed(8));
    final ts = DateTime.now().toUtc();
    final res = await _post(auth, profile.id, lat, lon, ts);

    if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
      final d = decodeBody(res);
      if (d is Map && d['geofence'] is Map) {
        final g = Map<String, dynamic>.from(d['geofence'] as Map);
        _insideProject = g['inside_project'] == true;
        _geofenceProject = g['project_name']?.toString();
        _zone = g['zone']?.toString();
      }
      _lastPing = DateTime.now();
      return null;
    }
    if (res == null || res.statusCode >= 500) {
      await _enqueue(lat, lon, ts);
      return 'No connection. Your location is saved on this phone and will upload automatically.';
    }
    return errorMessage(res, fallback: 'Location was rejected by the server');
  }

  Future<http.Response?> _post(AuthService auth, int workerId, double lat, double lon, DateTime ts) =>
      auth.authenticatedPost(ApiConfig.workerLocationUrl, {
        'worker_id': workerId,
        'latitude': lat,
        'longitude': lon,
        'timestamp': ts.toIso8601String(),
      });

  Future<List<Map<String, dynamic>>> _readQueue() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kQueue);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeQueue(List<Map<String, dynamic>> q) async {
    final prefs = await SharedPreferences.getInstance();
    if (q.isEmpty) {
      await prefs.remove(_kQueue);
    } else {
      await prefs.setString(_kQueue, jsonEncode(q.length > 300 ? q.sublist(q.length - 300) : q));
    }
  }

  Future<void> _enqueue(double lat, double lon, DateTime ts) async {
    final q = await _readQueue();
    q.add({'lat': lat, 'lon': lon, 'ts': ts.toIso8601String()});
    await _writeQueue(q);
  }

  Future<void> _flushQueue(AuthService auth, int workerId) async {
    final q = await _readQueue();
    if (q.isEmpty) return;
    var sent = 0;
    for (final p in q) {
      final res = await _post(auth, workerId, (p['lat'] as num).toDouble(),
          (p['lon'] as num).toDouble(), DateTime.parse(p['ts'].toString()));
      if (res != null && (res.statusCode == 200 || res.statusCode == 201)) {
        sent++;
      } else if (res != null && res.statusCode < 500) {
        sent++; // rejected for good (validation): drop it
      } else {
        break; // still offline
      }
    }
    await _writeQueue(q.sublist(sent));
  }

  /// Position on success, error String on failure.
  Future<Object> _getPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return 'Location services are off. Turn on GPS and try again.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) return 'Location permission denied.';
      if (perm == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return 'Location permission is blocked. Allow it in Settings.';
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 20),
      );
    } on TimeoutException {
      return 'Could not get a GPS fix. Move to open sky and retry.';
    } catch (e) {
      return 'Could not read location.';
    }
  }

  /// Cached position (no GPS wait) for tagging saved updates.
  Future<Position?> lastKnownOrNull() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Current position for tagging analyses (null if unavailable).
  Future<Position?> currentPositionOrNull() async {
    final p = await _getPosition();
    return p is Position ? p : null;
  }

  // ── Keep-alive pings while checked in ────────────────────────────────────

  LocationSettings _trackingSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: pingInterval,
        // Keeps tracking alive when the app is in the background / screen is off.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Site tracking is on',
          notificationText: 'Your location is shared with your site team while you are checked in.',
          enableWakeLock: true,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.other,
        distanceFilter: 25,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
  }

  /// While checked in: record the position every [pingInterval], also in the background.
  void _syncTracking(AuthService auth) {
    if (isCheckedIn) {
      _startTracking(auth);
    } else {
      _stopTracking();
    }
  }

  void _startTracking(AuthService auth) {
    if (_trackSub != null || _pingTimer != null) return;
    try {
      _trackSub = Geolocator.getPositionStream(locationSettings: _trackingSettings()).listen(
        (pos) async {
          if (!isCheckedIn) return;
          final now = DateTime.now();
          final last = _lastTrackAttempt;
          if (last != null && now.difference(last) < pingInterval - const Duration(seconds: 45)) {
            return; // the OS may deliver more often than every 10 minutes
          }
          _lastTrackAttempt = now;
          await _sendPosition(auth, pos);
          notifyListeners();
        },
        onError: (_) {
          _trackSub?.cancel();
          _trackSub = null;
          _startFallbackTimer(auth);
        },
      );
    } catch (_) {
      _startFallbackTimer(auth);
    }
  }

  /// Used only if the background location stream is not available.
  void _startFallbackTimer(AuthService auth) {
    _pingTimer ??= Timer.periodic(pingInterval, (_) async {
      if (!isCheckedIn) return;
      await _sendPing(auth);
      notifyListeners();
    });
  }

  void _stopTracking() {
    _trackSub?.cancel();
    _trackSub = null;
    _pingTimer?.cancel();
    _pingTimer = null;
    _lastTrackAttempt = null;
  }

  void reset() {
    _stopTracking();
    _today = null;
    _locallyCheckedOut = false;
    _error = null;
    _lastSync = null;
    _lastPing = null;
    _insideProject = null;
    _zone = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTracking();
    super.dispose();
  }
}
