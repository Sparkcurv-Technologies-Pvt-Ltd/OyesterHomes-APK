import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';

// Small pieces shared by the projects screens and the dashboard (private to these two folders).

/// Project statuses, in the web's order (ProjectListPage / ProjectFormModal STATUSES).
const projectStatuses = ['Planning', 'Ongoing', 'OnHold', 'Completed', 'Cancelled'];

/// `₹1,25,000` or "—" when there is no budget (web `fmtBudget`).
String fmtBudget(dynamic b) => b == null ? '—' : inr(b);

/// Web ProgressBar colours: ≥100 emerald, ≥60 amber, else sky.
Tone? progressTone(num pct) => pct >= 100 ? Tone.success : (pct >= 60 ? null : Tone.info);

/// Thin bar plus "NN%" (web ProjectTable ProgressBar).
class ProgressLine extends StatelessWidget {
  final num pct;
  final Tone? tone;
  final bool useProjectTone;
  const ProgressLine(this.pct, {super.key, this.tone, this.useProjectTone = true});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(children: [
      Expanded(child: LevelBar(pct / 100, tone: tone ?? (useProjectTone ? progressTone(pct) : null))),
      const SizedBox(width: 8),
      SizedBox(
        width: 40,
        child: Text('${pct.round()}%', textAlign: TextAlign.right, style: tabular(tt.bodySmall)),
      ),
    ]);
  }
}

/// Web DashboardStatCard: a KPI tile that doubles as a filter toggle. When [active] it gets a coloured
/// outline and the "Filter active" hint.
class FilterStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;
  final Tone? tone;
  const FilterStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.active = false,
    this.onTap,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final c = tone == null ? p.fg : p.tone(tone!);
    return Surface(
      onTap: onTap,
      borderColor: active ? c : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if (tone != null && tone != Tone.info) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Expanded(child: Eyebrow(label)),
          Icon(icon, size: 15, color: tone == null ? p.fgSubtle : c),
        ]),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              maxLines: 1,
              style: tabular(tt.headlineSmall).copyWith(fontWeight: FontWeight.w700, color: active ? c : p.fg)),
        ),
        if (active) ...[
          const SizedBox(height: 4),
          Text('FILTER ACTIVE — TAP TO CLEAR',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontSize: 9, letterSpacing: 1.2, color: p.fgMuted, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }
}

/// Small bordered tag (web `.chip` / phase name tag / document category).
class TagChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  const TagChip(this.text, {super.key, this.icon, this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final child = Container(
      padding: EdgeInsets.fromLTRB(8, 4, onRemove != null ? 2 : 8, 4),
      decoration: BoxDecoration(border: Border.all(color: p.border), borderRadius: BorderRadius.circular(6), color: p.card),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: p.fgMuted), const SizedBox(width: 4)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'Inter', fontSize: 12, color: p.fgMuted, fontWeight: FontWeight.w500)),
        ),
        if (onRemove != null)
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close, size: 13, color: p.fgSubtle)),
          ),
      ]),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: child);
  }
}

/// Reads a list from a JSON body that is either a list or `{items: [...]}`.
List<Map<String, dynamic>> asMapList(dynamic v, [String key = 'items']) {
  final list = v is List ? v : (v is Map ? v[key] as List? : null) ?? const [];
  return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
