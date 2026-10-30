import 'package:flutter/material.dart';
import '../../core/utils/files.dart';
import '../../core/widgets/common.dart';
import '../boq/boq_template_screen.dart';
import '../finance/project_finance_screen.dart';
import '../procurement/bid_comparison_screen.dart';
import '../procurement/commitment_detail_screen.dart';
import '../procurement/procurement_screen.dart';
import '../projects/project_detail_screen.dart';
import '../quotations/purchase_order_screen.dart';
import '../quotations/quotation_detail_screen.dart';
import '../setup/client_detail_screen.dart';
import '../setup/client_projects_screen.dart';
import 'nav_config.dart';

/// Pushes a screen on the root navigator (covers the bottom bar). Returns its pop result.
Future<T?> push<T>(BuildContext context, Widget screen) =>
    Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute(builder: (_) => screen));

/// Opens a web path the backend hands out (notification links, `link` fields) as the matching screen.
/// Mirrors the web routes in App.js. Unknown paths do nothing; http(s) links open outside the app.
Future<void> openWebPath(BuildContext context, String link) async {
  if (link.startsWith('http')) {
    await openExternal(context, link);
    return;
  }
  final uri = Uri.parse(link);
  final tab = uri.queryParameters['tab'];
  final s = uri.pathSegments;
  int? n(int i) => s.length > i ? int.tryParse(s[i]) : null;

  Widget? screen;
  if (s.length >= 3 && s[0] == 'admin' && s[1] == 'projects' && n(2) != null) {
    final pid = n(2)!;
    if (s.length == 3) {
      screen = ProjectDetailScreen(projectId: pid, initialTab: tab);
    } else if (s[3] == 'finance') {
      screen = ProjectFinanceScreen(projectId: pid);
    } else if (s[3] == 'procurement') {
      if (s.length == 4) {
        screen = ProcurementScreen(projectId: pid);
      } else if (s.length >= 6 && s[4] == 'quotations' && n(5) != null) {
        screen = s.length >= 7 && s[6] == 'purchase-order'
            ? PurchaseOrderScreen(projectId: pid, quotationId: n(5)!)
            : QuotationDetailScreen(projectId: pid, quotationId: n(5)!);
      } else if (s.length >= 6 && n(5) != null) {
        screen = CommitmentDetailScreen(projectId: pid, type: s[4], commitmentId: n(5)!);
      }
    }
  } else if (s.length >= 3 && s[0] == 'admin' && s[1] == 'clients' && n(2) != null) {
    screen = s.length >= 4 && s[3] == 'projects' ? ClientProjectsScreen(clientId: n(2)!) : ClientDetailScreen(clientId: n(2)!);
  } else if (s.length >= 4 && s[1] == 'setup' && s[2] == 'boq-library' && n(3) != null) {
    screen = BoqTemplateScreen(templateId: n(3)!);
  } else if (s.length >= 5 && s[1] == 'procurement' && s[2] == 'bid-packages' && n(3) != null) {
    screen = BidComparisonScreen(bidPackageId: n(3)!);
  } else {
    final page = pageForPath(uri.path);
    if (page != null) screen = RootPageScreen(page: page, initialTab: tab);
  }
  if (screen == null) {
    showToast(context, 'This link opens on the web only', error: true);
    return;
  }
  await push(context, screen);
}

/// A top-level page opened on its own (from a notification or search) with a back button.
class RootPageScreen extends StatelessWidget {
  final NavPage page;
  final String? initialTab;
  const RootPageScreen({super.key, required this.page, this.initialTab});

  @override
  Widget build(BuildContext context) => AppScaffold(title: page.label, body: page.builder(initialTab));
}
