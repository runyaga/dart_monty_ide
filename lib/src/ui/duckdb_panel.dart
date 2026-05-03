import 'dart:async';

import 'package:dart_duckdb/dart_duckdb.dart' as duck;
import 'package:dart_monty_ide/src/controller/monty_ide_controller.dart';
import 'package:flutter/material.dart';
import 'package:hhg_duckdb/hhg_duckdb.dart';

/// A panel for browsing DuckDB tables and running ad-hoc SQL queries.
///
/// Reads the live [DuckDbExtension] from the [controller]'s extension list,
/// so it automatically picks up the current connection after interpreter reset.
class DuckDbPanel extends StatefulWidget {
  /// Creates a [DuckDbPanel].
  const DuckDbPanel({
    required this.controller,
    required this.onClose,
    super.key,
  });

  /// IDE controller — used to locate the live [DuckDbExtension].
  final MontyIdeController controller;

  /// Called when the user clicks the close button.
  final VoidCallback onClose;

  @override
  State<DuckDbPanel> createState() => _DuckDbPanelState();
}

class _DuckDbPanelState extends State<DuckDbPanel> {
  final TextEditingController _sqlController = TextEditingController();
  final FocusNode _sqlFocus = FocusNode();

  List<String> _tables = [];
  String? _selectedTable;
  List<String> _columns = [];
  List<List<Object?>> _rows = [];
  List<String> _resultColumns = [];
  String? _error;
  bool _loading = false;
  bool _queryRunning = false;

  duck.Connection? get _conn {
    final exts = widget.controller.extensions ?? [];
    for (final e in exts) {
      if (e is DuckDbExtension) return e.connection;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(_refreshTables());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _sqlController.dispose();
    _sqlFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // Re-fetch tables when the interpreter resets (new extension instance).
    if (widget.controller.isInitialized) {
      unawaited(_refreshTables());
    }
  }

  Future<void> _refreshTables() async {
    final conn = _conn;
    if (conn == null) {
      setState(() {
        _tables = [];
        _error = 'No DuckDB connection.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rs = await conn.query('SHOW TABLES');
      final names = rs.fetchAll().map((r) => r.first?.toString() ?? '').toList();
      setState(() {
        _tables = names;
        if (_selectedTable != null && !names.contains(_selectedTable)) {
          _selectedTable = null;
          _columns = [];
        }
      });
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectTable(String name) async {
    final conn = _conn;
    if (conn == null) return;
    setState(() {
      _selectedTable = name;
      _columns = [];
      _rows = [];
      _resultColumns = [];
      _error = null;
    });
    try {
      final rs = await conn.query('DESCRIBE "$name"');
      final allRows = rs.fetchAll();
      setState(() {
        _columns = allRows.map((r) => '${r[0]} ${r[1]}').toList();
      });
      // Also show first 50 rows as a preview.
      _sqlController.text = 'SELECT * FROM "$name" LIMIT 50';
      await _runQuery();
    } on Exception catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _runQuery() async {
    final conn = _conn;
    final sql = _sqlController.text.trim();
    if (conn == null || sql.isEmpty) return;
    setState(() {
      _queryRunning = true;
      _error = null;
      _rows = [];
      _resultColumns = [];
    });
    try {
      final rs = await conn.query(sql);
      setState(() {
        _resultColumns = rs.columnNames;
        _rows = rs.fetchAll(batchSize: 500);
        if (_rows.length > 500) _rows = _rows.sublist(0, 500);
      });
    } on Exception catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _queryRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: theme.secondaryHeaderColor,
          height: 40,
          child: Row(
            children: [
              const Text(
                'DUCKDB',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              const Spacer(),
              if (_loading || _queryRunning)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              const SizedBox(width: 6),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _refreshTables,
                icon: const Icon(Icons.refresh, size: 14),
                tooltip: 'Refresh tables',
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        // ── Table list ──────────────────────────────────────────────────
        if (_tables.isNotEmpty)
          Container(
            color: theme.cardColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: _tables.map((t) {
                final selected = t == _selectedTable;
                return ActionChip(
                  label: Text(
                    t,
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: selected
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(_selectTable(t)),
                );
              }).toList(),
            ),
          ),
        // ── Column schema ───────────────────────────────────────────────
        if (_columns.isNotEmpty)
          Container(
            color: theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Wrap(
              spacing: 6,
              children: _columns.map((c) {
                return Text(
                  c,
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                );
              }).toList(),
            ),
          ),
        const Divider(height: 1),
        // ── SQL editor ──────────────────────────────────────────────────
        Container(
          color: theme.cardColor,
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _sqlController,
                  focusNode: _sqlFocus,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'SELECT ...',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                  ),
                  onSubmitted: (_) => unawaited(_runQuery()),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: _queryRunning ? null : () => unawaited(_runQuery()),
                style: TextButton.styleFrom(
                  minimumSize: const Size(36, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: const Text('▶ Run'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // ── Error ────────────────────────────────────────────────────────
        if (_error != null)
          Container(
            color: Colors.red.shade900.withAlpha(60),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 10,
                color: Colors.red.shade200,
                fontFamily: 'monospace',
              ),
            ),
          ),
        // ── Results ──────────────────────────────────────────────────────
        if (_resultColumns.isNotEmpty)
          Expanded(
            child: _ResultTable(
              columns: _resultColumns,
              rows: _rows,
            ),
          )
        else if (!_loading && !_queryRunning && _error == null)
          Expanded(
            child: Center(
              child: Text(
                _conn == null
                    ? 'Run a script to initialize DuckDB'
                    : 'No tables yet — run a script first',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Results table ─────────────────────────────────────────────────────────────

class _ResultTable extends StatelessWidget {
  const _ResultTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<List<Object?>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const cellStyle = TextStyle(fontSize: 10, fontFamily: 'monospace');
    const headerStyle = TextStyle(
      fontSize: 10,
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
    );
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 28,
            dataRowMinHeight: 22,
            dataRowMaxHeight: 22,
            horizontalMargin: 8,
            columnSpacing: 12,
            headingRowColor: WidgetStatePropertyAll(
              theme.colorScheme.surfaceContainerHighest,
            ),
            columns: columns
                .map(
                  (c) => DataColumn(
                    label: Text(c, style: headerStyle),
                  ),
                )
                .toList(),
            rows: rows.map((row) {
              return DataRow(
                cells: row.map((cell) {
                  final text = cell == null ? 'NULL' : '$cell';
                  final short = text.length > 60 ? '${text.substring(0, 57)}…' : text;
                  return DataCell(
                    Tooltip(
                      message: text,
                      child: Text(short, style: cellStyle),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
