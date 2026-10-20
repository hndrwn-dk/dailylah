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

/// Selector for which saved place a view is about.
class PlaceSelector extends StatelessWidget {
  const PlaceSelector({
    super.key,
    required this.places,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });
  final Iterable<PlaceKind> places;
  final PlaceKind selected;
  final String Function(PlaceKind) labelOf;
  final ValueChanged<PlaceKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final list = places.toList();
    if (list.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SegmentedButton<PlaceKind>(
        showSelectedIcon: false,
        segments: [for (final p in list) ButtonSegment(value: p, label: Text(labelOf(p)))],
        selected: {list.contains(selected) ? selected : list.first},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}
