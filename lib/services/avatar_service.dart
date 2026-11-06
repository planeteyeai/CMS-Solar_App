import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/api_config.dart';
import 'api_helpers.dart';
import 'auth_service.dart';

/// Profile pictures live in the database; the app fetches them by user id and
/// keeps them in memory so lists and maps stay fast.
class AvatarService {
  AvatarService._();

  static final Map<int, Uint8List?> _cache = {};
  static final Map<int, DateTime> _checked = {};
  static final Map<int, Future<Uint8List?>> _inflight = {};

  /// Incremented whenever a picture changes so avatars rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool hasLoaded(int userId) => _cache.containsKey(userId);
  static Uint8List? cached(int userId) => _cache[userId];

  static Future<Uint8List?> load(AuthService auth, int userId, {bool force = false}) {
    final known = _cache.containsKey(userId);
    final t = _checked[userId];
    if (!force && known && t != null) {
      final ttl = _cache[userId] == null ? const Duration(minutes: 2) : const Duration(minutes: 30);
      if (DateTime.now().difference(t) < ttl) return Future.value(_cache[userId]);
    }
    return _inflight.putIfAbsent(userId, () async {
      try {
        final res = await auth.authenticatedGet(ApiConfig.profilePictureUrl(userId));
        if (res != null && res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          _cache[userId] = res.bodyBytes;
        } else if (res != null && res.statusCode == 404) {
          _cache[userId] = null; // no picture
        } else {
          _cache.putIfAbsent(userId, () => null); // offline / error: keep what we had
        }
        _checked[userId] = DateTime.now();
        return _cache[userId];
      } finally {
        _inflight.remove(userId);
      }
    });
  }

  /// Returns an error message, or null on success. [bytes] must be a small JPEG/PNG/WEBP.
  static Future<String?> upload(AuthService auth, int userId, Uint8List bytes) async {
    final res = await auth.authenticatedPost(
      ApiConfig.profilePictureUrl(userId),
      {'image_base64': base64Encode(bytes)},
      timeout: const Duration(seconds: 45),
    );
    if (res != null && (res.statusCode == 201 || res.statusCode == 200)) {
      _cache[userId] = bytes;
      _checked[userId] = DateTime.now();
      revision.value++;
      return null;
    }
    if (res != null && res.statusCode == 404 && decodeBody(res) is! Map) {
      return 'The server does not support profile pictures yet. Ask your administrator to deploy the backend update.';
    }
    return errorMessage(res, fallback: 'Could not save the photo');
  }

  static Future<String?> remove(AuthService auth, int userId) async {
    final res = await auth.authenticatedRequest('DELETE', ApiConfig.profilePictureUrl(userId));
    if (res != null && (res.statusCode == 204 || res.statusCode == 200 || res.statusCode == 404)) {
      _cache[userId] = null;
      _checked[userId] = DateTime.now();
      revision.value++;
      return null;
    }
    return errorMessage(res, fallback: 'Could not remove the photo');
  }

  static void clear() {
    _cache.clear();
    _checked.clear();
    _inflight.clear();
    revision.value++;
  }
}
