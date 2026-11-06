import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../models/attendance.dart';
import '../../services/auth_service.dart';
import '../../services/site_status_service.dart';
import '../../services/tracking_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import '../../widgets/user_avatar.dart';

/// The route one engineer travelled on a day (points are saved every 10 minutes).
/// Refreshes by itself while viewing today.
class WorkerPathScreen extends StatefulWidget {
  final int workerId;
  final String name;
  const WorkerPathScreen({super.key, required this.workerId, required this.name});

  @override
  State<WorkerPathScreen> createState() => _WorkerPathScreenState();
}

class _WorkerPathScreenState extends State<WorkerPathScreen> {
  final _map = MapController();
  bool _mapReady = false;
  bool _needsFit = true;
  Timer? _timer;

  DateTime _day = DateTime.now();
  bool _loading = true;
  String? _error;
  WorkerPath? _path;
  List<SiteReading?> _readings = []; // each point vs the engineer's OWN assigned site
  int? _selectedIndex;

  /// True when point [i] is off the engineer's own site (more than 5 m away).
  bool _off(int i) {
    if (i < _readings.length && _readings[i]?.onSite != null) return _readings[i]!.onSite == false;
    final pts = _path?.points ?? const <PathPoint>[];
    return i < pts.length && pts[i].inside == false;
  }

  bool get _isToday {
    final n = DateTime.now();
    return _day.year == n.year && _day.month == n.month && _day.day == n.day;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_isToday) _load(silent: true);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      final p = await TrackingService.path(auth, widget.workerId, _day, name: widget.name);
      var readings = <SiteReading?>[];
      try {
        final ctx = await SiteStatusService.contextFor(auth, widget.workerId);
        readings = [
          for (final pt in p.points) ctx.reading(pt.lat, pt.lon, backendInside: pt.inside),
        ];
      } catch (_) {/* keep the server's own flag */}
      if (!mounted) return;
      _readings = readings;
      final grew = _path == null || p.points.length != _path!.points.length;
      setState(() {
        _path = p;
        _error = null;
        _loading = false;
      });
      if (_needsFit || (grew && !silent)) _fit();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('TrackingException: ', '');
        _loading = false;
      });
    }
  }

  void _fit() {
    final p = _path;
    if (!_mapReady || p == null || p.points.isEmpty) return;
    final pts = p.points.map((e) => LatLng(e.lat, e.lon)).toList();
    if (pts.length == 1) {
      _map.move(pts.first, 16.5);
    } else {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(48),
        maxZoom: 17,
      ));
    }
    _needsFit = false;
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (d != null) {
      setState(() {
        _day = d;
        _needsFit = true;
        _selectedIndex = null;
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _path;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(widget.name.toUpperCase(), style: const TextStyle(fontSize: 15)),
        actions: [
          IconButton(
              tooltip: 'Pick a day',
              icon: const Icon(Icons.calendar_month_rounded),
              onPressed: _pickDay),
          IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load),
        ],
      ),
      body: _loading && p == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && p == null
              ? ErrorState(message: _error!, onRetry: _load)
              : _content(p!),
    );
  }

  Widget _content(WorkerPath p) {
    final pts = p.points;
    final line = pts.map((e) => LatLng(e.lat, e.lon)).toList();
    final offCount = [for (var i = 0; i < pts.length; i++) if (_off(i)) i].length;

    return Column(children: [
      // Summary
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(children: [
          Row(children: [
            UserAvatar(userId: widget.workerId, name: widget.name, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_isToday ? 'Today · ${fmtDate(_day)}' : fmtDate(_day),
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
                Text(
                  p.lastAt == null
                      ? 'No location recorded on this day'
                      : 'Last point ${fmtTime(p.lastAt)} · ${fmtAgo(DateTime.now().difference(p.lastAt!).inMinutes)}',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ]),
            ),
            if (_isToday && p.points.isNotEmpty)
              Pill('AUTO-REFRESH', color: AppTheme.accent, icon: Icons.sync_rounded),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _Kpi('DISTANCE', fmtDistance(p.distanceMeters), AppTheme.accent)),
            const SizedBox(width: 8),
            Expanded(child: _Kpi('POINTS', '${pts.length}', AppTheme.aiColor)),
            const SizedBox(width: 8),
            Expanded(child: _Kpi('SPAN', fmtDuration(Duration(minutes: p.durationMinutes)), AppTheme.accentGreen)),
            const SizedBox(width: 8),
            Expanded(
                child: _Kpi('OFF SITE', '$offCount',
                    offCount > 0 ? AppTheme.amber : AppTheme.textSecondary)),
          ]),
          if (p.truncated)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Showing the first part of a very long day.',
                  style: TextStyle(color: AppTheme.amber, fontSize: 12)),
            ),
        ]),
      ),

      // Map
      Expanded(
        flex: 6,
        child: Stack(children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: line.isNotEmpty ? line.last : const LatLng(20.5937, 78.9629),
                initialZoom: line.isNotEmpty ? 15 : 4.5,
                onMapReady: () {
                  _mapReady = true;
                  _fit();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: MapConfig.tileUrl,
                  userAgentPackageName: MapConfig.userAgentPackage,
                ),
                if (line.length > 1)
                  PolylineLayer(polylines: [
                    Polyline(
                      points: line,
                      strokeWidth: 5,
                      color: AppTheme.accent,
                      borderStrokeWidth: 1.5,
                      borderColor: Colors.white,
                    ),
                  ]),
                MarkerLayer(markers: [
                  // every saved point
                  for (var i = 0; i < pts.length; i++)
                    if (i != 0 && i != pts.length - 1)
                      Marker(
                        point: line[i],
                        width: 22,
                        height: 22,
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedIndex = i),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _off(i) ? AppTheme.amber : AppTheme.primaryLight,
                              border: Border.all(
                                  color: Colors.white, width: _selectedIndex == i ? 3 : 1.5),
                            ),
                          ),
                        ),
                      ),
                  // start (check-in)
                  if (pts.isNotEmpty)
                    Marker(
                      point: line.first,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.flag_circle_rounded,
                          color: AppTheme.accentGreen, size: 38),
                    ),
                  // latest position
                  if (pts.length > 1)
                    Marker(
                      point: line.last,
                      width: 56,
                      height: 56,
                      child: UserAvatar(
                          userId: widget.workerId,
                          name: widget.name,
                          size: 44,
                          ringColor: AppTheme.accent),
                    ),
                ]),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: FloatingActionButton.small(
              heroTag: 'fitPath',
              backgroundColor: AppTheme.surfaceCard,
              onPressed: () {
                _needsFit = true;
                _fit();
              },
              child: Icon(Icons.center_focus_strong_rounded, color: AppTheme.accent),
            ),
          ),
          if (pts.isEmpty)
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No route for this day.\nPositions are saved every 10 minutes after check-in.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textPrimary)),
              ),
            ),
        ]),
      ),

      // Timeline
      Expanded(
        flex: 4,
        child: pts.isEmpty
            ? const SizedBox.shrink()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                itemCount: pts.length,
                itemBuilder: (_, k) {
                  final i = pts.length - 1 - k; // newest first
                  final pt = pts[i];
                  final isFirst = i == 0;
                  final isLast = i == pts.length - 1;
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedIndex = i);
                      if (_mapReady) _map.move(LatLng(pt.lat, pt.lon), 17);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _selectedIndex == i ? AppTheme.surfaceElev : AppTheme.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: _selectedIndex == i ? AppTheme.accent : AppTheme.border),
                      ),
                      child: Row(children: [
                        Icon(
                          isFirst
                              ? Icons.flag_rounded
                              : (isLast ? Icons.my_location_rounded : Icons.circle),
                          size: isFirst || isLast ? 20 : 10,
                          color: isFirst
                              ? AppTheme.accentGreen
                              : (_off(i) ? AppTheme.amber : AppTheme.accent),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 50,
                          child: Text(fmtTime(pt.timestamp),
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontWeight: FontWeight.w800)),
                        ),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                              isFirst
                                  ? 'Start · check-in'
                                  : (pt.zone.isEmpty ? 'On route' : pt.zone),
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                            ),
                            if (pt.gapMinutes > 25)
                              Text('No signal for ${pt.gapMinutes} min before this point',
                                  style: TextStyle(color: AppTheme.amber, fontSize: 11.5)),
                          ]),
                        ),
                        if (_off(i))
                          Pill(
                              i < _readings.length && _readings[i]?.distanceMeters != null
                                  ? '${fmtMeters(_readings[i]!.distanceMeters!)} OFF'
                                  : 'OFF SITE',
                              color: AppTheme.amber),
                        if (!isFirst)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text('+${fmtDistance(pt.segmentMeters)}',
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                          ),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.18), AppTheme.surfaceCard],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    color: color, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800)),
        ]),
      );
}
