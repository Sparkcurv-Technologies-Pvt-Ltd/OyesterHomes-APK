import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

// The web's RosenCharts (HBarChart, VBarChart, DonutChart, HalfGauge) and the dashboard Gantt.
// Bars, donut and gauge are fl_chart; the horizontal bars and the Gantt are plain widgets, as on the web.

class ChartDatum {
  final String key;
  final String label;
  final double value;
  final Color color;
  const ChartDatum(this.key, this.value, this.color, {String? label}) : label = label ?? key;
}

String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// A "nice" axis step for [range] split into about [count] ticks.
double _niceStep(double range, int count, {bool integer = false}) {
  if (range <= 0) return 1;
  final raw = range / count;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final norm = raw / mag;
  final step = (norm <= 1 ? 1 : norm <= 2 ? 2 : norm <= 5 ? 5 : 10) * mag;
  return integer ? math.max(1, step.roundToDouble()) : step;
}

/// Horizontal bars with the value at the end (web HBarChart).
class HBarChart extends StatelessWidget {
  final List<ChartDatum> data;
  final String Function(double) format;
  const HBarChart({super.key, required this.data, this.format = _plain});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final top = data.fold<double>(0, (m, d) => math.max(m, d.value));
    final scale = top <= 0 ? 1.0 : top;
    return Column(children: [
      for (final d in data)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 84,
              child: Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: tt.bodySmall),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final w = c.maxWidth - 44;
                final barW = d.value <= 0 ? 0.0 : math.max(3.0, w * d.value / scale);
                return Row(children: [
                  Container(
                    width: barW,
                    height: 22,
                    decoration: BoxDecoration(
                      color: d.color,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(format(d.value),
                      style: tabular(tt.bodySmall).copyWith(fontWeight: FontWeight.w600, color: p.fg)),
                ]);
              }),
            ),
          ]),
        ),
    ]);
  }
}

/// Vertical bars; [signed] draws +/- around zero (web VBarChart). Tap a bar for its full label.
class VBarChart extends StatelessWidget {
  final List<ChartDatum> data;
  final double height;
  final bool integer;
  final bool signed;
  final int minBars;
  final String Function(double) format;
  const VBarChart({
    super.key,
    required this.data,
    this.height = 220,
    this.integer = false,
    this.signed = false,
    this.minBars = 5,
    this.format = _plain,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final lo0 = signed ? math.min(0.0, data.fold<double>(0, (m, d) => math.min(m, d.value))) : 0.0;
    final hi0 = math.max(0.0, data.fold<double>(0, (m, d) => math.max(m, d.value)));
    final hiSafe = hi0 == lo0 ? lo0 + 1 : hi0;
    final step = _niceStep(hiSafe - lo0, 5, integer: integer);
    final lo = (lo0 / step).floor() * step;
    final hi = (hiSafe / step).ceil() * step;
    final slots = math.max(data.length, minBars);

    return SizedBox(
      height: height,
      child: LayoutBuilder(builder: (context, c) {
        final barW = ((c.maxWidth - 44) / slots * 0.6).clamp(6.0, 40.0);
        return BarChart(BarChartData(
          minY: lo,
          maxY: hi,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: step,
            getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 0.7, dashArray: const [6, 5]),
          ),
          extraLinesData: signed
              ? ExtraLinesData(horizontalLines: [HorizontalLine(y: 0, color: p.inputBorder, strokeWidth: 1)])
              : null,
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: step,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(format(v), textAlign: TextAlign.right, style: tabular(tt.bodySmall).copyWith(fontSize: 10)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SizedBox(
                      width: (c.maxWidth - 44) / slots,
                      child: Text(data[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: tt.bodySmall?.copyWith(fontSize: 10.5)),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => p.fg,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, gi, rod, ri) {
                if (group.x >= data.length) return null;
                final d = data[group.x];
                return BarTooltipItem('${d.label}\n${format(d.value)}',
                    TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: p.bg));
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < slots; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: i < data.length ? data[i].value : 0,
                  width: barW,
                  color: i < data.length ? data[i].color : Colors.transparent,
                  borderRadius: i < data.length && data[i].value < 0
                      ? const BorderRadius.vertical(bottom: Radius.circular(5))
                      : const BorderRadius.vertical(top: Radius.circular(5)),
                ),
              ]),
          ],
        ));
      }),
    );
  }
}

/// Donut with a centre slot (web DonutChart).
class DonutChart extends StatelessWidget {
  final List<ChartDatum> data;
  final double size;
  final Widget? center;
  const DonutChart({super.key, required this.data, this.size = 110, this.center});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final total = data.fold<double>(0, (s, d) => s + d.value);
    final shown = data.where((d) => d.value > 0).toList();
    final outer = size / 2;
    final inner = outer / 1.625;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(
          startDegreeOffset: -90,
          sectionsSpace: shown.length > 1 ? 2 : 0,
          centerSpaceRadius: inner,
          pieTouchData: PieTouchData(enabled: false),
          sections: total == 0
              ? [PieChartSectionData(value: 1, color: p.muted, radius: outer - inner, showTitle: false)]
              : [
                  for (final d in shown)
                    PieChartSectionData(value: d.value, color: d.color, radius: outer - inner, showTitle: false),
                ],
        )),
        if (center != null) center!,
      ]),
    );
  }
}

/// Half donut filled to [value] % with [child] under the arc (web HalfGauge).
class HalfGauge extends StatelessWidget {
  final num? value;
  final Color color;
  final Widget? child;
  const HalfGauge({super.key, required this.value, this.color = const Color(0xFFD1A658), this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pct = (value ?? 0).toDouble().clamp(0.0, 100.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          final outer = w / 2;
          final inner = outer / 1.625;
          return SizedBox(
            width: w,
            height: w / 2,
            child: Stack(children: [
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: w,
                  maxHeight: w,
                  child: SizedBox(
                    width: w,
                    height: w,
                    child: PieChart(PieChartData(
                      startDegreeOffset: 180,
                      sectionsSpace: 0,
                      centerSpaceRadius: inner,
                      pieTouchData: PieTouchData(enabled: false),
                      sections: [
                        if (pct > 0) PieChartSectionData(value: pct, color: color, radius: outer - inner, showTitle: false),
                        if (pct < 100)
                          PieChartSectionData(value: 100 - pct, color: p.muted, radius: outer - inner, showTitle: false),
                        PieChartSectionData(value: 100, color: Colors.transparent, radius: outer - inner, showTitle: false),
                      ],
                    )),
                  ),
                ),
              ),
              if (child != null) Positioned(left: 0, right: 0, bottom: 0, child: child!),
            ]),
          );
        }),
      ),
    );
  }
}

/// Project timeline (web GanttChart): planned span faded, progress up to today solid, a dashed "Today" line.
class GanttChart extends StatelessWidget {
  final List<Map<String, dynamic>> timeline;
  final Map<String, Color> colors;
  const GanttChart({super.key, required this.timeline, required this.colors});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final rows = timeline.where((t) => toDate(t['planned_start']) != null && toDate(t['planned_end']) != null).toList();
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text('No scheduled projects.', style: tt.bodySmall)),
      );
    }
    final starts = rows.map((r) => toDate(r['planned_start'])!.millisecondsSinceEpoch);
    final ends = rows.map((r) => toDate(r['planned_end'])!.millisecondsSinceEpoch);
    final min = starts.reduce(math.min);
    final max = ends.reduce(math.max);
    final span = (max - min) == 0 ? 1 : max - min;
    double pos(dynamic d) => (toDate(d)!.millisecondsSinceEpoch - min) / span * 100;
    final todayPct = ((DateTime.now().millisecondsSinceEpoch - min) / span * 100).clamp(0.0, 100.0);
    const labelW = 104.0;

    return LayoutBuilder(builder: (context, c) {
      final trackW = c.maxWidth - labelW - 8;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Stack(children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    SizedBox(
                      width: labelW,
                      child: Text(r['name']?.toString() ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    _ganttTrack(context, r, pos, todayPct, trackW),
                  ]),
                ),
            ]),
          ),
          Positioned(
            left: labelW + 8 + trackW * todayPct / 100,
            top: 0,
            bottom: 8,
            child: CustomPaint(size: const Size(1, double.infinity), painter: _DashedLine(p.info)),
          ),
          Positioned(
            left: labelW + 8 + trackW * todayPct / 100 + 3,
            top: 0,
            child: Text('TODAY',
                style: TextStyle(fontFamily: 'Inter', fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: p.accentText)),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(left: labelW + 8, top: 2),
          child: Row(children: [
            Text(fmtMonth(DateTime.fromMillisecondsSinceEpoch(min)), style: tt.bodySmall?.copyWith(fontSize: 10)),
            const Spacer(),
            Text(fmtMonth(DateTime.fromMillisecondsSinceEpoch(max)), style: tt.bodySmall?.copyWith(fontSize: 10)),
          ]),
        ),
      ]);
    });
  }

  Widget _ganttTrack(BuildContext context, Map<String, dynamic> r, double Function(dynamic) pos, double todayPct, double trackW) {
    final p = context.pal;
    final color = colors[r['status']] ?? const Color(0xFFF97316);
    final left = pos(r['planned_start']);
    final width = math.max(2.0, pos(r['planned_end']) - left);
    final pct = toNum(r['percent_complete']);
    final done = math.max(0.0, math.min(width * pct / 100, todayPct - left));
    return SizedBox(
      width: trackW,
      height: 20,
      child: Stack(children: [
        Positioned.fill(child: Container(color: p.muted)),
        Positioned(
          left: trackW * left / 100,
          width: trackW * width / 100,
          top: 0,
          bottom: 0,
          child: Container(color: color.withValues(alpha: 0.4)),
        ),
        Positioned(
          left: trackW * left / 100,
          width: trackW * done / 100,
          top: 0,
          bottom: 0,
          child: Container(color: color),
        ),
        Positioned(
          left: math.min(trackW * left / 100 + 4, trackW - 30),
          top: 3,
          child: Text('${pct.round()}%',
              style: tabular(TextStyle(fontFamily: 'Inter', fontSize: 10, fontWeight: FontWeight.w700, color: p.fg))),
        ),
      ]),
    );
  }
}

class _DashedLine extends CustomPainter {
  final Color color;
  _DashedLine(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, math.min(y + 4, size.height)), paint);
      y += 7;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLine old) => old.color != color;
}
