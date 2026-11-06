import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/site_task.dart';
import 'api_helpers.dart';
import 'auth_service.dart';

/// A photo ready to be stored, with the AI analysis of that photo.
class EvidenceFile {
  final String path;
  final String name;
  final String contentType;
  final int sizeBytes;
  final DateTime capturedAt;
  final Map<String, dynamic> analysis;

  const EvidenceFile({
    required this.path,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.capturedAt,
    this.analysis = const {},
  });

  static String contentTypeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'content_type': contentType,
        'size_bytes': sizeBytes,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'analysis': analysis,
      };

  factory EvidenceFile.fromJson(Map<String, dynamic> j) => EvidenceFile(
        path: j['path'].toString(),
        name: j['name'].toString(),
        contentType: j['content_type'].toString(),
        sizeBytes: (j['size_bytes'] as num?)?.toInt() ?? 0,
        capturedAt: DateTime.tryParse(j['captured_at'].toString()) ?? DateTime.now(),
        analysis: j['analysis'] is Map ? Map<String, dynamic>.from(j['analysis'] as Map) : {},
      );
}

class UploadOutcome {
  /// Evidence entries to send with the progress update (null = storage not available).
  final List<Map<String, dynamic>>? evidence;
  final String? error;

  /// When storage is unavailable: the HTTP status and a short human reason.
  final int? statusCode;
  final String reason;
  const UploadOutcome({this.evidence, this.error, this.statusCode, this.reason = ''});

  /// Storage (AWS) is not available on the server yet: caller should fall back.
  bool get unavailable => evidence == null && error == null;
}

/// Uploads photos straight to AWS S3 with short-lived signed links from the
/// backend. The photo never passes through the API server.
class EvidenceUploader {
  EvidenceUploader._();

  static String _putError(int status) {
    if (status == 403) {
      return 'Photo upload was refused (403). Check that this phone\'s date and time are correct '
          '(automatic), then try again. If it keeps happening, tell your administrator.';
    }
    if (status == 301 || status == 307 || status == 302 || status == 308) {
      return 'Photo storage is set to the wrong region on the server ($status). '
          'Please tell your administrator.';
    }
    return 'Photo upload failed ($status). Please try again.';
  }

  static Future<UploadOutcome> upload(
      AuthService auth, SiteTask task, List<EvidenceFile> files) async {
    if (files.isEmpty) return const UploadOutcome(evidence: []);
    if (task.id < 0) {
      // task lives on the phone only
      return const UploadOutcome(
          reason: 'this task list is stored on the phone (the server task list was not reachable)');
    }

    // 1. Ask the server for upload links.
    final res = await auth.authenticatedPost(
      ApiConfig.siteTaskEvidencePresignUrl(task.id),
      {
        'files': [
          for (final f in files)
            {
              'name': f.name,
              'content_type': f.contentType,
              'size_bytes': f.sizeBytes,
              'media_type': 'image',
            }
        ],
      },
    );
    if (res == null ||
        res.statusCode >= 500 ||
        res.statusCode == 503 ||
        (res.statusCode == 404 && decodeBody(res) is! Map)) {
      return UploadOutcome(
        statusCode: res?.statusCode,
        reason: res == null
            ? 'no connection to the server'
            : (decodeBody(res) is Map
                ? errorMessage(res, fallback: 'storage not available')
                : 'the photo-upload route does not exist on the server'),
      );
    }
    if (res.statusCode != 200) {
      return UploadOutcome(error: errorMessage(res, fallback: 'Could not prepare the upload'));
    }
    final links = extractList(decodeBody(res), keys: const ['files']);
    if (links.length != files.length) {
      return const UploadOutcome(error: 'Upload service returned an unexpected answer.');
    }

    // 2. Upload every file directly to S3.
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      final link = links[i];
      try {
        final bytes = await File(f.path).readAsBytes();
        final headers = <String, String>{
          for (final e in (link['headers'] as Map? ?? {}).entries) '${e.key}': '${e.value}',
        };
        // Straight to S3: no JWT, the exact headers returned, and NO redirects
        // (a 301/307 means the server's bucket region setting is wrong).
        final req = http.Request('PUT', Uri.parse(link['upload_url'].toString()))
          ..followRedirects = false
          ..headers.addAll(headers)
          ..bodyBytes = bytes;
        final client = http.Client();
        int status;
        try {
          final streamed = await client.send(req).timeout(const Duration(seconds: 90));
          status = streamed.statusCode;
          await streamed.stream.drain<void>();
        } finally {
          client.close();
        }
        if (status != 200 && status != 204) {
          return UploadOutcome(error: _putError(status));
        }
      } on TimeoutException {
        return const UploadOutcome(error: 'Photo upload timed out. Check your signal and try again.');
      } catch (_) {
        return const UploadOutcome(error: 'Photo upload failed. Check your signal and try again.');
      }
      out.add({
        'key': link['key'],
        'media_type': 'image',
        'name': f.name,
        'content_type': f.contentType,
        'size_bytes': f.sizeBytes,
        'captured_at': f.capturedAt.toUtc().toIso8601String(),
        'analysis': f.analysis,
      });
    }
    return UploadOutcome(evidence: out);
  }
}
