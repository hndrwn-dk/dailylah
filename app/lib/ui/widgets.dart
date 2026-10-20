import 'package:flutter/material.dart';

import '../models.dart';
import 'theme.dart';

/// Bus service number on a solid plate, like the number boards on stop poles.
class BusPlate extends StatelessWidget {
  const BusPlate(this.service, {super.key});
  final String service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        service,
        style: TextStyle(
          fontFamily: DL.display,
          fontWeight: FontWeight.w700,
          fontSize: 24,
          height: 1.1,
          color: scheme.onPrimary,
        ),
      ),
    );
  }
}

/// Three-step crowd meter for a bus: seats, standing, full.
class LoadMeter extends StatelessWidget {
  const LoadMeter(this.load, {super.key, required this.label});
  final String load;
  final String label;

  @override
  Widget build(BuildContext context) {
    final level = switch (load) {
      'SEA' => 1,
      'SDA' => 2,
      'LSD' => 3,
      _ => 0,
    };
    final scheme = Theme.of(context).colorScheme;
    final on = level == 3 ? DL.amber : scheme.primary;
    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 3; i++)
            Container(
              width: 7,
              height: 7 + i * 3.0,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: i <= level ? on : scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// MRT line code on its official colour.
class LineChip extends StatelessWidget {
  const LineChip(this.code, {super.key, this.dense = false});
  final String code;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3),
      decoration: BoxDecoration(color: DL.lineColor(code), borderRadius: BorderRadius.circular(6)),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: DL.display,
          fontWeight: FontWeight.w700,
          fontSize: dense ? 13 : 15,
          color: Colors.white,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Section title with an optional trailing action.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});
  final String text;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

enum AlertTone { info, warning }

/// A single actionable alert, shown at the top of Today.
class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.icon, required this.text, this.tone = AlertTone.warning, this.onTap});
  final IconData icon;
  final String text;
  final AlertTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final warn = tone == AlertTone.warning;
    final bg = warn ? DL.amber.withValues(alpha: 0.18) : scheme.primary.withValues(alpha: 0.10);
    final fg = warn ? const Color(0xFF8A5300) : scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).brightness == Brightness.dark ? DL.amber : fg),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: Theme.of(context).textTheme.labelLarge)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Short message for empty or failed states, with an optional action.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.icon = Icons.info_outline, this.action});
  final String text;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A big number with a small caption, used for stats in the Homes module.
class Stat extends StatelessWidget {
  const Stat({super.key, required this.value, required this.caption});
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: t.displaySmall),
        const SizedBox(height: 2),
        Text(caption, style: t.bodySmall),
      ],
    );
  }
}

/// Pill selector for which saved place a view is about. Use [onDark] inside a hero.
class PlaceSelector extends StatelessWidget {
  const PlaceSelector({
    super.key,
    required this.places,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.onDark = false,
  });
  final Iterable<PlaceKind> places;
  final PlaceKind selected;
  final String Function(PlaceKind) labelOf;
  final ValueChanged<PlaceKind> onChanged;
  final bool onDark;

  static IconData iconOf(PlaceKind k) => switch (k) {
        PlaceKind.home => Icons.home_outlined,
        PlaceKind.work => Icons.work_outline,
        PlaceKind.school => Icons.school_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final list = places.toList();
    if (list.length < 2) return const SizedBox.shrink();
    final current = list.contains(selected) ? selected : list.first;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      children: [
        for (final p in list)
          Material(
            color: p == current
                ? (onDark ? Colors.white : DL.ink)
                : (onDark ? Colors.white.withValues(alpha: 0.10) : scheme.surfaceContainerLowest),
            shape: StadiumBorder(
              side: BorderSide(color: onDark ? Colors.white24 : scheme.outlineVariant, width: p == current ? 0 : 1),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onChanged(p),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconOf(p),
                        size: 16,
                        color: p == current ? (onDark ? DL.ink : Colors.white) : (onDark ? Colors.white : null)),
                    const SizedBox(width: 6),
                    Text(
                      labelOf(p),
                      style: t.labelLarge?.copyWith(
                        color: p == current ? (onDark ? DL.ink : Colors.white) : (onDark ? Colors.white : null),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Full-bleed header at the top of a tab: a deep "night over the Straits" gradient
/// with rounded lower corners. Content below it can overlap via [overlap].
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.accent = DL.teal});
  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DL.night, DL.ink, Color.lerp(DL.ink, accent, 0.55)!],
          stops: const [0, 0.55, 1],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          // A soft glow, like the city lights on the horizon.
          Positioned(
            right: -60,
            top: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [accent.withValues(alpha: 0.45), accent.withValues(alpha: 0)]),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: IconTheme.merge(data: const IconThemeData(color: Colors.white), child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large screen title used on tabs, matching the hero type.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.displayMedium?.copyWith(color: Colors.white)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: t.bodyMedium?.copyWith(color: Colors.white70)),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Square-ish tile for a bento row: icon, big value, caption.
class BentoTile extends StatelessWidget {
  const BentoTile({
    super.key,
    required this.icon,
    required this.value,
    required this.caption,
    this.tint,
    this.onTap,
  });
  final IconData icon;
  final String value;
  final String caption;
  final Color? tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = tint ?? Theme.of(context).colorScheme.primary;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, size: 20, color: c),
              ),
              const SizedBox(height: 14),
              Text(value, style: t.displaySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(caption, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
