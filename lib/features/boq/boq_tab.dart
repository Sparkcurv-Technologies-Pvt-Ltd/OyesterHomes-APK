import 'package:flutter/material.dart';
import 'boq_editor.dart';

/// The project's BOQ tab (web BOQTab.jsx → `BOQEditor kind="project"`): sections and lines with quantity,
/// rate, amount and actual cost, totals, add / edit / delete lines, apply a library template, save as a
/// template, Excel import / export, blank sheet and the letterhead PDF. Editing follows the server's
/// `can_edit` (Admin or this project's manager).
///
/// Embedded in the project detail TabBarView: no Scaffold, scrolls itself, pull-to-refresh.
class BoqTab extends StatelessWidget {
  final int projectId;
  const BoqTab({super.key, required this.projectId});

  @override
  Widget build(BuildContext context) => BoqEditor(isProject: true, id: projectId);
}
