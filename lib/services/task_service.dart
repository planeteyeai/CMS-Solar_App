import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/site_task.dart';
import '../models/user_profile.dart';
import 'local_task_repo.dart';
import 'api_helpers.dart';
import 'auth_service.dart';

class TaskListResult {
  final int? projectId;
  final String projectName;
  final TaskSummary summary;
  final List<SiteTask> tasks;
  const TaskListResult({
    required this.projectId,
    required this.projectName,
    required this.summary,
    required this.tasks,
  });
}

class TaskSaveResult {
  final SiteTask? task;
  final TaskUpdate? update;
  final String? error;
  final bool local; // saved on the phone, will upload later
  const TaskSaveResult({this.task, this.update, this.error, this.local = false});
  bool get ok => task != null;
}

/// A 404 without a JSON body means the route itself does not exist on the
/// server, i.e. the backend has not been updated yet.
String _taskError(dynamic res, String fallback) {
  if (res != null && res.statusCode == 404 && decodeBody(res) is! Map) {
    return 'The server does not have the task feature yet. '
        'Ask your administrator to deploy the latest backend update and run the database migration.';
  }
  return errorMessage(res, fallback: fallback);
}

class TaskException implements Exception {
  final String message;
  const TaskException(this.message);
  @override
  String toString() => message;
}

/// Calls to the site-task endpoints.
class TaskApi {
  TaskApi._();

  /// True while the server cannot provide the task feature (not deployed yet,
  /// server error, or no signal). Site engineers then work from the phone.
  static bool localMode = false;

  static bool _isSiteEngineer(AuthService a) => a.profile?.appRole == AppRole.siteEngineer;

  static bool _unavailable(http.Response? res) =>
      res == null ||
      res.statusCode >= 500 ||
      (res.statusCode == 404 && decodeBody(res) is! Map);

  static Future<TaskListResult> fetchTasks(AuthService auth, {int? projectId}) async {
    final uri = Uri.parse(ApiConfig.siteTasksUrl).replace(
        queryParameters: projectId == null ? null : {'project': '$projectId'});
    final res = await auth.authenticatedGet(uri.toString());
    if (_unavailable(res) && _isSiteEngineer(auth)) {
      localMode = true;
      return LocalTaskRepo.loadTasks(auth, projectId);
    }
    if (res == null || res.statusCode != 200) {
      throw TaskException(_taskError(res, 'Could not load tasks'));
    }
    localMode = false;
    final d = decodeBody(res);
    final m = d is Map ? d : <dynamic, dynamic>{};
    final proj = m['project'] is Map ? Map<String, dynamic>.from(m['project'] as Map) : null;
    final tasks = extractList(m, keys: const ['tasks']).map(SiteTask.fromJson).toList();
    return TaskListResult(
      projectId: proj == null ? null : (proj['id'] as num?)?.toInt(),
      projectName: proj?['name']?.toString() ?? '',
      summary: m['summary'] is Map
          ? TaskSummary.fromJson(Map<String, dynamic>.from(m['summary'] as Map))
          : TaskSummary.empty,
      tasks: tasks,
    );
  }

  /// Task + full update history (newest first, with photo thumbnails).
  static Future<(SiteTask, List<TaskUpdate>)> fetchDetail(AuthService auth, int taskId) async {
    if (taskId < 0) return LocalTaskRepo.detail(auth, taskId);
    final res = await auth.authenticatedGet(ApiConfig.siteTaskUrl(taskId));
    if (res == null || res.statusCode != 200) {
      throw TaskException(_taskError(res, 'Could not load task history'));
    }
    final d = decodeBody(res) as Map;
    return (
      SiteTask.fromJson(Map<String, dynamic>.from(d['task'] as Map)),
      extractList(d, keys: const ['history']).map(TaskUpdate.fromJson).toList(),
    );
  }

  /// Save a progress update. Site engineers fall back to saving on the phone
  /// when the server is unavailable ([allowLocal] = false disables that).
  static Future<TaskSaveResult> saveUpdate(
    AuthService auth,
    SiteTask task,
    Map<String, dynamic> payload, {
    bool allowLocal = true,
  }) async {
    final canLocal = allowLocal && _isSiteEngineer(auth);
    if (task.id < 0) {
      // Task came from the on-phone list: keep it on the phone.
      return LocalTaskRepo.saveUpdate(auth, task, payload);
    }
    // Local-only helpers are not sent to the server.
    final serverPayload = Map<String, dynamic>.from(payload)
      ..remove('evidence_meta')
      ..remove('photo_paths');
    final res = await auth.authenticatedPost(
      ApiConfig.siteTaskUpdatesUrl(task.id),
      serverPayload,
      timeout: const Duration(seconds: 60),
    );
    if (_unavailable(res) && canLocal) {
      return LocalTaskRepo.saveUpdate(auth, task, payload);
    }
    if (res == null || (res.statusCode != 201 && res.statusCode != 200)) {
      return TaskSaveResult(error: _taskError(res, 'Could not save progress'));
    }
    final d = decodeBody(res) as Map;
    return TaskSaveResult(
      task: SiteTask.fromJson(Map<String, dynamic>.from(d['task'] as Map)),
      update: TaskUpdate.fromJson(Map<String, dynamic>.from(d['update'] as Map)),
    );
  }

  /// History feed. Site engineers get their project, managers get everything
  /// they can access.
  static Future<List<TaskUpdate>> fetchFeed(
    AuthService auth, {
    int? projectId,
    int? userId,
    int? taskId,
    int limit = 150,
  }) async {
    if (localMode && _isSiteEngineer(auth)) {
      return LocalTaskRepo.feed(auth, projectId: projectId);
    }
    final qp = <String, String>{'limit': '$limit'};
    if (projectId != null) qp['project'] = '$projectId';
    if (userId != null) qp['user'] = '$userId';
    if (taskId != null) qp['task'] = '$taskId';
    final uri = Uri.parse(ApiConfig.siteTaskFeedUrl).replace(queryParameters: qp);
    final res = await auth.authenticatedGet(uri.toString());
    if (_unavailable(res) && _isSiteEngineer(auth)) {
      localMode = true;
      return LocalTaskRepo.feed(auth, projectId: projectId);
    }
    if (res == null || res.statusCode != 200) {
      throw TaskException(_taskError(res, 'Could not load updates'));
    }
    return extractList(decodeBody(res)).map(TaskUpdate.fromJson).toList();
  }
}

/// Task list of the logged-in Site Engineer's project, shared by all tabs.
class TaskStore extends ChangeNotifier {
  bool _loading = false;
  bool _loaded = false;
  String? _error;
  int? _projectId;
  String _projectName = '';
  TaskSummary _summary = TaskSummary.empty;
  List<SiteTask> _tasks = [];
  bool _local = false;
  int _pending = 0;

  /// Working from the phone (server task feature unavailable).
  bool get isLocal => _local;

  /// Updates saved on the phone that are waiting to upload.
  int get pendingSync => _pending;

  bool get loading => _loading;
  bool get loaded => _loaded;
  String? get error => _error;
  int? get projectId => _projectId;
  String get projectName => _projectName;
  TaskSummary get summary => _summary;
  List<SiteTask> get tasks => _tasks;

  SiteTask? byOrder(int order) {
    for (final t in _tasks) {
      if (t.order == order) return t;
    }
    return null;
  }

  SiteTask? byId(int id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  int? _preferredProjectId(AuthService auth) {
    final p = auth.profile;
    if (p == null) return null;
    if (p.assignedProject != null && p.assignedProject!.id != 0) {
      return p.assignedProject!.id;
    }
    final active = p.activeAssignments;
    if (active.isNotEmpty) return active.first.id;
    return p.assignedProjects.isNotEmpty ? p.assignedProjects.first.id : null;
  }

  Future<void> load(AuthService auth, {bool silent = false}) async {
    if (_loading) return;
    _loading = true;
    if (!silent) notifyListeners();
    try {
      var r = await TaskApi.fetchTasks(auth, projectId: _preferredProjectId(auth));
      _local = TaskApi.localMode;
      if (!_local && r.projectId != null) {
        // Server is back: upload whatever was saved on the phone, then refresh.
        final sent = await LocalTaskRepo.syncPending(auth, r.tasks, r.projectId!);
        if (sent > 0) r = await TaskApi.fetchTasks(auth, projectId: r.projectId);
      }
      _pending = await LocalTaskRepo.pendingCount(auth, r.projectId);
      _projectId = r.projectId;
      _projectName = r.projectName;
      _summary = r.summary;
      _tasks = r.tasks;
      _error = null;
      _loaded = true;
    } catch (e) {
      _error = e.toString().replaceFirst('TaskException: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Apply a saved update immediately (before the next refresh).
  void applySaved(SiteTask updated) {
    _tasks = [for (final t in _tasks) t.id == updated.id ? updated : t];
    final total = _tasks.length;
    final done = _tasks.where((t) => t.isDone).length;
    final prog = _tasks.where((t) => t.isInProgress).length;
    _summary = TaskSummary(
      total: total,
      done: done,
      inProgress: prog,
      pending: total - done - prog,
      overall: total == 0 ? 0 : _tasks.fold<double>(0, (s, t) => s + t.progress) / total,
    );
    notifyListeners();
  }

  void reset() {
    _loading = false;
    _loaded = false;
    _error = null;
    _projectId = null;
    _projectName = '';
    _summary = TaskSummary.empty;
    _tasks = [];
    _local = false;
    _pending = 0;
    TaskApi.localMode = false;
    notifyListeners();
  }
}
