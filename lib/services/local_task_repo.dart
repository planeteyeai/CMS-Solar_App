import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/site_task.dart';
import 'auth_service.dart';
import 'evidence_uploader.dart';
import 'uuid_util.dart';
import 'task_service.dart';

/// On-device copy of the task list and update history.
///
/// Used by the Site Engineer when the server cannot provide the task feature
/// (backend not updated yet, server error, or no signal). Everything is kept
/// in the phone's storage and uploaded automatically (oldest first) the next
/// time the server answers.
class LocalTaskRepo {
  LocalTaskRepo._();

  static const defaults = <(String, String)>[
    ('Site Survey & Marking', 'Topographical survey and marking of boundaries, blocks and structure positions as per drawings.'),
    ('Excavation', 'Excavation of land as per drawing and specifications. Upload site photos/videos as evidence of completed work.'),
    ('Foundation / RCC Work', 'Foundation excavation, PCC, reinforcement and RCC casting for equipment and structures.'),
    ('Module Mounting Structure', 'Erection of module mounting structures (piles, columns, purlins) with alignment and tilt checks.'),
    ('Solar Panel Installation', 'Mounting and clamping of PV modules on the structures, including inter-row alignment.'),
    ('DC Cable Laying', 'Laying, dressing and termination of DC string cables along trays and trenches.'),
    ('Inverter Installation', 'Placement, levelling and connection of string / central inverters.'),
    ('AC Cable Laying', 'Trenching and laying of AC cables between inverters, transformers and panels.'),
    ('Earthing Installation', 'Earth pits, strips and connections for structures, inverters and equipment.'),
    ('Lightning Arrestor', 'Installation of lightning arrestors and their earthing connections.'),
    ('Transformer Installation', 'Transformer foundation, placement, oil filling and connections.'),
    ('HT/LT Panel Installation', 'Erection and wiring of HT/LT switchgear and panels.'),
    ('Cable Termination', 'Glanding, lugging and termination of all power and control cables.'),
    ('Testing & Commissioning', 'Insulation, continuity, IV-curve, protection and functional tests; commissioning.'),
    ('Final Inspection', 'Final walk-down, punch-list closure and handover inspection.'),
  ];

  /// Local task ids are negative so they never clash with server ids.
  static int idFor(int projectId, int order) => -(projectId * 100 + order);

  static String _tk(int uid, int pid) => 'local_tasks_${uid}_$pid';
  static String _uk(int uid, int pid) => 'local_updates_${uid}_$pid';

  static int _preferredProject(AuthService auth) {
    final p = auth.profile;
    if (p == null) return 0;
    if (p.assignedProject != null && p.assignedProject!.id != 0) return p.assignedProject!.id;
    if (p.activeAssignments.isNotEmpty) return p.activeAssignments.first.id;
    return p.assignedProjects.isNotEmpty ? p.assignedProjects.first.id : 0;
  }

  static String _projectName(AuthService auth, int pid) {
    final p = auth.profile;
    if (p == null) return '';
    for (final a in p.assignedProjects) {
      if (a.id == pid) return a.projectName;
    }
    if (p.assignedProject != null && p.assignedProject!.id == pid) {
      return p.assignedProject!.projectName;
    }
    return p.primaryProjectName ?? '';
  }

  // ── storage ──────────────────────────────────────────────────────────────

  static List<Map<String, dynamic>> _seed(int pid, String pname) => [
        for (var i = 0; i < defaults.length; i++)
          {
            'id': idFor(pid, i + 1),
            'project_id': pid,
            'project_name': pname,
            'order': i + 1,
            'name': defaults[i].$1,
            'description': defaults[i].$2,
            'progress_percent': 0.0,
            'status': 'pending',
            'last_updated_at': null,
            'last_updated_by': '',
            'updates_count': 0,
          }
      ];

  static Future<List<Map<String, dynamic>>> _taskMaps(int uid, int pid, String pname) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_tk(uid, pid));
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }
    final seeded = _seed(pid, pname);
    await prefs.setString(_tk(uid, pid), jsonEncode(seeded));
    return seeded;
  }

  static Future<List<Map<String, dynamic>>> _updateMaps(int uid, int pid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_uk(uid, pid));
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeTasks(int uid, int pid, List<Map<String, dynamic>> v) async =>
      (await SharedPreferences.getInstance()).setString(_tk(uid, pid), jsonEncode(v));

  static Future<void> _writeUpdates(int uid, int pid, List<Map<String, dynamic>> v) async =>
      (await SharedPreferences.getInstance()).setString(_uk(uid, pid), jsonEncode(v));

  static TaskSummary _summary(List<SiteTask> tasks) {
    final done = tasks.where((t) => t.isDone).length;
    final prog = tasks.where((t) => t.isInProgress).length;
    return TaskSummary(
      total: tasks.length,
      done: done,
      inProgress: prog,
      pending: tasks.length - done - prog,
      overall: tasks.isEmpty ? 0 : tasks.fold<double>(0, (s, t) => s + t.progress) / tasks.length,
    );
  }

  static String _statusFor(double p) => p >= 100 ? 'done' : (p > 0 ? 'in_progress' : 'pending');

  // ── operations (mirror the server API) ───────────────────────────────────

  static Future<TaskListResult> loadTasks(AuthService auth, int? projectId) async {
    final pid = projectId ?? _preferredProject(auth);
    final pname = _projectName(auth, pid);
    final maps = await _taskMaps(auth.profile!.id, pid, pname);
    final tasks = maps.map(SiteTask.fromJson).toList()..sort((a, b) => a.order.compareTo(b.order));
    return TaskListResult(projectId: pid, projectName: pname, summary: _summary(tasks), tasks: tasks);
  }

  /// Save an update on the phone. [task] is the task as the UI currently shows it.
  static Future<TaskSaveResult> saveUpdate(
      AuthService auth, SiteTask task, Map<String, dynamic> payload) async {
    final user = auth.profile!;
    final pid = task.projectId;
    final tasks = await _taskMaps(user.id, pid, task.projectName);
    final i = tasks.indexWhere((t) => t['order'] == task.order);

    final before = task.progress;
    final after = ((payload['progress_percent'] as num?)?.toDouble() ?? before).clamp(0.0, 100.0).toDouble();
    final aiPct = (payload['ai_progress_percent'] as num?)?.toDouble();
    final summary = (payload['summary'] ?? '').toString();
    final aiSummary = (payload['ai_summary'] ?? '').toString();
    final analysisMap = payload['analysis'];
    final qtyEdited = analysisMap is Map && analysisMap['quantities_edited'] == true;
    final edited = aiPct == null || (after - aiPct).abs() > 0.5 ||
        (aiSummary.isNotEmpty && summary != aiSummary) ||
        qtyEdited;
    final now = DateTime.now();
    final paths = (payload['photo_paths'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];

    final stored = Map<String, dynamic>.from(payload)
      ..putIfAbsent('client_uuid', () => newUuidV4()) // same value on every retry (idempotent)
      ..remove('photos')
      ..remove('evidence')
      ..remove('photo_paths');

    final updates = await _updateMaps(user.id, pid);
    updates.add({
      'id': -now.microsecondsSinceEpoch,
      'task_id': task.id,
      'task_name': task.name,
      'task_order': task.order,
      'project_id': pid,
      'project_name': task.projectName,
      'user_name': user.fullName,
      'username': user.username,
      'progress_before': before,
      'progress_after': after,
      'ai_progress_percent': aiPct,
      'edited_by_user': edited,
      'summary': summary,
      'ai_summary': aiSummary,
      'findings': payload['findings'] ?? [],
      'remarks': payload['remarks'] ?? '',
      'analysis': payload['analysis'] ?? {},
      'media': payload['media'] ?? [],
      'photo_count': paths.length,
      'photo_paths': paths,
      'lat': payload['lat'],
      'lon': payload['lon'],
      'created_at': now.toIso8601String(),
      'synced': false,
      'payload': stored,
    });
    await _writeUpdates(user.id, pid, updates);

    final updatesCount = updates.where((u) => u['task_order'] == task.order).length;
    final status = _statusFor(after);
    if (i >= 0) {
      tasks[i]
        ..['progress_percent'] = after
        ..['status'] = status
        ..['last_updated_at'] = now.toIso8601String()
        ..['last_updated_by'] = user.fullName
        ..['updates_count'] = updatesCount;
      await _writeTasks(user.id, pid, tasks);
    }

    final updatedTask = SiteTask(
      id: task.id,
      projectId: pid,
      projectName: task.projectName,
      order: task.order,
      name: task.name,
      description: task.description,
      progress: after,
      status: status,
      updatedAt: now,
      updatedBy: user.fullName,
      updatesCount: updatesCount,
    );
    return TaskSaveResult(
      task: updatedTask,
      update: TaskUpdate.fromJson(updates.last),
      local: true,
    );
  }

  static Future<(SiteTask, List<TaskUpdate>)> detail(AuthService auth, int taskId) async {
    final pid = (-taskId) ~/ 100;
    final order = (-taskId) % 100;
    final r = await loadTasks(auth, pid);
    final task = r.tasks.firstWhere((t) => t.order == order);
    final hist = await feed(auth, projectId: pid, order: order);
    return (task, hist);
  }

  static Future<List<TaskUpdate>> feed(AuthService auth, {int? projectId, int? order}) async {
    final pid = projectId ?? _preferredProject(auth);
    final raw = await _updateMaps(auth.profile!.id, pid);
    final list = raw
        .where((u) => order == null || u['task_order'] == order)
        .map(TaskUpdate.fromJson)
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(2000)).compareTo(a.createdAt ?? DateTime(2000)));
    return list;
  }

  static Future<int> pendingCount(AuthService auth, int? projectId) async {
    final pid = projectId ?? _preferredProject(auth);
    final raw = await _updateMaps(auth.profile!.id, pid);
    return raw.where((u) => u['synced'] != true).length;
  }

  /// Upload updates saved on the phone, oldest first. Returns how many were sent.
  static Future<int> syncPending(AuthService auth, List<SiteTask> serverTasks, int pid) async {
    final uid = auth.profile!.id;
    final raw = await _updateMaps(uid, pid);
    final pending = raw.where((u) => u['synced'] != true).toList()
      ..sort((a, b) => '${a['created_at']}'.compareTo('${b['created_at']}'));
    if (pending.isEmpty) return 0;

    var sent = 0;
    for (final u in pending) {
      SiteTask? target;
      for (final t in serverTasks) {
        if (t.order == u['task_order']) target = t;
      }
      if (target == null) break;

      final payload = Map<String, dynamic>.from(u['payload'] as Map? ?? {});
      // Updates queued by an older app version have no id yet: derive a stable one.
      if ((payload['client_uuid'] ?? '').toString().isEmpty) {
        payload['client_uuid'] = 'legacy-${u['id']}';
      }

      // Photos: upload to AWS S3 when available, otherwise send small thumbnails.
      final files = <EvidenceFile>[
        for (final m in (payload['evidence_meta'] as List? ?? const []))
          if (m is Map) EvidenceFile.fromJson(Map<String, dynamic>.from(m)),
      ].where((f) => File(f.path).existsSync()).toList();

      payload['evidence'] = <Map<String, dynamic>>[];
      payload['photos'] = <String>[];
      if (files.isNotEmpty) {
        final up = await EvidenceUploader.upload(auth, target, files);
        if (up.error != null) break; // retry on the next sync
        if (up.evidence != null) {
          payload['evidence'] = up.evidence;
        } else {
          final photos = <String>[];
          for (final f in files.take(3)) {
            photos.add(base64Encode(await File(f.path).readAsBytes()));
          }
          payload['photos'] = photos;
        }
      }

      final res = await TaskApi.saveUpdate(auth, target, payload, allowLocal: false);
      if (!res.ok) break;
      u['synced'] = true;
      sent++;
    }

    final remaining = raw.where((u) => u['synced'] != true).toList();
    if (remaining.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_uk(uid, pid));
      await prefs.remove(_tk(uid, pid));
    } else {
      await _writeUpdates(uid, pid, remaining);
    }
    return sent;
  }
}
