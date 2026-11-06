import 'dart:convert';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/attendance.dart';

/// A photo or video kept on this device for a task.
class LocalMedia {
  final String id;
  final String path;
  final String type; // photo | video
  final String name;
  final DateTime capturedAt;
  final int sizeBytes;
  final int durationSeconds;
  final bool synced; // photo thumbnail + metadata already saved to the database

  const LocalMedia({
    required this.id,
    required this.path,
    required this.type,
    required this.name,
    required this.capturedAt,
    required this.sizeBytes,
    required this.durationSeconds,
    required this.synced,
  });

  bool get isVideo => type == 'video';

  LocalMedia copyWith({bool? synced}) => LocalMedia(
        id: id,
        path: path,
        type: type,
        name: name,
        capturedAt: capturedAt,
        sizeBytes: sizeBytes,
        durationSeconds: durationSeconds,
        synced: synced ?? this.synced,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'type': type,
        'name': name,
        'captured_at': capturedAt.toIso8601String(),
        'size_bytes': sizeBytes,
        'duration_seconds': durationSeconds,
        'synced': synced,
      };

  /// Metadata sent to the database (the file itself stays on the device).
  Map<String, dynamic> toMetadata() => {
        'name': name,
        'type': type,
        'duration_seconds': durationSeconds,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'size_bytes': sizeBytes,
        'stored_on_device': true,
      };

  factory LocalMedia.fromJson(Map<String, dynamic> j) => LocalMedia(
        id: j['id'].toString(),
        path: j['path'].toString(),
        type: j['type'].toString(),
        name: j['name'].toString(),
        capturedAt: DateTime.tryParse(j['captured_at'].toString()) ?? DateTime.now(),
        sizeBytes: toInt(j['size_bytes']),
        durationSeconds: toInt(j['duration_seconds']),
        synced: j['synced'] == true,
      );
}

/// Photos and videos are copied into the app's private storage on this phone,
/// so they survive restarts and are never lost if an upload fails.
class EvidenceStore {
  EvidenceStore._();

  static String _key(String taskKey) => 'evidence_$taskKey';

  static Future<List<LocalMedia>> list(String taskId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(taskId));
    if (raw == null) return [];
    try {
      final items = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => LocalMedia.fromJson(Map<String, dynamic>.from(e)))
          .where((m) => File(m.path).existsSync())
          .toList();
      return items;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(String taskId, List<LocalMedia> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(taskId), jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  static bool looksLikeVideo(XFile f) {
    final n = f.name.toLowerCase();
    return (f.mimeType ?? '').startsWith('video') ||
        n.endsWith('.mp4') ||
        n.endsWith('.mov') ||
        n.endsWith('.mkv') ||
        n.endsWith('.3gp') ||
        n.endsWith('.webm') ||
        n.endsWith('.avi');
  }

  static String _stamp(DateTime d) =>
      '${d.year}${two(d.month)}${two(d.day)}_${two(d.hour)}${two(d.minute)}${two(d.second)}';

  /// Copy [file] into local storage and register it for the task.
  static Future<LocalMedia> add(String taskId, XFile file, {required bool video}) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/evidence/$taskId');
    if (!await dir.exists()) await dir.create(recursive: true);

    final now = DateTime.now();
    final ext = video
        ? (file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'mp4')
        : 'jpg';
    final name = '${video ? 'VID' : 'IMG'}_${_stamp(now)}.$ext';
    final dest = File('${dir.path}/$name');
    await File(file.path).copy(dest.path);

    var duration = 0;
    if (video) {
      try {
        final c = VideoPlayerController.file(dest);
        await c.initialize();
        duration = c.value.duration.inSeconds;
        await c.dispose();
      } catch (_) {}
    }

    final media = LocalMedia(
      id: '${now.microsecondsSinceEpoch}',
      path: dest.path,
      type: video ? 'video' : 'photo',
      name: name,
      capturedAt: now,
      sizeBytes: await dest.length(),
      durationSeconds: duration,
      synced: false,
    );
    final all = await list(taskId);
    await _write(taskId, [...all, media]);
    return media;
  }

  static Future<void> remove(String taskId, LocalMedia m) async {
    try {
      final f = File(m.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    final all = await list(taskId);
    await _write(taskId, all.where((e) => e.id != m.id).toList());
  }

  static Future<void> markSynced(String taskId, Set<String> ids) async {
    final all = await list(taskId);
    await _write(taskId, [
      for (final m in all) ids.contains(m.id) ? m.copyWith(synced: true) : m,
    ]);
  }
}
