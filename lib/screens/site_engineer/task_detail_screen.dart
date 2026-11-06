import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/attendance.dart';
import '../../models/site_task.dart';
import '../../services/ai_service.dart';
import '../../services/auth_service.dart';
import '../../services/checkin_service.dart';
import '../../services/evidence_store.dart';
import '../../services/evidence_uploader.dart';
import '../../services/task_service.dart';
import '../../services/uuid_util.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_report.dart';
import '../../widgets/task_widgets.dart';
import '../../widgets/ui_kit.dart';

/// Task page: add evidence → AI estimates progress → engineer reviews/edits → save.
class TaskDetailScreen extends StatefulWidget {
  final int taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  final _picker = ImagePicker();
  final _summaryCtrl = TextEditingController();
  final _findingsCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();
  final List<_QtyDraft> _qtyRows = [];

  List<LocalMedia> _media = [];
  List<TaskUpdate> _history = [];
  bool _historyLoading = true;
  String? _historyError;

  TaskAnalysis? _analysis;
  List<String> _analysedIds = []; // media ids, same order as the photos sent to the AI

  /// One id per save attempt of the same draft. Re-sent on every retry so the
  /// server answers "already saved" (200) instead of creating a second history row.
  String? _clientUuid;

  /// Photos already uploaded to storage during this save (by file path), so a
  /// retry after a network error does not upload them again.
  final Map<String, Map<String, dynamic>> _uploaded = {};
  double _percent = 0;
  double? _aiPercent;
  bool _analysing = false;
  bool _saving = false;
  bool _adding = false;
  String? _aiError;

  int _order = 0;

  /// The task as currently listed. Falls back to the task number, because the
  /// id changes when the list switches between the server and this phone.
  SiteTask? _currentTask(TaskStore store) => store.byId(widget.taskId) ?? store.byOrder(_order);

  SiteTask get _task => _currentTask(context.read<TaskStore>())!;

  /// Stable key for local evidence: same whether the task came from the
  /// server or from the phone.
  String get _evKey => '${_task.projectId}_${_task.order}';

  @override
  void initState() {
    super.initState();
    _order = context.read<TaskStore>().byId(widget.taskId)?.order ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMedia();
      _loadHistory();
    });
  }

  @override
  void dispose() {
    _summaryCtrl.dispose();
    _findingsCtrl.dispose();
    _remarksCtrl.dispose();
    for (final r in _qtyRows) {
      r.dispose();
    }
    super.dispose();
  }

  void _replaceQuantities(List<QuantityReading> items) {
    final old = List<_QtyDraft>.from(_qtyRows);
    _qtyRows
      ..clear()
      ..addAll(items.map(_QtyDraft.fromReading));
    if (old.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in old) {
        r.dispose();
      }
    });
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _loadMedia() async {
    final m = await EvidenceStore.list(_evKey);
    if (mounted) setState(() => _media = m);
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final (t, h) = await TaskApi.fetchDetail(context.read<AuthService>(), _task.id);
      if (!mounted) return;
      context.read<TaskStore>().applySaved(t);
      setState(() {
        _history = h;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _historyError = e.toString().replaceFirst('TaskException: ', '');
        _historyLoading = false;
      });
    }
  }

  // ── Evidence ─────────────────────────────────────────────────────────────

  Future<void> _addFiles(List<XFile> files) async {
    if (files.isEmpty) return;
    setState(() => _adding = true);
    try {
      for (final f in files) {
        await EvidenceStore.add(_evKey, f, video: EvidenceStore.looksLikeVideo(f));
      }
      await _loadMedia();
      // New evidence makes the previous analysis out of date.
      if (_analysis != null) {
        _toast('Evidence added. Run the analysis again to include it.');
      }
    } catch (_) {
      _toast('Could not store the file on this device.');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _takePhoto() async {
    try {
      final f = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 1024, imageQuality: 65);
      if (f != null) await _addFiles([f]);
    } catch (_) {
      _toast('Could not open the camera. Check app permissions.');
    }
  }

  Future<void> _recordVideo() async {
    try {
      final f = await _picker.pickVideo(
          source: ImageSource.camera, maxDuration: const Duration(minutes: 2));
      if (f != null) await _addFiles([f]);
    } catch (_) {
      _toast('Could not open the camera. Check app permissions.');
    }
  }

  Future<void> _pickGallery() async {
    try {
      final files = await _picker.pickMultipleMedia(maxWidth: 1024, imageQuality: 65);
      await _addFiles(files);
    } catch (_) {
      _toast('Could not open the gallery. Check app permissions.');
    }
  }

  Future<void> _deleteMedia(LocalMedia m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete ${m.isVideo ? 'video' : 'photo'}?'),
        content: Text(m.synced
            ? 'This removes the file from this phone. The saved progress update keeps its record.'
            : 'This removes the file from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentRed),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await EvidenceStore.remove(_evKey, m);
      await _loadMedia();
    }
  }

  void _open(LocalMedia m) {
    if (m.isVideo) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => _VideoScreen(path: m.path, title: m.name)));
    } else {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(8),
          child: InteractiveViewer(child: Image.file(File(m.path))),
        ),
      );
    }
  }

  // ── AI analysis ──────────────────────────────────────────────────────────

  List<LocalMedia> get _newPhotos =>
      _media.where((m) => !m.isVideo && !m.synced).toList();

  Future<void> _analyse() async {
    _clientUuid = null; // a new analysis is a new draft
    final photos = _newPhotos;
    if (photos.isEmpty) {
      _toast('Add at least one new photo to analyse.');
      return;
    }
    final store = context.read<TaskStore>();
    setState(() {
      _analysing = true;
      _aiError = null;
    });
    try {
      final latest = photos.length > 4 ? photos.sublist(photos.length - 4) : photos;
      final images = <Uint8List>[
        for (final m in latest) await File(m.path).readAsBytes(),
      ];
      final result = await AiService.analyzeTask(
        auth: context.read<AuthService>(),
        images: images,
        task: _task,
        projectName: store.projectName,
      );
      if (!mounted) return;
      final pct = result.progressPercent.roundToDouble();
      setState(() {
        _analysis = result;
        _analysedIds = latest.map((m) => m.id).toList();
        _aiPercent = pct;
        _percent = pct;
        _summaryCtrl.text = result.summary;
        _findingsCtrl.text = [
          ...result.observations,
          ...result.safetyFindings.map((e) => 'Safety: $e'),
        ].join('\n');
        _replaceQuantities(result.quantities);
        _analysing = false;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _aiError = e.message;
        _analysing = false;
      });
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final a = _analysis;
    if (a == null || _saving) return;
    setState(() => _saving = true);

    final auth = context.read<AuthService>();
    final store = context.read<TaskStore>();
    final checkin = context.read<CheckInService>();

    final task = _task;
    final unsynced = _media.where((m) => !m.synced).toList();
    final photoItems = unsynced.where((m) => !m.isVideo).toList();

    // Each photo keeps the AI analysis of that photo.
    final files = <EvidenceFile>[
      for (final m in photoItems)
        EvidenceFile(
          path: m.path,
          name: m.name,
          contentType: EvidenceFile.contentTypeFor(m.name),
          sizeBytes: m.sizeBytes,
          capturedAt: m.capturedAt,
          analysis: _analysedIds.contains(m.id)
              ? a.forImage(_analysedIds.indexOf(m.id))
              : <String, dynamic>{},
        ),
    ];

    // The server accepts at most 6 photos per saved update; any extra photos stay
    // on the phone, are kept as "new", and can be analysed and saved next.
    const maxPhotos = 6;
    final batchItems = photoItems.take(maxPhotos).toList();
    final batchFiles = files.take(maxPhotos).toList();
    final extraPhotos = photoItems.length - batchItems.length;

    final pos = await checkin.lastKnownOrNull();
    _clientUuid ??= newUuidV4();

    // Photos go straight to AWS S3 (private). If storage is not available yet,
    // fall back to small thumbnails inside the update.
    List<Map<String, dynamic>> evidence = [];
    final photosB64 = <String>[];
    var usedFallback = false;
    var fallbackReason = '';
    if (batchFiles.isNotEmpty) {
      final pending = batchFiles.where((f) => !_uploaded.containsKey(f.path)).toList();
      if (pending.isNotEmpty) {
        final up = await EvidenceUploader.upload(auth, task, pending);
        if (up.error != null) {
          if (mounted) setState(() => _saving = false);
          _toast(up.error!);
          return;
        }
        if (up.evidence != null) {
          for (var i = 0; i < pending.length; i++) {
            _uploaded[pending[i].path] = up.evidence![i];
          }
        } else {
          usedFallback = true;
          fallbackReason = up.statusCode == null ? up.reason : '${up.reason} (HTTP ${up.statusCode})';
          for (final f in batchFiles.take(3)) {
            photosB64.add(base64Encode(await File(f.path).readAsBytes()));
          }
        }
      }
      if (!usedFallback) {
        evidence = [
          for (final f in batchFiles)
            {
              ..._uploaded[f.path]!,
              'analysis': f.analysis,
              if (pos != null) 'lat': pos.latitude,
              if (pos != null) 'lon': pos.longitude,
            }
        ];
      }
    }

    final savedQty =
        _qtyRows.map((r) => r.toReading()).where((q) => !q.isEmpty).toList();
    final analysis = a.toJson();
    analysis['quantities'] = savedQty.map((q) => q.toJson()).toList();
    analysis['ai_quantities'] = a.quantities.map((q) => q.toJson()).toList();
    analysis['quantities_edited'] = !QuantityReading.sameList(savedQty, a.quantities);

    final result = await TaskApi.saveUpdate(auth, task, {
      'client_uuid': _clientUuid,
      'photo_paths': batchFiles.take(3).map((f) => f.path).toList(),
      'evidence_meta': batchFiles.map((f) => f.toJson()).toList(),
      'evidence': evidence,
      'photos': photosB64,
      'progress_percent': _percent,
      'ai_progress_percent': _aiPercent,
      'summary': _summaryCtrl.text.trim(),
      'ai_summary': a.summary,
      'findings': _findingsCtrl.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      'remarks': _remarksCtrl.text.trim(),
      'analysis': analysis,
      'media': unsynced.map((m) => m.toMetadata()).toList(),
      'lat': pos?.latitude,
      'lon': pos?.longitude,
    });

    if (!mounted) return;
    if (!result.ok) {
      setState(() => _saving = false);
      _toast(result.error ?? 'Could not save. Please try again.');
      return;
    }

    // Mark a photo as saved ONLY when it really was stored; otherwise keep it so
    // it is not silently lost. Videos are metadata only (the file stays on the phone).
    final syncedIds = <String>{for (final m in unsynced) if (m.isVideo) m.id};
    String? warning;
    final upd = result.update;
    final storedOnServer = upd == null
        ? 0
        : [upd.photoCount, upd.evidenceCount, upd.evidence.length].reduce((a, b) => a > b ? a : b);
    if (batchItems.isNotEmpty) {
      if (result.local) {
        // Saved on the phone; the photos upload together with the update later.
        syncedIds.addAll(batchItems.map((m) => m.id));
      } else if (!usedFallback) {
        syncedIds.addAll(batchItems.map((m) => m.id)); // uploaded to storage and attached
      } else if (storedOnServer > 0) {
        syncedIds.addAll(batchItems.take(3).map((m) => m.id));
        if (batchItems.length > 3) {
          warning = 'Progress saved. Photo storage is not available ($fallbackReason), so only the first 3 '
              'photos were kept as small copies. The others stay on this phone.';
        }
      } else {
        warning = 'Progress saved, but the photos were NOT stored on the server: $fallbackReason. '
            'They are kept on this phone. Ask your administrator to enable photo storage.';
      }
    }
    await EvidenceStore.markSynced(_evKey, syncedIds);
    _clientUuid = null;
    _uploaded.clear();
    store.applySaved(result.task!);
    await _loadMedia();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _analysis = null;
      _analysedIds = [];
      _aiPercent = null;
      _summaryCtrl.clear();
      _findingsCtrl.clear();
      _remarksCtrl.clear();
      _replaceQuantities(const []);
    });
    final extraNote = extraPhotos > 0
        ? ' $extraPhotos more photo${extraPhotos == 1 ? '' : 's'} are still waiting: analyse and save again to store them.'
        : '';
    final message = warning ??
        (result.local
            ? 'Saved on this phone: ${result.task!.progress.round()}%. It will upload automatically when the server is ready.'
            : 'Progress saved: ${result.task!.progress.round()}% · visible to your team lead, manager and superadmin.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message + extraNote),
      duration: Duration(seconds: (warning != null || extraNote.isNotEmpty) ? 10 : 4),
    ));
    _loadHistory();
    store.load(auth, silent: true);
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final store = context.watch<TaskStore>();
    final task = _currentTask(store);
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task Details')),
        body: const EmptyState(icon: Icons.error_outline_rounded, title: 'Task not found'),
      );
    }
    final shownPercent = _analysis != null ? _percent : task.progress;
    final c = progressColor(shownPercent);
    final edited = _aiPercent != null && (_percent - _aiPercent!).abs() > 0.5;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('Task Details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          // Header
          AppCard(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              PercentRing(percent: shownPercent, color: c, size: 104),
              const SizedBox(width: 18),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Pill('Task ${task.order} of ${store.tasks.length}', color: AppTheme.textSecondary),
                  const SizedBox(height: 8),
                  Text(task.name,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                          height: 1.15)),
                  const SizedBox(height: 8),
                  TaskStatusPill(task),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          if (task.description.isNotEmpty)
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.info_rounded, color: AppTheme.accent, size: 20),
                  SizedBox(width: 8),
                  Text('Task Description',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                Text(task.description,
                    style: TextStyle(color: AppTheme.textSecondary, height: 1.45)),
              ]),
            ),
          const SizedBox(height: 12),

          // Evidence
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.add_a_photo_rounded, color: AppTheme.accent, size: 20),
                SizedBox(width: 8),
                Text('Add Site Evidence',
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 6),
              Text(
                'Add photos or videos from your gallery or capture using your camera. Videos stay on this phone; photos are used for the AI estimate.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: _EvidenceButton(
                        icon: Icons.photo_camera_rounded,
                        label: 'Take Photo',
                        sub: 'Open Camera',
                        color: AppTheme.accent,
                        onTap: _adding ? null : _takePhoto)),
                const SizedBox(width: 10),
                Expanded(
                    child: _EvidenceButton(
                        icon: Icons.videocam_rounded,
                        label: 'Record Video',
                        sub: 'Capture Video',
                        color: AppTheme.aiColor,
                        onTap: _adding ? null : _recordVideo)),
                const SizedBox(width: 10),
                Expanded(
                    child: _EvidenceButton(
                        icon: Icons.photo_library_rounded,
                        label: 'Choose from Gallery',
                        sub: 'Select Files',
                        color: AppTheme.accentGreen,
                        onTap: _adding ? null : _pickGallery)),
              ]),
              if (_adding)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ]),
          ),

          if (_media.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.folder_rounded, color: AppTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Uploaded Files (${_media.length})',
                      style: TextStyle(
                          color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _media.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _MediaTile(
                      media: _media[i],
                      onOpen: () => _open(_media[i]),
                      onDelete: () => _deleteMedia(_media[i]),
                    ),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),

          // Progress estimate: a plain action card (no description text, no AI styling)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.trending_up_rounded, color: AppTheme.accent, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Progress Estimate',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ]),
              if (_aiError != null) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, color: AppTheme.accentRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(_aiError!,
                          style: TextStyle(color: AppTheme.textPrimary, height: 1.4))),
                ]),
              ],
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: (_analysing || _saving || _newPhotos.isEmpty) ? null : _analyse,
                  icon: _analysing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.trending_up_rounded, size: 20),
                  label: Text(_analysing
                      ? 'ESTIMATING…'
                      : (_analysis == null ? 'ESTIMATE PROGRESS' : 'ESTIMATE AGAIN')),
                ),
              ),
            ]),
          ),

          if (_analysis != null) ...[
            // The review / edit card comes first; the assistant's notes (including any
            // safety observations) follow it, so nothing alarming is the first thing seen.
            const SizedBox(height: 12),
            _reviewCard(edited),
            const SizedBox(height: 12),
            AppCard(
              borderColor: AppTheme.aiColor.withOpacity(0.3),
              child: AiReportView(analysis: _analysis!, showOverview: false),
            ),
          ],

          // History
          SectionTitle('Progress history (${_history.length})'),
          if (_historyLoading && _history.isEmpty)
            const Padding(
                padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_historyError != null && _history.isEmpty)
            AppCard(
              child: Column(children: [
                Text(_historyError!, style: TextStyle(color: AppTheme.textPrimary)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _loadHistory, child: const Text('RETRY')),
              ]),
            )
          else if (_history.isEmpty)
            AppCard(
                child: Text('No updates saved for this task yet.',
                    style: TextStyle(color: AppTheme.textSecondary)))
          else
            for (final u in _history)
              TaskUpdateTile(
                update: u,
                showTask: false,
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => TaskUpdateDetailScreen(update: u))),
              ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(context).padding.bottom * 0),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _analysis != null && !_saving
                    ? AppTheme.primaryGradient
                    : null,
                color: _analysis != null && !_saving ? null : AppTheme.surfaceElev,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: (_analysis != null && !_saving) ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_saving
                    ? 'SAVING…'
                    : (_analysis == null ? 'ESTIMATE TO ENABLE SAVE' : 'SAVE PROGRESS')),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewCard(bool edited) {
    final a = _analysis!;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.edit_note_rounded, color: AppTheme.accent, size: 22),
          ),
          const SizedBox(width: 12),
          Text('Review & Edit',
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          Pill('AI ESTIMATE ${_aiPercent!.round()}%', color: AppTheme.aiColor, icon: Icons.smart_toy_rounded),
          Pill('CONFIDENCE ${a.confidence}%', color: AppTheme.textSecondary),
          Pill('${a.riskLevel} RISK', color: softRiskColor(a.riskLevel)),
        ]),
        const SizedBox(height: 16),

        // Percentage control
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElev,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text('Completion Percentage',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 15)),
              ),
              _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => setState(() => _percent = (_percent - 5).clamp(0, 100).toDouble())),
              SizedBox(
                width: 92,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${_percent.round()}%',
                      textAlign: TextAlign.center,
                      style: AppTheme.numStyle(size: 34, letterSpacing: -1)),
                ),
              ),
              _StepButton(
                  icon: Icons.add_rounded,
                  onTap: () => setState(() => _percent = (_percent + 5).clamp(0, 100).toDouble())),
            ]),
            Slider(
              value: _percent,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _percent = v.roundToDouble()),
            ),
          ]),
        ),
        if (edited)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Icon(Icons.edit_rounded, size: 14, color: AppTheme.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Edited from the AI estimate (${_aiPercent!.round()}%)',
                    style: TextStyle(color: AppTheme.amber, fontSize: 12.5)),
              ),
              TextButton(
                onPressed: () => setState(() => _percent = _aiPercent!),
                child: const Text('RESET'),
              ),
            ]),
          ),

        const SizedBox(height: 14),
        Text('Summary',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        const SizedBox(height: 6),
        TextField(controller: _summaryCtrl, minLines: 3, maxLines: 6,
            decoration: const InputDecoration(hintText: 'Describe the work done')),

        const SizedBox(height: 14),
        _quantityEditor(),

        const SizedBox(height: 14),
        Text('Findings (one per line)',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        const SizedBox(height: 6),
        TextField(controller: _findingsCtrl, minLines: 3, maxLines: 8,
            decoration: const InputDecoration(hintText: 'Add or remove findings')),

        const SizedBox(height: 14),
        Text('Remarks (Optional)',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
        const SizedBox(height: 6),
        TextField(controller: _remarksCtrl, minLines: 2, maxLines: 5,
            decoration: const InputDecoration(hintText: 'Add any notes about the work done…')),

        if (_analysedIds.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Per-photo analysis',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          const SizedBox(height: 8),
          for (var i = 0; i < _analysedIds.length; i++) _photoAnalysisRow(i, a),
        ],

        if (a.recommendations.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('AI suggestions',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          const SizedBox(height: 6),
          for (final r in a.recommendations)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: AppTheme.aiColor)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(r,
                        style: TextStyle(color: AppTheme.textSecondary, height: 1.35))),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _quantityEditor() {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        );

    Widget field(TextEditingController c, String label, {TextInputType? keyboard}) => TextField(
          controller: c,
          keyboardType: keyboard,
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
          decoration: deco(label),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Measured quantities',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
      const SizedBox(height: 4),
      Text(
        'Number, size, material and quantity are separate fields. Edit any value before saving.',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.35),
      ),
      const SizedBox(height: 8),
      if (_qtyRows.isEmpty)
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Nothing measurable was read from the photos. Add a row if you counted something.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
        ),
      for (var i = 0; i < _qtyRows.length; i++)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElev,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Item ${i + 1}',
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final row = _qtyRows[i];
                  setState(() => _qtyRows.removeAt(i));
                  WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
                },
                icon: Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 18),
              ),
            ]),
            field(_qtyRows[i].item, 'Item'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: field(_qtyRows[i].number, 'Number',
                      keyboard: const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: 8),
              Expanded(
                  child: field(_qtyRows[i].quantity, 'Quantity',
                      keyboard: const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: 8),
              Expanded(child: field(_qtyRows[i].unit, 'Unit')),
            ]),
            const SizedBox(height: 8),
            field(_qtyRows[i].size, 'Size'),
            const SizedBox(height: 8),
            field(_qtyRows[i].material, 'Material'),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _qtyRows.add(_QtyDraft())),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('ADD ITEM'),
        ),
      ),
    ]);
  }
}

class _QtyDraft {
  final TextEditingController item;
  final TextEditingController number;
  final TextEditingController size;
  final TextEditingController material;
  final TextEditingController quantity;
  final TextEditingController unit;

  _QtyDraft()
      : item = TextEditingController(),
        number = TextEditingController(),
        size = TextEditingController(),
        material = TextEditingController(),
        quantity = TextEditingController(),
        unit = TextEditingController();

  _QtyDraft.fromReading(QuantityReading q)
      : item = TextEditingController(text: q.item),
        number = TextEditingController(text: q.number),
        size = TextEditingController(text: q.size),
        material = TextEditingController(text: q.material),
        quantity = TextEditingController(text: q.quantity),
        unit = TextEditingController(text: q.unit);

  QuantityReading toReading() => QuantityReading(
        item: item.text.trim(),
        number: number.text.trim(),
        size: size.text.trim(),
        material: material.text.trim(),
        quantity: quantity.text.trim(),
        unit: unit.text.trim(),
      );

  void dispose() {
    item.dispose();
    number.dispose();
    size.dispose();
    material.dispose();
    quantity.dispose();
    unit.dispose();
  }
}

extension _PhotoRows on _TaskDetailScreenState {
  Widget _photoAnalysisRow(int i, TaskAnalysis a) {
    final id = _analysedIds[i];
    final matches = _media.where((m) => m.id == id).toList();
    final info = a.forImage(i);
    final desc = (info['description'] ?? '').toString();
    final obs = info['observations'] is List
        ? (info['observations'] as List).map((e) => '$e').toList()
        : <String>[];
    final risk = (info['risk_level'] ?? '').toString().toUpperCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceElev,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 58,
            height: 58,
            child: matches.isEmpty
                ? const ColoredBox(color: Colors.black26)
                : Image.file(File(matches.first.path), fit: BoxFit.cover, cacheWidth: 200),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Photo ${i + 1}',
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(width: 8),
              if (risk.isNotEmpty && risk != 'LOW') Pill('$risk RISK', color: softRiskColor(risk)),
            ]),
            if (desc.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(desc,
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35)),
              ),
            for (final o in obs.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('• $o',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.3)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, color: AppTheme.textPrimary),
        ),
      );
}

class _EvidenceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback? onTap;
  const _EvidenceButton({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final light = AppTheme.isLight;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 112,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(light ? 0.08 : 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(light ? 0.35 : 0.6)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 2),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
          ]),
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final LocalMedia media;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  const _MediaTile({required this.media, required this.onOpen, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final m = media;
    return SizedBox(
      width: 190,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 126,
              width: 190,
              child: Stack(fit: StackFit.expand, children: [
                if (m.isVideo)
                  Container(
                    decoration: BoxDecoration(
                      gradient: AppTheme.heroGradient,
                    ),
                  )
                else
                  Image.file(File(m.path), fit: BoxFit.cover, cacheWidth: 500),
                if (m.isVideo)
                  Center(
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32),
                    ),
                  ),
                if (m.isVideo)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          '${two(m.durationSeconds ~/ 60)}:${two(m.durationSeconds % 60)}',
                          style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                if (m.synced)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppTheme.accentGreen.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_rounded, size: 12, color: Colors.black),
                        SizedBox(width: 3),
                        Text('SAVED',
                            style: TextStyle(
                                color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(m.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppTheme.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(fmtDateTime(m.capturedAt),
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
      ]),
    );
  }
}

class _VideoScreen extends StatefulWidget {
  final String path;
  final String title;
  const _VideoScreen({required this.path, required this.title});

  @override
  State<_VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<_VideoScreen> {
  late final VideoPlayerController _c = VideoPlayerController.file(File(widget.path));
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) {
        setState(() => _ready = true);
        _c.play();
      }
    });
    _c.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.title, style: const TextStyle(fontSize: 14))),
        body: Center(
          child: !_ready
              ? const CircularProgressIndicator()
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AspectRatio(aspectRatio: _c.value.aspectRatio, child: VideoPlayer(_c)),
                  const SizedBox(height: 12),
                  VideoProgressIndicator(_c, allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16)),
                  const SizedBox(height: 8),
                  IconButton(
                    iconSize: 48,
                    color: Colors.white,
                    icon: Icon(_c.value.isPlaying
                        ? Icons.pause_circle_rounded
                        : Icons.play_circle_rounded),
                    onPressed: () => _c.value.isPlaying ? _c.pause() : _c.play(),
                  ),
                ]),
        ),
      );
}
