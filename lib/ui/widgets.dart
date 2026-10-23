import "package:flutter/material.dart";

import "theme.dart";

/// Small rounded label ("VLESS", "Locked", "Expired"…).
class Pill extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const Pill(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4)
          ],
          Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w500, color: fg)),
          ),
        ],
      ),
    );
  }
}

/// A rounded square holding an icon (list leading, settings rows, empty states).
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  const IconTile(this.icon, {super.key, this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.colors.brand;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: fg, size: size * 0.5),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// A card that groups settings rows with hairline dividers.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(indent: 72));
      rows.add(children[i]);
    }
    return Card(clipBehavior: Clip.antiAlias, child: Column(children: rows));
  }
}

/// One row in a [SettingsGroup].
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconTile(icon, size: 40, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 15)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: context.colors.muted,
                                height: 1.35)),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      );
}

/// Centered illustration + text + optional actions for empty lists.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.body,
      this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: c.brandSoft),
              child: Icon(icon, size: 44, color: c.brand),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, height: 1.6)),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              ...actions.expand((a) => [a, const SizedBox(height: 10)]),
            ],
          ],
        ),
      ),
    );
  }
}

/// Subtle gradient behind the page header, in the brand colour.
class GlowBackdrop extends StatelessWidget {
  final double height;
  const GlowBackdrop({super.key, this.height = 360});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
            height: height,
            decoration: BoxDecoration(gradient: context.colors.heroGlow)),
      );
}
