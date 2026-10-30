import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/common.dart';
import '../auth/user.dart';

// Private helpers for the setup screens (clients, companies, users, company settings).

/// Module key → label, exactly as `MODULE_LABELS` in the web UsersPage.jsx.
const moduleLabels = <String, String>{
  'projects': 'Projects',
  'phases_tracking': 'Phases & Tracking',
  'field_ops': 'Field Ops',
  'clients': 'Clients',
  'leads': 'Leads',
  'leave_attendance': 'Leave & Attendance',
  'finance': 'Finance',
  'estimates': 'Estimates',
  'procurement': 'Procurement',
  'equipment': 'Assets',
  'inventory': 'Stock',
  'change_orders': 'Change Orders',
  'model3d_viewer': '3D Viewer',
  'client_portal': 'Client Portal',
  'vendor_portal': 'Vendor Portal',
  'site_engineer_portal': 'SE Portal',
};

String moduleLabel(String key) => moduleLabels[key] ?? key;

/// The web's `r.replace(/([A-Z])/g, " $1").trim()` ("ProjectManager" → "Project Manager").
String roleWords(String? role) => humanize(role);

/// JSON list → list of maps.
List<Map<String, dynamic>> asMaps(dynamic v) =>
    (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// `value || null` from the web forms.
String? orNull(String s) => s.isEmpty ? null : s;

/// The web RoleBadge: role label in a bordered pill, coloured per role.
class RoleBadge extends StatelessWidget {
  final String? role;
  const RoleBadge(this.role, {super.key});

  static Tone _tone(String? r) => switch (r) {
        'Admin' => Tone.accent,
        'ProjectManager' => Tone.orange,
        'SiteEngineer' => Tone.info,
        'Accountant' => Tone.success,
        'ProcurementOfficer' => Tone.orange,
        _ => Tone.neutral,
      };

  @override
  Widget build(BuildContext context) =>
      StatusChip(role, label: AppUser.roleLabels[role] ?? role ?? '—', tone: _tone(role), dense: true);
}

/// Inline error inside a bottom sheet (a toast would sit behind the sheet).
class SheetError extends StatelessWidget {
  final String? message;
  const SheetError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.isEmpty) return const SizedBox.shrink();
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.toneFill(Tone.danger),
          border: Border.all(color: p.toneBorder(Tone.danger)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 16, color: p.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(message!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: p.danger))),
        ]),
      ),
    );
  }
}

/// Muted helper paragraph.
class HelpText extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;
  const HelpText(this.text, {super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: padding, child: Text(text, style: Theme.of(context).textTheme.bodySmall));
}
