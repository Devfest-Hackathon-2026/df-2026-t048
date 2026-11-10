import '../l10n/app_localizations.dart';
import 'dart:io' show Platform;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Quiet, non-interactive color beneath translucent controls.
class PostCheckBackdrop extends StatelessWidget {
  const PostCheckBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final solid =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6FA),
              gradient: solid
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF6F8FC),
                        Color(0xFFEAF1FA),
                        Color(0xFFF6F3F9),
                      ],
                    ),
            ),
            child: solid
                ? null
                : const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(.95, -.8),
                        radius: 1.05,
                        colors: [Color(0xA6C8DDFA), Color(0x00C8DDFA)],
                      ),
                    ),
                  ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Native Liquid Glass on iOS 26, native material on older iOS; Flutter fallback
/// for other platforms and capture tests. Never used for long-form content.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.dark = false,
    this.radius = 24,
    this.native = true,
  });
  final Widget child;
  final bool dark, native;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final solid =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final useNative = native && !solid && !kIsWeb && Platform.isIOS;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: useNative
                    ? UiKitView(
                        viewType: 'postcheck/glass',
                        creationParams: {'radius': radius, 'dark': dark},
                        creationParamsCodec: const StandardMessageCodec(),
                      )
                    : BackdropFilter(
                        filter: ImageFilter.blur(
                          sigmaX: solid ? 0 : 18,
                          sigmaY: solid ? 0 : 18,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color:
                                (dark ? const Color(0xFF202022) : Colors.white)
                                    .withValues(
                                      alpha: solid ? 1 : (dark ? .72 : .68),
                                    ),
                            borderRadius: BorderRadius.circular(radius),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: dark ? .18 : .6,
                              ),
                              width: .5,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Material(type: MaterialType.transparency, child: child),
        ],
      ),
    );
  }
}

class AppleIconButton extends StatelessWidget {
  const AppleIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.dark = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool dark;
  @override
  Widget build(BuildContext context) => GlassSurface(
    dark: dark,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tr(context, label),
      icon: Icon(icon, size: 22),
      color: dark ? Colors.white : const Color(0xFF1C1C1E),
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    ),
  );
}

class AppleBar extends StatelessWidget implements PreferredSizeWidget {
  const AppleBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.automaticallyImplyLeading = true,
  });
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;
  final bool automaticallyImplyLeading;
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) => AppBar(
    title: title,
    leading: leading,
    actions: [...actions, const SizedBox(width: 8)],
    automaticallyImplyLeading: automaticallyImplyLeading,
    centerTitle: true,
    flexibleSpace: const GlassSurface(radius: 0, child: SizedBox.expand()),
  );
}

class AppleSection extends StatelessWidget {
  const AppleSection({
    super.key,
    this.title,
    required this.children,
    this.footer,
  });
  final String? title, footer;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: AppText(
              title!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        GlassSurface(
          radius: 24,
          native: false,
          child: Material(
            color: Colors.transparent,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Divider(height: .5, thickness: .5),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AppText(
              footer!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    ),
  );
}

class AppleRow extends StatelessWidget {
  const AppleRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.translateTitle = true,
    this.translateSubtitle = true,
    this.translateValue = true,
  });
  final String title;
  final String? subtitle, value;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final bool translateTitle, translateSubtitle, translateValue;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: icon == null
        ? null
        : Icon(
            icon,
            color: destructive
                ? CupertinoColors.systemRed
                : CupertinoColors.activeBlue,
            size: 23,
          ),
    title: Text(
      translateTitle ? tr(context, title) : title,
      style: TextStyle(color: destructive ? CupertinoColors.systemRed : null),
    ),
    subtitle: subtitle == null
        ? null
        : Text(translateSubtitle ? tr(context, subtitle!) : subtitle!),
    trailing:
        trailing ??
        (value == null
            ? (onTap == null
                  ? null
                  : const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 15,
                      color: CupertinoColors.systemGrey,
                    ))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    translateValue ? tr(context, value!) : value!,
                    style: const TextStyle(
                      color: CupertinoColors.systemGrey,
                      fontSize: 15,
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.chevron_forward,
                      size: 15,
                      color: CupertinoColors.systemGrey,
                    ),
                  ],
                ],
              )),
    onTap: onTap,
  );
}

Future<T?> appleSheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF2F2F7),
      builder: (_) => FractionallySizedBox(heightFactor: .82, child: child),
    );
