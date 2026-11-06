/// ─────────────────────────────────────────────────────────────────────────────
/// CMS Site Manager AI — API Configuration
///
/// HOW TO CHANGE THE SERVER ADDRESS
///   Production API  →  https://civil-works-site-monitoring-sd7d.vercel.app
/// ─────────────────────────────────────────────────────────────────────────────

class ApiConfig {
  ApiConfig._();

  // Change this ONE line to point at your server
  //
  // Override without editing code (no trailing slash):
  //   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8009        (Android emulator -> PC)
  //   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8009    (real phone, same Wi-Fi)
  static const String _base = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://civil-works-site-monitoring-sd7d.vercel.app',
  );

  /// Base URL, exposed so the superadmin data explorer can resolve paths.
  static String get base => _base;

  /// Turns '/api/foo/' into a full URL (full http(s) URLs are returned as-is).
  static String url(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_base${path.startsWith('/') ? '' : '/'}$path';
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String tokenUrl        = '$_base/api/token/';
  static const String tokenRefreshUrl = '$_base/api/token/refresh/';
  static const String meUrl           = '$_base/api/accounts/me/';

  // ── Worker / Attendance ───────────────────────────────────────────────────
  static const String workerLocationUrl = '$_base/api/worker/location/';
  static String workerAttendanceTodayUrl(int id) =>
      '$_base/api/worker/$id/attendance/today/';
  static String workerAttendanceUrl(int id) =>
      '$_base/api/worker/$id/attendance/';
  static String workerActivityUrl(int id) => '$_base/api/worker/$id/activity/';
  static String workerLocationsUrl(int id) =>
      '$_base/api/worker/$id/locations/';

  // ── Dashboard (team lead / project manager / superadmin) ──────────────────
  static const String workersUrl      = '$_base/api/dashboard/workers/';
  static const String activityFeedUrl = '$_base/api/dashboard/activity-feed/';
  static const String analyticsUrl    = '$_base/api/dashboard/analytics/';
  static const String livelinessUrl   = '$_base/api/dashboard/liveliness/';
  static const String attendanceExportUrl =
      '$_base/api/dashboard/ai-data/attendance/';
  static const String locationExportUrl =
      '$_base/api/dashboard/ai-data/location/';
  static const String zoneExportUrl = '$_base/api/dashboard/ai-data/zone/';

  // ── AI analyses ───────────────────────────────────────────────────────────
  static const String siteInspectionsUrl =
      '$_base/api/projects-data/site-inspections/';
  static const String detectJsonUrl      = '$_base/api/detect/json/';
  static const String detectJsonListUrl  = '$_base/api/detect/json/list/';

  // ── Site tasks (progress + history) ───────────────────────────────────────
  static const String siteTasksUrl = '$_base/api/projects-data/site-tasks/';
  static String siteTaskUpdatesUrl(int id) =>
      '$_base/api/projects-data/site-tasks/$id/updates/';
  static String siteTaskEvidencePresignUrl(int id) =>
      '$_base/api/projects-data/site-tasks/$id/evidence/presign/';
  static String siteTaskUrl(int id) => '$_base/api/projects-data/site-tasks/$id/';
  static const String siteTaskFeedUrl =
      '$_base/api/projects-data/site-task-updates/';

  // ── Live tracking + profile picture ───────────────────────────────────────
  static const String liveLocationsUrl = '$_base/api/dashboard/live-locations/';
  static const String workerPathUrl = '$_base/api/dashboard/worker-path/';
  static const String projectBoundaryUrl = '$_base/api/projects/boundary/';
  static String profilePictureUrl(int userId) =>
      '$_base/api/accounts/users/$userId/profile-picture/';

  // ── Directory ─────────────────────────────────────────────────────────────
  static const String usersUrl       = '$_base/api/accounts/users/';
  static const String assignmentsUrl = '$_base/api/accounts/assignments/';
  static const String projectsUrl    = '$_base/api/projects-data/projects/';

  // ── Common headers ────────────────────────────────────────────────────────
  static const Map<String, String> jsonHeaders = {
    'Content-Type': 'application/json',
  };

  static Map<String, String> authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
}

/// AI analysis configuration.
///
/// There is NO AI key in this app. Analysis goes through the backend
/// (POST /api/accounts/ai/generate/), which holds the key.
class AiConfig {
  AiConfig._();

  /// AI runs on the backend (the Gemini key lives only on the server and never in this app).
  /// Same login token as the rest of the app; the client timeout must be 90 seconds.
  static String get endpoint => '${ApiConfig.base}/api/accounts/ai/generate/';

  /// The backend allows about 4 MB per request.
  static const int maxBodyBytes = 4 * 1000 * 1000;

  static const Duration timeout = Duration(seconds: 90);
}

/// Map tiles. The default OpenStreetMap server is fine for testing; for production
/// use a commercial tile provider (MapTiler, Stadia, Mapbox …) and set the URL here.
class MapConfig {
  MapConfig._();
  static const String tileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );
  static const String userAgentPackage = 'com.cms.sitemanager';
}
