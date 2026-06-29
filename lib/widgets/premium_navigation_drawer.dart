import 'package:flutter/material.dart';

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
          ],
        ),
      ),
    );
  }
}

