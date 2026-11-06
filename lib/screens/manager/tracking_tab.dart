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
import 'worker_path_screen.dart';

Color trackingColor(String state) {
  switch (state) {
    case 'live':
      return AppTheme.accentGreen;
    case 'stale':
      return AppTheme.amber;
    default:
      return AppTheme.textMuted;
  }
}

String trackingLabel(String state) =>
    state == 'live' ? 'LIVE' : (state == 'stale' ? 'NO RECENT PING' : 'OFFLINE');

/// Superadmin: live map of every engineer, tap one to see the route travelled.
class TrackingTab extends StatefulWidget {
  final ValueNotifier<String> project;
  const TrackingTab({super.key, required this.project});

  @override
  State<TrackingTab> createState() => _TrackingTabState();
}

class _TrackingTabState extends State<TrackingTab> {
  final _map = MapController();
  bool _mapReady = false;
  bool _fitted = false;
  Timer? _timer;

  bool _loading = true;
  String? _error;
  List<LivePosition> _items = [];
  Map<int, SiteReading> _site = {}; // vs each engineer's OWN assigned site
  DateTime? _updated;
  int? _selected;

  @override
  void initState() {
    super.initState();
    widget.project.addListener(_onProject);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
    });
  }

  @override
  void dispose() {
    widget.project.removeListener(_onProject);
    _timer?.cancel();
    super.dispose();
  }

  void _onProject() {
    _fitted = false;
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    try {
      final auth = context.read<AuthService>();
      final items = await TrackingService.live(auth, project: widget.project.value);
      final site = <int, SiteReading>{};
      try {
        final ctx = await SiteStatusService.contextsFor(
          auth,
          items.map((e) => e.workerId),
          fallbackProject: {
            for (final e in items)
              if (e.projectName.isNotEmpty) e.workerId: e.projectName
          },
        );
        for (final p in items) {
          site[p.workerId] = (ctx[p.workerId] ?? SiteContext.empty)
              .reading(p.lat, p.lon, backendInside: p.insideProject);
        }
      } catch (_) {/* keep the server's own flag */}
      if (!mounted) return;
      setState(() {
        _site = site;
        _items = items;
        _error = null;
        _loading = false;
        _updated = DateTime.now();
      });
      if (!_fitted) _fit();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('TrackingException: ', '');
        _loading = false;
      });
    }
  }

  void _fit() {
    if (!_mapReady || _items.isEmpty) return;
    final pts = _items.map((e) => LatLng(e.lat, e.lon)).toList();
    if (pts.length == 1) {
      _map.move(pts.first, 16);
    } else {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(56),
        maxZoom: 17,
      ));
    }
    _fitted = true;
  }

  void _openPath(LivePosition p) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => WorkerPathScreen(workerId: p.workerId, name: p.fullName)),
      );

  @override
  Widget build(BuildContext context) {
    final live = _items.where((e) => e.state == 'live').length;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Pill('$live LIVE', color: AppTheme.accentGreen, icon: Icons.circle),
          const SizedBox(width: 8),
          Pill('${_items.length - live} OTHER', color: AppTheme.textSecondary),
          const Spacer(),
          if (_updated != null)
            Text('Updated ${fmtTime(_updated)}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5)),
          IconButton(
            tooltip: 'Fit all',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.center_focus_strong_rounded, color: AppTheme.accent),
            onPressed: () {
              _fitted = false;
              _fit();
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.refresh_rounded, color: AppTheme.accent),
            onPressed: _load,
          ),
        ]),
      ),
      Expanded(
        flex: 6,
        child: Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(20.5937, 78.9629),
                initialZoom: 4.5,
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
                MarkerLayer(markers: [
                  for (final p in _items)
                    Marker(
                      point: LatLng(p.lat, p.lon),
                      width: 64,
                      height: 70,
                      child: GestureDetector(
                        onTap: () => setState(() => _selected = p.workerId),
                        child: _MapPin(position: p, selected: _selected == p.workerId),
                      ),
                    ),
                ]),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
          ),
          if (_loading && _items.isEmpty) const Center(child: CircularProgressIndicator()),
        ]),
      ),
      Expanded(flex: 5, child: _list()),
    ]);
  }

  Widget _list() {
    if (_error != null && _items.isEmpty) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    if (!_loading && _items.isEmpty) {
      return const EmptyState(
        icon: Icons.location_searching_rounded,
        title: 'No one is being tracked right now',
        message: 'Engineers appear here after they check in. Their position is saved every 10 minutes.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final p = _items[i];
        final c = trackingColor(p.state);
        return AppCard(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          borderColor: _selected == p.workerId ? AppTheme.accent : null,
          onTap: () {
            setState(() => _selected = p.workerId);
            if (_mapReady) _map.move(LatLng(p.lat, p.lon), 17);
          },
          child: Row(children: [
            UserAvatar(userId: p.workerId, name: p.fullName, size: 42, ringColor: c),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.fullName,
                    style: TextStyle(
                        color: AppTheme.textPrimary, fontWeight: FontWeight.w800, fontSize: 16.5)),
                const SizedBox(height: 3),
                Text(
                  [
                    if (p.zone.isNotEmpty) p.zone,
                    fmtAgo(p.minutesAgo),
                  ].join(' · '),
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                if (_site[p.workerId] != null && _site[p.workerId]!.label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _site[p.workerId]!.label,
                      style: TextStyle(
                          color: _site[p.workerId]!.onSite == false
                              ? AppTheme.amber
                              : AppTheme.accentGreen,
                          fontSize: 14,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
              ]),
            ),
            Pill(trackingLabel(p.state), color: c),
            IconButton(
              tooltip: 'View route',
              icon: Icon(Icons.route_rounded, color: AppTheme.accent),
              onPressed: () => _openPath(p),
            ),
          ]),
        );
      },
    );
  }
}

class _MapPin extends StatelessWidget {
  final LivePosition position;
  final bool selected;
  const _MapPin({required this.position, required this.selected});

  @override
  Widget build(BuildContext context) {
    final c = trackingColor(position.state);
    final first = position.fullName.split(' ').first;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: c.withOpacity(selected ? 0.9 : 0.5), blurRadius: selected ? 14 : 8, spreadRadius: selected ? 3 : 1),
          ],
        ),
        child: UserAvatar(
            userId: position.workerId, name: position.fullName, size: selected ? 44 : 38, ringColor: c),
      ),
      const SizedBox(height: 2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(8)),
        child: Text(first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}
