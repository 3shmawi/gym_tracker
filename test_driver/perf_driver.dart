// Host side of integration_test/perf/scroll_perf.dart (`flutter drive`).
// Writes build/perf/<mode>.json (the frame-timing summary per flow, without
// the per-frame lists) and build/perf/<mode>.md (a table for
// docs/performance.md). Holds no secrets: only frame times.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

/// The columns of the table, from FrameTimingSummarizer.summary.
const _columns = {
  'average_frame_build_time_millis': 'build avg',
  '90th_percentile_frame_build_time_millis': 'build p90',
  '99th_percentile_frame_build_time_millis': 'build p99',
  'average_frame_rasterizer_time_millis': 'raster avg',
  '90th_percentile_frame_rasterizer_time_millis': 'raster p90',
  '99th_percentile_frame_rasterizer_time_millis': 'raster p99',
  'missed_frame_build_budget_count': 'missed build',
  'missed_frame_rasterizer_budget_count': 'missed raster',
  'frame_count': 'frames',
};

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    final meta = (data['meta'] as Map?)?.cast<String, Object?>() ?? {};
    final mode = '${meta['mode'] ?? 'unknown'}';
    // PERF_NAME (scripts/perf.sh --name) names the files, e.g. the base
    // branch's run next to this branch's in CI.
    final name = Platform.environment['PERF_NAME'] ?? mode;
    final flows = <String, Map<String, Object?>>{
      for (final MapEntry(:key, :value) in data.entries)
        if (key != 'meta' && value is Map)
          key: {for (final c in _columns.keys) c: value[c]},
    };
    final dir = Directory('build/perf')..createSync(recursive: true);
    File('${dir.path}/$name.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({'meta': meta, ...flows}),
    );
    final table = StringBuffer()
      ..writeln(
        '$name: ${meta['platform']} · ${meta['build']} · $mode '
        '(times in ms)',
      )
      ..writeln()
      ..writeln('| flow | ${_columns.values.join(' | ')} |')
      ..writeln('|---|${List.filled(_columns.length, '---:').join('|')}|');
    for (final MapEntry(:key, :value) in flows.entries) {
      final cells = [
        for (final c in _columns.keys)
          switch (value[c]) {
            final double d => d.toStringAsFixed(1),
            final Object? o => '$o',
          },
      ];
      table.writeln('| $key | ${cells.join(' | ')} |');
    }
    File('${dir.path}/$name.md').writeAsStringSync(table.toString());
    stdout.write(table);
  },
);
