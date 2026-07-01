import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

class YolaLogoLockup extends StatelessWidget {
  final bool compact;
  final Color? captionColor;

  const YolaLogoLockup({
    super.key,
    this.compact = false,
    this.captionColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = captionColor ?? theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              AppTheme.successGreen,
              Color(0xFF00B7FF),
              AppTheme.primaryBlue,
              Color(0xFF7C3AED),
            ],
          ).createShader(bounds),
          child: Text(
            'yola',
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontSize: compact ? 36 : 54,
              fontWeight: FontWeight.w900,
              height: 0.9,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'by Double Gee',
          style: theme.textTheme.labelMedium?.copyWith(
            color: caption,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class YolaGradientPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry? borderRadius;

  const YolaGradientPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(AppRadius.xxl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF00133D),
            Color(0xFF012A72),
            Color(0xFF0646D8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.24),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class YolaGradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const YolaGradientButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            AppTheme.primaryBlue,
            Color(0xFF12B8D8),
            AppTheme.successGreen,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.22),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class GoogleSignInPlaceholderButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const GoogleSignInPlaceholderButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Text(
        'G',
        style: TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    );
  }
}

class LanguageSelectorPlaceholder extends StatelessWidget {
  const LanguageSelectorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      builder: (context, controller, child) {
        return OutlinedButton.icon(
          onPressed: () {
            controller.isOpen ? controller.close() : controller.open();
          },
          icon: const Icon(Icons.language),
          label: const Text('English'),
        );
      },
      menuChildren: const [
        MenuItemButton(
          leadingIcon: Icon(Icons.check),
          child: Text('English'),
        ),
        MenuItemButton(
          child: Text('Shona'),
        ),
        MenuItemButton(
          child: Text('Ndebele'),
        ),
      ],
    );
  }
}

class TermsPrivacyConsent extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const TermsPrivacyConsent({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CheckboxListTile(
      value: value,
      onChanged: (checked) => onChanged(checked ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            const TextSpan(text: 'I agree to the '),
            TextSpan(
              text: 'Terms of Service',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const TextSpan(text: ' and '),
            TextSpan(
              text: 'Privacy Policy',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppVersionUpdateRoom extends StatelessWidget {
  final AppUpdateStatus? update;

  const AppVersionUpdateRoom({
    super.key,
    this.update,
  });

  @override
  Widget build(BuildContext context) {
    final status = update;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: Icon(
              Icons.system_update_alt,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Double Gee Business Suite v${UpdateService.currentVersion}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  status?.message ?? 'Update checks are ready for production.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
