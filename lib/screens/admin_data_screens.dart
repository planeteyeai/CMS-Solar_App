import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/api_config.dart';
import '../services/admin_data_service.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

String _prettyKey(String k) => k.replaceAll('_', ' ').toUpperCase();

bool _looksLikeDate(String key, dynamic v) {
  if (v is! String || v.length < 10) return false;
  final k = key.toLowerCase();
  final keyHint = k.endsWith('_at') ||
      k.contains('time') ||
      k.contains('date') ||
      k.contains('seen') ||
      k == 'timestamp';
  return keyHint && DateTime.tryParse(v) != null;
}

String _fmtDate(String raw) {
  final d = DateTime.tryParse(raw)?.toLocal();
  if (d == null) return raw;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String _scalar(String key, dynamic v) {
  if (v == null) return '—';
  if (v is bool) return v ? 'Yes' : 'No';
  if (_looksLikeDate(key, v)) return _fmtDate(v as String);
  final s = v.toString();
  return s.isEmpty ? '—' : s;
}

bool _isScalar(dynamic v) => v == null || v is String || v is num || v is bool;

const _titleKeys = [
  'name', 'title', 'asset_id', 'username', 'worker_name', 'worker_username',
  'project_name', 'full_name', 'summary', 'description', 'message', 'id',
];

String _titleOf(Map<String, dynamic> m) {
  for (final k in _titleKeys) {
    final v = m[k];
    if (v != null && _isScalar(v) && v.toString().trim().isNotEmpty) {
      final s = v.toString().trim();
      return s.length > 80 ? '${s.substring(0, 80)}…' : s;
    }
  }
  return 'Record';
}

/// Picks up to [max] short scalar fields to preview on a list card.
List<MapEntry<String, dynamic>> _previewFields(Map<String, dynamic> m,
    {int max = 4}) {
  final skip = <String>{};
  for (final k in _titleKeys) {
    final v = m[k];
    if (v != null && _isScalar(v) && v.toString().trim().isNotEmpty) {
      skip.add(k);
      break;
    }
  }
  const priority = [
    'status', 'is_checked_in', 'risk_level', 'risk', 'role', 'highest_role',
    'zone', 'current_zone', 'project_name', 'project', 'confidence',
    'anomaly_count', 'check_in_time', 'check_out_time', 'last_seen',
    'created_at', 'timestamp', 'assigned_at', 'email',
  ];
  final out = <MapEntry<String, dynamic>>[];
  for (final k in priority) {
    if (out.length >= max) break;
    if (m.containsKey(k) && !skip.contains(k) && _isScalar(m[k])) {
      out.add(MapEntry(k, m[k]));
    }
  }
  for (final e in m.entries) {
    if (out.length >= max) break;
    if (skip.contains(e.key) || out.any((o) => o.key == e.key)) continue;
    if (_isScalar(e.value) && e.key != 'id') out.add(e);
  }
  return out;
}

String _prettyJson(Object? v) =>
    const JsonEncoder.withIndent('  ').convert(v);

// ─────────────────────────────────────────────────────────────────────────────
// List screen
// ─────────────────────────────────────────────────────────────────────────────

class AdminDataListScreen extends StatefulWidget {
  final AdminDataset dataset;

  /// When set, the screen reads this exact URL instead of resolving the
  /// dataset's candidate endpoints (used by the "custom endpoint" tool).
  final String? customUrl;

  const AdminDataListScreen({super.key, required this.dataset, this.customUrl});

  @override
  State<AdminDataListScreen> createState() => _AdminDataListScreenState();
}

class _AdminDataListScreenState extends State<AdminDataListScreen> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  String? _next;
  int? _count;
  bool _loading = true;
  bool _loadingMore = false;
  AdminDataException? _error;
  String _localFilter = '';
  String _serverSearch = '';
  DateTime? _date;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = widget.customUrl != null
          ? await AdminDataService.fetchUrl(auth, widget.customUrl!)
          : await AdminDataService.fetchDataset(auth, widget.dataset,
              search: _serverSearch, date: _date);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _next = page.next;
        _count = page.count;
        _loading = false;
      });
    } on AdminDataException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_next == null || _loadingMore || _loading) return;
    final auth = context.read<AuthService>();
    setState(() => _loadingMore = true);
    try {
      final page = await AdminDataService.fetchUrl(auth, _next!);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _next = page.next;
        _count = page.count ?? _count;
      });
    } on AdminDataException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() => _date = d);
      _load();
    }
  }

  Future<void> _editEndpoint() async {
    final current = await AdminDataService.getOverride(widget.dataset.key);
    if (!mounted) return;
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Endpoint path'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'If your backend serves this data from a different route, enter it here (e.g. /api/attendance/records/). Leave empty to use automatic detection.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autocorrect: false,
            decoration: const InputDecoration(hintText: '/api/…/'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('SAVE')),
        ],
      ),
    );
    if (result == null) return;
    await AdminDataService.setOverride(widget.dataset.key, result);
    if (mounted) _load();
  }

  List<Map<String, dynamic>> get _visible {
    if (_localFilter.isEmpty) return _items;
    final q = _localFilter.toLowerCase();
    return _items
        .where((m) => jsonEncode(m).toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final ds = widget.dataset;
    final visible = _visible;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(ds.title.toUpperCase()),
        actions: [
          if (ds.supportsDate && widget.customUrl == null)
            IconButton(
              tooltip: 'Filter by date',
              icon: Icon(Icons.calendar_month_rounded,
                  color: _date != null ? AppTheme.accent : null),
              onPressed: _pickDate,
            ),
          if (widget.customUrl == null)
            IconButton(
              tooltip: 'Endpoint path',
              icon: const Icon(Icons.settings_ethernet_rounded),
              onPressed: _editEndpoint,
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onChanged: (v) => setState(() => _localFilter = v.trim()),
            onSubmitted: (v) {
              _serverSearch = v.trim();
              _load();
            },
            decoration: InputDecoration(
              hintText: 'Filter loaded records · press search to query server',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        final hadServer = _serverSearch.isNotEmpty;
                        setState(() {
                          _localFilter = '';
                          _serverSearch = '';
                        });
                        if (hadServer) _load();
                      },
                    ),
            ),
          ),
        ),
        if (_date != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text('Date: ${_fmtDate(_date!.toIso8601String()).substring(0, 10)}'),
                onDeleted: () {
                  setState(() => _date = null);
                  _load();
                },
              ),
            ),
          ),
        if (!_loading && _error == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _count != null
                    ? '${visible.length} shown · ${_items.length} loaded of $_count total'
                    : '${visible.length} record${visible.length == 1 ? '' : 's'}',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          ),
        Expanded(child: _body(visible)),
      ]),
    );
  }

  Widget _body(List<Map<String, dynamic>> visible) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          SizedBox(height: 120),
          Icon(Icons.inbox_rounded, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 12),
          Center(
              child: Text('No records found',
                  style: TextStyle(color: AppTheme.textSecondary))),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: visible.length + (_next != null || _loadingMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= visible.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          return _RecordCard(
            record: visible[i],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AdminRecordDetailScreen(
                    title: widget.dataset.title, record: visible[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onTap;
  const _RecordCard({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final preview = _previewFields(record);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(_titleOf(record),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textMuted),
            ]),
            if (preview.isNotEmpty) const SizedBox(height: 8),
            ...preview.map((e) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 112,
                      child: Text(_prettyKey(e.key),
                          style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 10.5,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700)),
                    ),
                    Expanded(
                      child: Text(_scalar(e.key, e.value),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13)),
                    ),
                  ]),
                )),
          ]),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final AdminDataException error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            error.notFound
                ? Icons.link_off_rounded
                : Icons.error_outline_rounded,
            size: 48,
            color: error.notFound ? AppTheme.amber : AppTheme.accentRed,
          ),
          const SizedBox(height: 14),
          Text(error.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          if (error.notFound && error.tried.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Tried these URLs. If your backend uses a different route, use the endpoint button (top right) to set it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 8),
            ...error.tried.map((u) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: SelectableText(u,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                )),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('RETRY')),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail screen – shows EVERY field of a record, including nested data
// ─────────────────────────────────────────────────────────────────────────────

class AdminRecordDetailScreen extends StatelessWidget {
  final String title;
  final Map<String, dynamic> record;
  const AdminRecordDetailScreen(
      {super.key, required this.title, required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(title.toUpperCase()),
        actions: [
          IconButton(
            tooltip: 'Copy as JSON',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _prettyJson(record)));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Record copied as JSON')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(_titleOf(record),
              style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          _FieldsBlock(data: record, depth: 0),
        ],
      ),
    );
  }
}

class _FieldsBlock extends StatelessWidget {
  final Map<String, dynamic> data;
  final int depth;
  const _FieldsBlock({required this.data, required this.depth});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final e in data.entries) {
      children.add(_fieldRow(context, e.key, e.value));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: depth == 0 ? AppTheme.surfaceCard : AppTheme.surfaceElev,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _fieldRow(BuildContext context, String key, dynamic value) {
    if (_isScalar(value)) {
      final text = _scalar(key, value);
      return InkWell(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Copied $key')));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 120,
              child: Text(_prettyKey(key),
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: AppTheme.textPrimary, fontSize: 14, height: 1.35)),
            ),
          ]),
        ),
      );
    }

    // Nested object or list
    Widget nested;
    if (value is Map) {
      nested = value.isEmpty
          ? Text('—', style: TextStyle(color: AppTheme.textSecondary))
          : _FieldsBlock(
              data: Map<String, dynamic>.from(value), depth: depth + 1);
    } else if (value is List) {
      if (value.isEmpty) {
        nested =
            Text('—', style: TextStyle(color: AppTheme.textSecondary));
      } else if (value.every(_isScalar)) {
        nested = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: value
              .map((v) => Chip(
                    label: Text(_scalar(key, v),
                        style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                  ))
              .toList(),
        );
      } else {
        nested = Column(
          children: [
            for (var i = 0; i < value.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: value[i] is Map
                    ? _FieldsBlock(
                        data: Map<String, dynamic>.from(value[i] as Map),
                        depth: depth + 1)
                    : Text(value[i].toString(),
                        style: TextStyle(color: AppTheme.textPrimary)),
              ),
          ],
        );
      }
    } else {
      nested = Text(value.toString());
    }

    final count = value is List ? ' (${value.length})' : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_prettyKey(key)}$count',
            style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        nested,
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom endpoint explorer – read any GET endpoint the superadmin can access
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showCustomEndpointDialog(BuildContext context) async {
  final ctrl = TextEditingController(text: '/api/');
  final path = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Open any endpoint'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Read-only. Enter an API path and every record it returns will be listed.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '/api/…/'),
        ),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL')),
        FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('OPEN')),
      ],
    ),
  );
  if (path == null || path.isEmpty || !context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AdminDataListScreen(
        dataset: AdminDataset(
          key: 'custom',
          title: path,
          subtitle: '',
          icon: Icons.code_rounded,
          paths: [path],
        ),
        customUrl: ApiConfig.url(path),
      ),
    ),
  );
}
