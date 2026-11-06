DateTime? parseDate(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

int toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}

double? toDouble(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '');

String two(int n) => n.toString().padLeft(2, '0');
String fmtTime(DateTime? d) => d == null ? '—' : '${two(d.hour)}:${two(d.minute)}';
String fmtDate(DateTime? d) =>
    d == null ? '—' : '${d.year}-${two(d.month)}-${two(d.day)}';
String fmtDateTime(DateTime? d) =>
    d == null ? '—' : '${fmtDate(d)} ${fmtTime(d)}';

String fmtDuration(Duration d) {
  final m = d.inMinutes < 0 ? 0 : d.inMinutes;
  return '${m ~/ 60}h ${two(m % 60)}m';
}

/// One row from /api/worker/{id}/attendance/ or /api/dashboard/ai-data/attendance/
class AttendanceRecord {
  final int id;
  final int workerId;
  final String workerUsername;
  final String projectName;
  final DateTime? date;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double? durationSeconds;
  final String status; // ACTIVE | COMPLETED | INCOMPLETE
  final String zone;

  const AttendanceRecord({
    required this.id,
    required this.workerId,
    required this.workerUsername,
    required this.projectName,
    required this.date,
    required this.checkIn,
    required this.checkOut,
    required this.durationSeconds,
    required this.status,
    required this.zone,
  });

  Duration? get duration {
    if (durationSeconds != null) {
      return Duration(seconds: durationSeconds!.round());
    }
    if (checkIn != null && checkOut != null) {
      return checkOut!.difference(checkIn!);
    }
    return null;
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
        id: toInt(j['id'] ?? j['attendance_id']),
        workerId: toInt(j['worker'] ?? j['worker_id']),
        workerUsername: (j['worker_username'] ?? '').toString(),
        projectName: (j['project_name'] ?? '').toString(),
        date: DateTime.tryParse((j['date'] ?? '').toString()),
        checkIn: parseDate(j['check_in']),
        checkOut: parseDate(j['check_out']),
        durationSeconds: toDouble(j['total_duration_seconds']),
        status: (j['status'] ?? '').toString().toUpperCase(),
        zone: (j['zone'] ?? '').toString(),
      );
}

/// One entry of `worker_statuses` from /api/dashboard/workers/
class WorkerStatus {
  final int workerId;
  final String username;
  final String fullName;
  final String status; // PRESENT | CHECKED_OUT | INCOMPLETE | ABSENT
  final String zone;
  final bool? insideProject;
  final DateTime? lastSeen;
  final double? lat;
  final double? lon;

  /// Distance (m) to the engineer's OWN assigned site; 0 = inside. null = not measured.
  final double? siteDistance;
  final String siteName;

  const WorkerStatus({
    required this.workerId,
    required this.username,
    required this.fullName,
    required this.status,
    required this.zone,
    required this.insideProject,
    required this.lastSeen,
    required this.lat,
    required this.lon,
    this.siteDistance,
    this.siteName = '',
  });

  WorkerStatus copyWith({
    String? status,
    bool? insideProject,
    double? siteDistance,
    String? siteName,
  }) =>
      WorkerStatus(
        workerId: workerId,
        username: username,
        fullName: fullName,
        status: status ?? this.status,
        zone: zone,
        insideProject: insideProject ?? this.insideProject,
        lastSeen: lastSeen,
        lat: lat,
        lon: lon,
        siteDistance: siteDistance ?? this.siteDistance,
        siteName: siteName ?? this.siteName,
      );

  factory WorkerStatus.fromJson(Map<String, dynamic> j) {
    final loc = j['last_location'] is Map
        ? Map<String, dynamic>.from(j['last_location'] as Map)
        : <String, dynamic>{};
    // Tolerate both {latitude, longitude} and {lat, lng/lon} spellings.
    final latV = loc['latitude'] ?? loc['lat'];
    final lonV = loc['longitude'] ?? loc['lng'] ?? loc['lon'];
    return WorkerStatus(
      workerId: toInt(j['worker_id'] ?? j['id']),
      username: (j['username'] ?? '').toString(),
      fullName: (j['full_name'] ?? j['username'] ?? '').toString(),
      status: (j['status'] ?? 'ABSENT').toString().toUpperCase(),
      zone: (loc['zone'] ?? j['zone'] ?? '').toString(),
      insideProject: loc['inside_project'] is bool ? loc['inside_project'] as bool : null,
      lastSeen: parseDate(loc['timestamp']),
      lat: toDouble(latV),
      lon: toDouble(lonV),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'PRESENT':
        return 'On site';
      case 'CHECKED_OUT':
        return 'Checked out';
      case 'INCOMPLETE':
        return 'Off site';
      default:
        return 'Absent';
    }
  }
}
