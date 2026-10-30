import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../shell/routes.dart';
import 'project_common.dart';
import 'project_detail_screen.dart';

/// One project (web ProjectTable row / mobile card): name with the issues flag, location, status,
/// client, budget and completion. Opens the project when tapped unless [onTap] is given.
/// No outer margin: the caller places it.
class ProjectTile extends StatelessWidget {
  final Map<String, dynamic> project;
  final VoidCallback? onTap;
  const ProjectTile({super.key, required this.project, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final tt = Theme.of(context).textTheme;
    final pr = project;
    final pct = toNum(pr['percent_complete']);
    return Surface(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: onTap ?? () => push(context, ProjectDetailScreen(projectId: toInt(pr['id']))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(dash(pr['name']), maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall),
                ),
                if (pr['has_active_issues'] == true) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Active issues',
                    child: Icon(Icons.warning_amber_rounded, size: 16, color: p.danger),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Row(children: [
                Icon(Icons.location_on_outlined, size: 13, color: p.fgSubtle),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(dash(pr['location']), maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          StatusChip(pr['status'] as String?, dense: true),
        ]),
        const SizedBox(height: 10),
        Divider(height: 1, color: p.border),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: InfoTile(label: 'Client', value: pr['client_name']?.toString())),
          const SizedBox(width: 12),
          Expanded(
            child: InfoTile(
              label: 'Budget',
              valueWidget: Text(fmtBudget(pr['budget']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tabular(tt.bodyMedium).copyWith(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
        if (pr['site_engineer_name'] != null) ...[
          const SizedBox(height: 8),
          Text('Engineer: ${pr['site_engineer_name']}', style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
        const SizedBox(height: 10),
        ProgressLine(pct),
      ]),
    );
  }
}
