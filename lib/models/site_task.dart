import 'attendance.dart';

List<String> _strList(dynamic v) => v is List
    ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
    : <String>[];

String _s(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s == 'null' ? '' : s;
}

/// One of the project's site tasks (e.g. Excavation).
class SiteTask {
  final int id;
  final int projectId;
  final String projectName;
  final int order;
  final String name;
  final String description;
  final double progress; // 0-100
  final String status; // pending | in_progress | done
  final DateTime? updatedAt;
  final String updatedBy;
  final int updatesCount;

  const SiteTask({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.order,
    required this.name,
    required this.description,
    required this.progress,
    required this.status,
    required this.updatedAt,
    required this.updatedBy,
    required this.updatesCount,
  });

  bool get isDone => status == 'done';
  bool get isInProgress => status == 'in_progress';
  bool get isPending => status == 'pending';

  String get statusLabel =>
      isDone ? 'DONE' : (isInProgress ? 'IN PROGRESS' : 'PENDING');

  factory SiteTask.fromJson(Map<String, dynamic> j) => SiteTask(
        id: toInt(j['id']),
        projectId: toInt(j['project_id']),
        projectName: _s(j['project_name']),
        order: toInt(j['order']),
        name: _s(j['name']),
        description: _s(j['description']),
        progress: (toDouble(j['progress_percent']) ?? 0).clamp(0.0, 100.0).toDouble(),
        status: _s(j['status']).isEmpty ? 'pending' : _s(j['status']),
        updatedAt: parseDate(j['last_updated_at']),
        updatedBy: _s(j['last_updated_by']),
        updatesCount: toInt(j['updates_count']),
      );
}

class TaskSummary {
  final int total;
  final int done;
  final int inProgress;
  final int pending;
  final double overall;
  const TaskSummary({
    required this.total,
    required this.done,
    required this.inProgress,
    required this.pending,
    required this.overall,
  });

  static const empty =
      TaskSummary(total: 0, done: 0, inProgress: 0, pending: 0, overall: 0);

  factory TaskSummary.fromJson(Map<String, dynamic> j) => TaskSummary(
        total: toInt(j['total']),
        done: toInt(j['done']),
        inProgress: toInt(j['in_progress']),
        pending: toInt(j['pending']),
        overall: toDouble(j['overall_percent']) ?? 0,
      );
}

/// One measured item from the photos: count, size, material and quantity,
/// kept as separate values so a site engineer can edit each one.
class QuantityReading {
  final String item;
  final String number;
  final String size;
  final String material;
  final String quantity;
  final String unit;

  const QuantityReading({
    this.item = '',
    this.number = '',
    this.size = '',
    this.material = '',
    this.quantity = '',
    this.unit = '',
  });

  bool get isEmpty =>
      item.isEmpty && number.isEmpty && size.isEmpty && material.isEmpty && quantity.isEmpty;

  String get quantityLabel =>
      quantity.isEmpty ? '' : (unit.isEmpty ? quantity : '$quantity $unit');

  bool sameAs(QuantityReading o) =>
      item == o.item &&
      number == o.number &&
      size == o.size &&
      material == o.material &&
      quantity == o.quantity &&
      unit == o.unit;

  static bool sameList(List<QuantityReading> a, List<QuantityReading> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!a[i].sameAs(b[i])) return false;
    }
    return true;
  }

  factory QuantityReading.fromJson(Map<String, dynamic> j) => QuantityReading(
        item: _s(j['item']),
        number: _s(j['number']),
        size: _s(j['size']),
        material: _s(j['material']),
        quantity: _s(j['quantity']),
        unit: _s(j['unit']),
      );

  static List<QuantityReading> listFrom(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => QuantityReading.fromJson(Map<String, dynamic>.from(e)))
        .where((q) => !q.isEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'item': item,
        'number': number,
        'size': size,
        'material': material,
        'quantity': quantity,
        'unit': unit,
      };
}

int severityRank(String s) {
  switch (s.trim().toUpperCase()) {
    case 'CRITICAL':
      return 4;
    case 'HIGH':
      return 3;
    case 'MEDIUM':
      return 2;
    case 'LOW':
      return 1;
    default:
      return 0;
  }
}

String _normSeverity(String s) {
  final u = s.trim().toUpperCase();
  return const ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'].contains(u) ? u : (u.isEmpty ? 'LOW' : 'MEDIUM');
}

/// One hazard / unsafe condition found in the photos.
class Hazard {
  final String hazard;
  final String category;
  final String severity; // LOW | MEDIUM | HIGH | CRITICAL
  final String location;
  final String action;

  const Hazard({
    required this.hazard,
    this.category = '',
    this.severity = 'MEDIUM',
    this.location = '',
    this.action = '',
  });

  int get rank => severityRank(severity);

  factory Hazard.fromJson(Map<String, dynamic> j) => Hazard(
        hazard: _s(j['hazard']),
        category: _s(j['category']),
        severity: _normSeverity(_s(j['severity'])),
        location: _s(j['location']),
        action: _s(j['action']),
      );

  Map<String, dynamic> toJson() => {
        'hazard': hazard,
        'category': category,
        'severity': severity,
        'location': location,
        'action': action,
      };

  /// Parsed, empty entries removed, most severe first.
  static List<Hazard> listFrom(dynamic v) {
    if (v is! List) return <Hazard>[];
    final out = v
        .whereType<Map>()
        .map((e) => Hazard.fromJson(Map<String, dynamic>.from(e)))
        .where((h) => h.hazard.isNotEmpty)
        .toList();
    out.sort((a, b) => b.rank.compareTo(a.rank));
    return out;
  }
}

/// What the AI says about the photos of a task.
class TaskAnalysis {
  final double progressPercent;
  final String summary;
  final List<String> observations;
  final List<String> safetyFindings;
  final String safetySeverity;
  final int peopleTotal;
  final int peopleWithPpe;
  final List<String> equipment;
  final String riskLevel; // LOW | MEDIUM | HIGH
  final int confidence;
  final String imageQuality;
  final List<String> recommendations;
  final List<QuantityReading> quantities;

  // Detailed report + hazards
  final List<String> workCompleted;
  final List<String> workInProgress;
  final List<String> workRemaining;
  final List<String> qualityObservations;
  final List<Hazard> hazards;
  final String ppeStatus;
  final String housekeeping;
  final String environment;
  final List<String> immediateActions;

  /// One entry per analysed photo (same order as the photos sent to the AI).
  final List<Map<String, dynamic>> perImage;

  const TaskAnalysis({
    required this.progressPercent,
    required this.summary,
    required this.observations,
    required this.safetyFindings,
    required this.safetySeverity,
    required this.peopleTotal,
    required this.peopleWithPpe,
    required this.equipment,
    required this.riskLevel,
    required this.confidence,
    required this.imageQuality,
    required this.recommendations,
    this.quantities = const [],
    this.workCompleted = const [],
    this.workInProgress = const [],
    this.workRemaining = const [],
    this.qualityObservations = const [],
    this.hazards = const [],
    this.ppeStatus = '',
    this.housekeeping = '',
    this.environment = '',
    this.immediateActions = const [],
    this.perImage = const [],
  });

  /// True when the AI returned the detailed report (older saved analyses did not).
  bool get hasReport =>
      hazards.isNotEmpty ||
      workCompleted.isNotEmpty ||
      workInProgress.isNotEmpty ||
      workRemaining.isNotEmpty ||
      qualityObservations.isNotEmpty ||
      ppeStatus.isNotEmpty ||
      housekeeping.isNotEmpty ||
      environment.isNotEmpty ||
      immediateActions.isNotEmpty;

  /// Analysis of the i-th analysed photo (0-based), or {} when the AI gave none.
  Map<String, dynamic> forImage(int i) {
    for (final m in perImage) {
      if (toInt(m['index']) == i + 1) return m;
    }
    return i < perImage.length ? perImage[i] : <String, dynamic>{};
  }

  factory TaskAnalysis.fromAi(Map<String, dynamic> j) {
    final hazards = Hazard.listFrom(j['hazards']);
    final topHazard = hazards.isEmpty ? 0 : hazards.first.rank;

    // Overall risk: the higher of what the AI said and what the hazards imply.
    var risk = _s(j['risk_level']).toUpperCase();
    if (!const ['LOW', 'MEDIUM', 'HIGH'].contains(risk)) risk = 'LOW';
    final riskRank = const {'LOW': 1, 'MEDIUM': 2, 'HIGH': 3}[risk]!;
    final hazardRisk = topHazard >= 3 ? 3 : (topHazard == 2 ? 2 : 1);
    if (hazardRisk > riskRank) risk = hazardRisk == 3 ? 'HIGH' : 'MEDIUM';

    var severity = _s(j['safety_severity']).isEmpty ? 'NONE' : _s(j['safety_severity']).toUpperCase();
    if (topHazard > severityRank(severity)) severity = hazards.first.severity;

    var safety = _strList(j['safety_findings']);
    if (safety.isEmpty && hazards.isNotEmpty) safety = hazards.map((h) => h.hazard).toList();

    return TaskAnalysis(
      workCompleted: _strList(j['work_completed']),
      workInProgress: _strList(j['work_in_progress']),
      workRemaining: _strList(j['work_remaining']),
      qualityObservations: _strList(j['quality_observations']),
      hazards: hazards,
      ppeStatus: _s(j['ppe_status']),
      housekeeping: _s(j['housekeeping']),
      environment: _s(j['environment']),
      immediateActions: _strList(j['immediate_actions']),
      progressPercent:
          (toDouble(j['progress_percent']) ?? 0).clamp(0.0, 100.0).toDouble(),
      summary: _s(j['summary']),
      observations: _strList(j['observations']),
      safetyFindings: safety,
      safetySeverity: severity,
      peopleTotal: toInt(j['people_total']),
      peopleWithPpe: toInt(j['people_with_ppe']),
      equipment: _strList(j['equipment']),
      riskLevel: risk,
      confidence: toInt(j['confidence']).clamp(0, 100).toInt(),
      imageQuality: _s(j['image_quality']).isEmpty ? '—' : _s(j['image_quality']),
      recommendations: _strList(j['recommendations']),
      quantities: QuantityReading.listFrom(j['quantities']),
      perImage: j['images'] is List
          ? (j['images'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[],
    );
  }

  Map<String, dynamic> toJson() => {
        'progress_percent': progressPercent,
        'summary': summary,
        'observations': observations,
        'safety_findings': safetyFindings,
        'safety_severity': safetySeverity,
        'people_total': peopleTotal,
        'people_with_ppe': peopleWithPpe,
        'equipment': equipment,
        'risk_level': riskLevel,
        'confidence': confidence,
        'image_quality': imageQuality,
        'recommendations': recommendations,
        'quantities': quantities.map((q) => q.toJson()).toList(),
        'work_completed': workCompleted,
        'work_in_progress': workInProgress,
        'work_remaining': workRemaining,
        'quality_observations': qualityObservations,
        'hazards': hazards.map((h) => h.toJson()).toList(),
        'ppe_status': ppeStatus,
        'housekeeping': housekeeping,
        'environment': environment,
        'immediate_actions': immediateActions,
      };
}

List<EvidenceItem> _evidenceList(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => EvidenceItem.fromJson(Map<String, dynamic>.from(e))).toList()
    : <EvidenceItem>[];

/// A photo stored in AWS S3 for an update, with its own AI analysis.
class EvidenceItem {
  final int id;
  final String mediaType; // image | video
  final String name;
  final String? url; // short-lived signed link
  final int sizeBytes;
  final Map<String, dynamic> analysis;

  const EvidenceItem({
    required this.id,
    required this.mediaType,
    required this.name,
    required this.url,
    required this.sizeBytes,
    required this.analysis,
  });

  bool get isVideo => mediaType == 'video';

  factory EvidenceItem.fromJson(Map<String, dynamic> j) => EvidenceItem(
        id: toInt(j['id']),
        mediaType: _s(j['media_type']).isEmpty ? 'image' : _s(j['media_type']),
        name: _s(j['name']),
        url: _s(j['url']).isEmpty ? null : _s(j['url']),
        sizeBytes: toInt(j['size_bytes']),
        analysis: j['analysis'] is Map
            ? Map<String, dynamic>.from(j['analysis'] as Map)
            : <String, dynamic>{},
      );
}

/// One saved progress update (a row of the task's history).
class TaskUpdate {
  final int id;
  final int taskId;
  final String taskName;
  final int taskOrder;
  final String projectName;
  final String userName;
  final double before;
  final double after;
  final double? aiPercent;
  final bool edited;
  final String summary;
  final String aiSummary;
  final List<String> findings;
  final String remarks;
  final Map<String, dynamic> analysis;
  final List<Map<String, dynamic>> media;
  final int photoCount;
  final List<String> photos; // base64 thumbnails (only in detail responses)
  final List<String> photoPaths; // photos kept on this phone (offline saves)
  final List<EvidenceItem> evidence; // photos stored in AWS S3
  final int evidenceCount;
  final double? lat;
  final double? lon;
  final DateTime? createdAt;

  const TaskUpdate({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.taskOrder,
    required this.projectName,
    required this.userName,
    required this.before,
    required this.after,
    required this.aiPercent,
    required this.edited,
    required this.summary,
    required this.aiSummary,
    required this.findings,
    required this.remarks,
    required this.analysis,
    required this.media,
    required this.photoCount,
    required this.photos,
    this.photoPaths = const [],
    this.evidence = const [],
    this.evidenceCount = 0,
    required this.lat,
    required this.lon,
    required this.createdAt,
  });

  double get delta => after - before;
  String get riskLevel {
    final r = _s(analysis['risk_level']).toUpperCase();
    return r.isEmpty ? 'LOW' : r;
  }

  int get videoCount => media.where((m) => _s(m['type']) == 'video').length;

  /// Hazards found by the assistant (empty for updates saved before this feature).
  List<Hazard> get hazards => Hazard.listFrom(analysis['hazards']);
  int get hazardCount => hazards.length;
  String get worstHazardSeverity => hazards.isEmpty ? '' : hazards.first.severity;

  factory TaskUpdate.fromJson(Map<String, dynamic> j) => TaskUpdate(
        id: toInt(j['id']),
        taskId: toInt(j['task_id']),
        taskName: _s(j['task_name']),
        taskOrder: toInt(j['task_order']),
        projectName: _s(j['project_name']),
        userName: _s(j['user_name']).isEmpty ? _s(j['username']) : _s(j['user_name']),
        before: toDouble(j['progress_before']) ?? 0,
        after: toDouble(j['progress_after']) ?? 0,
        aiPercent: toDouble(j['ai_progress_percent']),
        edited: j['edited_by_user'] == true,
        summary: _s(j['summary']),
        aiSummary: _s(j['ai_summary']),
        findings: _strList(j['findings']),
        remarks: _s(j['remarks']),
        analysis: j['analysis'] is Map
            ? Map<String, dynamic>.from(j['analysis'] as Map)
            : <String, dynamic>{},
        media: j['media'] is List
            ? (j['media'] as List)
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[],
        photoCount: toInt(j['photo_count']),
        photos: _strList(j['photos']),
        photoPaths: _strList(j['photo_paths']),
        // The photo list is called `evidence` in the spec, `evidence_files` in some backends.
        evidence: _evidenceList(j['evidence'] ?? j['evidence_files']),
        evidenceCount: toInt(j['evidence_count'] ?? j['evidence_files_count']),
        lat: toDouble(j['lat']),
        lon: toDouble(j['lon']),
        createdAt: parseDate(j['created_at']),
      );
}
