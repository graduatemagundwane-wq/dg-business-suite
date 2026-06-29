import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../session/app_session.dart';
import '../theme/app_tokens.dart';

class PremiumNavigationItem {
  final String label;
  final IconData icon;
  final WidgetBuilder builder;
  final bool ownerOnly;

  const PremiumNavigationItem({
    required this.label,
    required this.icon,
    required this.builder,
    this.ownerOnly = false,
  });
}

class PremiumNavigationDrawer extends StatelessWidget {
  final AppSession session;
  final List<PremiumNavigationItem> items;

  const PremiumNavigationDrawer({
    super.key,
    required this.session,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleItems = items
        .where((item) => !item.ownerOnly || session.isOwner)
        .toList(growable: false);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: AppInsets.card,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.storefront),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.shopName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          session.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.sm),
                itemCount: visibleItems.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final item = visibleItems[index];

                  return ListTile(
                    leading: Icon(item.icon),
                    title: Text(item.label),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: item.builder,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Switch Mode'),
              onTap: () {
                _showSwitchModeDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSwitchModeDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Switch Mode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (session.isBusinessAccount && !session.isCustomer)
                ListTile(
                  leading: const Icon(Icons.storefront),
                  title: const Text('Customer Mode'),
                  subtitle: const Text('Browse marketplace tools'),
                  onTap: () {
                    session.switchToCustomerMode();
                    Navigator.pop(context);
                  },
                ),
              if (session.isBusinessAccount && session.isCustomer)
                ListTile(
                  leading: const Icon(Icons.work_outline),
                  title: Text(
                    session.accountIsOwner ? 'Owner Mode' : 'Employee Mode',
                  ),
                  subtitle: const Text('Return to business workspace'),
                  onTap: () {
                    session.switchToBusinessMode();
                    Navigator.pop(context);
                  },
                ),
              if (session.accountIsCustomer && kDebugMode) ...[
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Demo Owner Mode'),
                  onTap: () {
                    session.switchToDemoOwnerMode();
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.badge),
                  title: const Text('Demo Employee Mode'),
                  onTap: () {
                    session.switchToDemoEmployeeMode();
                    Navigator.pop(context);
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
