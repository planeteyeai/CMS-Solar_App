import 'dart:convert';

import 'package:http/http.dart' as http;

/// Pulls a list of records out of the several response shapes this backend
/// uses: a bare list, DRF `{results: []}`, `{data: []}`, `{events: []}` …
List<Map<String, dynamic>> extractList(dynamic decoded,
    {List<String> keys = const [
      'results', 'data', 'items', 'events', 'worker_statuses', 'records'
    ]}) {
  List<dynamic> raw = const [];
  if (decoded is List) {
    raw = decoded;
  } else if (decoded is Map) {
    for (final k in keys) {
      if (decoded[k] is List) {
        raw = decoded[k] as List;
        break;
      }
    }
  }
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

dynamic decodeBody(http.Response res) {
  try {
    return jsonDecode(utf8.decode(res.bodyBytes));
  } catch (_) {
    return null;
  }
}

/// Human-readable message for an error response.
String errorMessage(http.Response? res, {String fallback = 'Request failed.'}) {
  if (res == null) return 'Network error. Check your connection and try again.';
  if (res.statusCode == 401) return 'Session expired. Please sign in again.';
  if (res.statusCode == 403) {
    final d = decodeBody(res);
    if (d is Map && d['detail'] != null) return d['detail'].toString();
    return 'You do not have permission to do this.';
  }
  final d = decodeBody(res);
  if (d is Map) {
    for (final k in ['detail', 'error', 'message']) {
      if (d[k] != null) return d[k].toString();
    }
    final parts = <String>[];
    d.forEach((k, v) {
      parts.add('$k: ${v is List ? v.join(', ') : v}');
    });
    if (parts.isNotEmpty) return parts.take(3).join('\n');
  }
  return '$fallback (${res.statusCode})';
}
