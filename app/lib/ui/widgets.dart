import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import 'app_frame.dart';
import 'theme.dart';

/// Bus service number on a solid plate, like the number boards on stop poles.
class BusPlate extends StatelessWidget {
  const BusPlate(this.service, {super.key});
  final String service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 60),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: DL.edge(context), width: 2),
        boxShadow: DL.hard(context, d: 2.5),
      ),
      // Center with factors keeps the plate as wide as its number (at least 60): plain
      // alignment made it fill the whole width in a ListTile and squeezed the title.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        // The number is already big (24): it grows with system text up to 130%, so at 200% on a
        // 320 dp phone the arrival times beside it keep room to be read.
        child: Text(
          service,
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
          style: TextStyle(
            fontFamily: DL.display,
            fontWeight: FontWeight.w700,
            fontSize: 24,
            height: 1.1,
            color: scheme.onPrimary,
          ),
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
    // A Wrap, so the label goes under the bars at 200% text on a narrow phone instead of
    // overflowing the row; the label itself wraps too.
    return Semantics(
      label: label,
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
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
            ],
          ),
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
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 1 : 2),
      decoration: BoxDecoration(
        color: DL.lineColor(code),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: DL.edge(context), width: 2),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: DL.display,
          fontWeight: FontWeight.w700,
          fontSize: dense ? 13 : 15,
          color: DL.onColor(DL.lineColor(code)),
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// The app's card: an outlined panel with a hard offset shadow, like a printed sticker.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.margin = const EdgeInsets.only(bottom: 16), this.color});
  final Widget child;
  final EdgeInsetsGeometry margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(DL.radius);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: r,
          border: Border.all(color: DL.edge(context), width: DL.stroke),
          boxShadow: DL.hard(context),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DL.radius - DL.stroke),
          child: Material(type: MaterialType.transparency, child: child),
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
          if (trailing != null) Flexible(child: trailing!),
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
    final warn = tone == AlertTone.warning;
    final r = BorderRadius.circular(12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: warn ? DL.amber : Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: r,
          border: Border.all(color: DL.edge(context), width: DL.stroke),
          boxShadow: DL.hard(context, d: 3),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            // At least 48 dp tall, the tap target TalkBack and Material ask for.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: warn ? DL.ink : null),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: warn ? DL.ink : null),
                      ),
                    ),
                  ],
                ),
              ),
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
        PlaceKind.other => Icons.star_outline,
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
            // TalkBack says which place is on; each pill is at least 48 dp tall.
            child: Semantics(
              button: true,
              selected: p == current,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => onChanged(p),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
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
            ),
          ),
      ],
    );
  }
}

/// Header at the top of a tab: big ink headline straight on the paper background,
/// like the reference sticker UI. Content inside uses the normal (dark) text colours.
class HeroHeader extends StatelessWidget {
  const HeroHeader({super.key, required this.child, this.accent = DL.teal});
  final Widget child;

  /// Kept for call sites; the light header has no tinted background.
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
        child: child,
      ),
    );
  }
}

/// Small square sticker button (search, back) used in headers.
class StickerIconButton extends StatelessWidget {
  const StickerIconButton({super.key, required this.icon, required this.onPressed, required this.tooltip});
  final IconData icon;
  final VoidCallback onPressed;

  /// Also the TalkBack label: an icon-only button must say what it does.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(12);
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          borderRadius: r,
          border: Border.all(color: DL.edge(context), width: DL.stroke),
          boxShadow: DL.hard(context, d: 3),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: r,
            onTap: onPressed,
            child: SizedBox(
                width: kMinInteractiveDimension, height: kMinInteractiveDimension, child: Icon(icon, size: 22)),
          ),
        ),
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
              Text(title, style: t.displayLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: t.bodyMedium?.copyWith(color: t.bodySmall?.color)),
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
    final highlighted = tint == DL.amber;
    return Panel(
      margin: EdgeInsets.zero,
      color: highlighted ? DL.amber : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: highlighted ? DL.card : (tint ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: DL.edge(context), width: 2),
                ),
                child: Icon(icon, size: 18, color: highlighted ? DL.ink : tint ?? Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 12),
              Text(value,
                  style: t.displaySmall?.copyWith(color: highlighted ? DL.ink : null),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(caption,
                  style: t.bodySmall?.copyWith(color: highlighted ? DL.ink : null),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Display name of a place: its own name for custom places, else the kind label.
String placeTitle(String Function(String) placeLabel, Place p) =>
    p.kind == PlaceKind.other && (p.name?.isNotEmpty ?? false) ? p.name! : placeLabel(p.kind.name);

/// A horizontally scrolling row of chunky pills: (key, icon, label).
class PillRow extends StatelessWidget {
  const PillRow({
    super.key,
    required this.items,
    required this.selected,
    required this.onTap,
    this.onDark = false,
    this.danger = const {},
  });
  final List<(String, IconData, String)> items;

  /// Keys drawn in red (e.g. "emergency"): red fill when selected, red text otherwise.
  final Set<String> danger;
  final String selected;
  final ValueChanged<String> onTap;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final edge = onDark ? DL.ink : DL.edge(context);
    // Wraps onto more lines so every choice stays visible (no hidden sideways scroll).
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (key, icon, label) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 3, right: 3),
              child: _Pill(
                icon: icon,
                label: label,
                selected: key == selected,
                danger: danger.contains(key),
                edge: edge,
                onDark: onDark,
                style: t.labelLarge,
                onTap: () => onTap(key),
              ),
            ),
        ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.edge,
    required this.onDark,
    required this.style,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool danger;
  final Color edge;
  final bool onDark;
  final TextStyle? style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (danger ? DL.stopDeep : DL.amber)
        : (onDark ? DL.card : Theme.of(context).colorScheme.surfaceContainerLowest);
    // Selected pills are amber (ink text); unselected ones sit on the card surface, which is
    // dark in dark mode, so their text follows the theme.
    final fg = danger
        ? (selected ? Colors.white : DL.stopText(context))
        : (selected || onDark ? DL.ink : Theme.of(context).colorScheme.onSurface);
    final r = BorderRadius.circular(12);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: r,
        border: Border.all(color: edge, width: DL.stroke),
        boxShadow: selected ? [BoxShadow(color: edge, offset: const Offset(3, 3))] : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        // TalkBack says which pill is on; the pill is at least 48 dp tall.
        child: Semantics(
          button: true,
          selected: selected,
          child: InkWell(
            borderRadius: r,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: style?.copyWith(color: fg)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Gentle blink for things happening right now (a bus arriving). Holds still when the
/// system asks for reduced motion.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child});
  final Widget child;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.55, end: 1).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: widget.child,
      );
}


/// Space to leave under scrolling content so the floating nav never covers it.
const kNavClearance = 96.0;

/// Floating pill navigation: an outlined capsule with a hard shadow; the selected tab
/// grows into an amber pill with its label.
class PillNav extends StatelessWidget {
  const PillNav({super.key, required this.index, required this.onTap, required this.items});
  final int index;
  final ValueChanged<int> onTap;

  /// (icon, selected icon, label)
  final List<(IconData, IconData, String)> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Container(
      height: 64,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: DL.edge(context), width: DL.stroke),
        boxShadow: DL.hard(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              flex: i == index ? 2 : 1,
              child: Tooltip(
                message: items[i].$3,
                child: Semantics(
                  selected: i == index,
                  button: true,
                  label: items[i].$3,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: () => onTap(i),
                    child: AnimatedContainer(
                      duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: EdgeInsets.fromLTRB(2, 0, i == index ? 5 : 2, i == index ? 3 : 0),
                      // Same look as the selected place pill: full-height amber sticker
                      // with an ink outline and a hard shadow.
                      decoration: BoxDecoration(
                        color: i == index ? DL.amber : Colors.transparent,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: i == index ? DL.ink : Colors.transparent, width: DL.stroke),
                        boxShadow: i == index ? const [BoxShadow(color: DL.ink, offset: Offset(3, 3))] : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(i == index ? items[i].$2 : items[i].$1,
                              size: 22, color: i == index ? DL.ink : t.bodySmall?.color),
                          if (i == index) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                items[i].$3,
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: t.labelLarge?.copyWith(color: DL.ink),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// Station code in its line colour, like the station signs ("TE26", "DT17").
class StationChip extends StatelessWidget {
  const StationChip(this.code, {super.key});
  final String code;

  @override
  Widget build(BuildContext context) {
    final line = lineOfCode(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: DL.lineColor(line ?? ''),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DL.edge(context), width: 2),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontFamily: DL.display,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// The home block number set big, like the numbers painted high on HDB blocks.
class PaintedBlockNumber extends StatelessWidget {
  const PaintedBlockNumber(this.number, {super.key, this.size = 96});
  final String number;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).brightness == Brightness.dark ? DL.card : DL.ink;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'BLK',
          style: TextStyle(fontFamily: DL.display, fontWeight: FontWeight.w700, fontSize: size * 0.2, color: ink, letterSpacing: 2, height: 1),
        ),
        Text(
          number,
          style: TextStyle(fontFamily: DL.display, fontWeight: FontWeight.w700, fontSize: size, color: ink, height: 0.95),
        ),
        // The painted band under the number.
        Container(width: size * 0.9, height: size * 0.07, color: DL.go),
      ],
    );
  }
}

/// One arrival on the bus stop board.
class BoardRow {
  const BoardRow({
    required this.service,
    required this.minutes,
    this.next,
    this.note = '',
    this.live,
    this.load = '',
    this.info = '',
    this.onTap,
    this.dim = false,
    this.tag,
  });
  final String service;
  final int minutes;

  /// Drawn in the dim LED colour, for a bus the rider cannot catch.
  final bool dim;

  /// A short label next to the arrival, e.g. "Too soon".
  final String? tag;
  final int? next;
  final String note;

  /// Where the bus is now ("Now near Blk 201 · 3 stops away"), shown in LED colour.
  final String? live;

  /// LTA load code (SEA/SDA/LSD), drawn as a meter before [info] ("Seats free · ♿ Wheelchair").
  final String load;
  final String info;

  /// Opens "Where's my bus?"; the row shows a chevron when set.
  final VoidCallback? onTap;
}

/// Bus load as 1–3 bars: teal for seats or standing, amber when packed. [onDark] for the LED board.
class LoadBars extends StatelessWidget {
  const LoadBars(this.load, {super.key, this.onDark = false});
  final String load;
  final bool onDark;

  static int level(String load) => switch (load) {
        'SEA' => 1,
        'SDA' => 2,
        'LSD' => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final lv = level(load);
    final on = lv == 3 ? DL.amber : (onDark ? DL.tealLight : Theme.of(context).colorScheme.primary);
    final off = onDark ? const Color(0xFF3A4A4E) : Theme.of(context).colorScheme.outlineVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 3; i++)
          Container(
            width: 6,
            height: 5 + i * 3.0,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(color: i <= lv ? on : off, borderRadius: BorderRadius.circular(2)),
          ),
      ],
    );
  }
}

/// Live arrivals on a dark LED board, like the panels at bus stops. Rows with [BoardRow.onTap]
/// can be tapped; [hint] then explains it under the rows.
class BusBoard extends StatelessWidget {
  const BusBoard({
    super.key,
    required this.rows,
    required this.arrLabel,
    required this.minLabel,
    required this.thenLabel,
    this.hint,
  });
  final List<BoardRow> rows;
  final String arrLabel;
  final String minLabel;
  final String Function(int) thenLabel;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    const led = TextStyle(fontFamily: DL.display, fontWeight: FontWeight.w700, color: DL.led, height: 1.05);
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: DL.ledDim);
    final tappable = rows.any((r) => r.onTap != null);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
      decoration: BoxDecoration(
        color: DL.board,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DL.edge(context), width: DL.stroke),
        boxShadow: DL.hard(context, d: 3),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 8), color: const Color(0x33FFB627)),
              InkWell(
                onTap: r.onTap,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
                  child: _BoardRowLayout(
                    service: ConstrainedBox(
                      // Bounded so large system text cannot push the row past the edge.
                      constraints: const BoxConstraints(minWidth: 62, maxWidth: 96),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topLeft,
                        child: Text(r.service, style: led.copyWith(fontSize: 30, color: r.dim ? DL.ledDim : DL.led)),
                      ),
                    ),
                    time: Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(r.minutes == 0 ? arrLabel : '${r.minutes} $minLabel',
                            style: led.copyWith(fontSize: 30, color: r.dim ? DL.ledDim : DL.led)),
                        if (r.next != null) Text(thenLabel(r.next!), style: led.copyWith(fontSize: 18, color: DL.ledDim)),
                        if (r.tag case final tag?)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: DL.ledDim),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(tag, style: small),
                          ),
                      ],
                    ),
                    details: [
                      if (r.live != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 2),
                          child: Text.rich(
                            TextSpan(children: [
                              const WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Icon(Icons.my_location, size: 14, color: DL.led),
                                ),
                              ),
                              TextSpan(text: r.live),
                            ]),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: r.dim ? DL.ledDim : DL.led),
                          ),
                        ),
                      if (r.info.isNotEmpty)
                        Text.rich(
                          TextSpan(children: [
                            if (LoadBars.level(r.load) > 0)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 5),
                                  child: LoadBars(r.load, onDark: true),
                                ),
                              ),
                            TextSpan(text: r.info),
                          ]),
                          style: small,
                        ),
                      if (r.note.isNotEmpty) Text(r.note, style: small),
                    ],
                    chevron: r.onTap == null
                        ? null
                        : const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Icon(Icons.chevron_right, size: 20, color: DL.ledDim),
                          ),
                  ),
                ),
              ),
            ],
            if (tappable && hint != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Text(hint!, textAlign: TextAlign.end, style: small),
              ),
          ],
        ),
      ),
    );
  }
}

/// One board row: the service number, then its time and details beside it. When the column beside
/// the number gets too narrow for whole words (large text, small screens), the details go under the
/// number and time at full width, so "Wheelchair" or a stop name moves down whole instead of
/// breaking inside the word.
class _BoardRowLayout extends StatelessWidget {
  const _BoardRowLayout({required this.service, required this.time, required this.details, this.chevron});
  final Widget service;
  final Widget time;
  final List<Widget> details;
  final Widget? chevron;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(builder: (context, box) {
      // The number takes 62 dp at normal text (more only at large text), the gap 10 and the chevron
      // about 24: beside it on phones from 320 dp at 100% text, as before.
      final beside = box.maxWidth - 62 - 10 - 24 >= 150 * scale;
      final top = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          service,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [time, if (beside) ...details],
            ),
          ),
          if (chevron case final c?) c,
        ],
      );
      if (beside || details.isEmpty) return top;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          top,
          Padding(
            padding: const EdgeInsets.only(top: 4, right: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: details),
          ),
        ],
      );
    });
  }
}

/// "Good time to go?" for parks: teal when fine, amber when the weather says wait.
class ParkTimeBanner extends StatelessWidget {
  const ParkTimeBanner({super.key, required this.time, required this.text, this.margin = const EdgeInsets.only(bottom: 12)});
  final ParkTime time;
  final String text;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final good = time == ParkTime.good || time == ParkTime.goodNight;
    return Panel(
      margin: margin,
      color: good ? DL.mint : DL.attention,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              switch (time) {
                ParkTime.lightning => Icons.flash_on,
                ParkTime.rain || ParkTime.showers => Icons.umbrella_outlined,
                ParkTime.haze => Icons.masks_outlined,
                ParkTime.heat || ParkTime.uv => Icons.wb_sunny_outlined,
                ParkTime.good => Icons.check_circle_outline,
                ParkTime.goodNight => Icons.nightlight_outlined,
              },
              color: good ? DL.tealText : DL.ink,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DL.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon for a park facility label from the poi bundle ("Toilet", "Playground"...).
IconData facilityIcon(String label) => switch (label) {
      'Playground' => Icons.toys_outlined,
      'Fitness corner' => Icons.fitness_center,
      'Toilet' => Icons.wc,
      'Car park' => Icons.local_parking,
      'Shelter' => Icons.roofing,
      'BBQ pit' => Icons.outdoor_grill_outlined,
      'Dog run' => Icons.pets,
      'Cycling' => Icons.directions_bike,
      'Bike rack' => Icons.pedal_bike,
      'Water' => Icons.water_drop_outlined,
      'Food' => Icons.restaurant_outlined,
      'Pond' => Icons.water,
      'Lookout' => Icons.landscape_outlined,
      'Camping' => Icons.cabin_outlined,
      'Bike rental' => Icons.directions_bike_outlined,
      'Foot reflexology' => Icons.spa_outlined,
      'Sports court' => Icons.sports_basketball_outlined,
      'Amphitheatre' => Icons.theater_comedy_outlined,
      'Community garden' => Icons.yard_outlined,
      'Therapeutic garden' => Icons.local_florist_outlined,
      'Baby room' => Icons.child_friendly_outlined,
      'Jetty' => Icons.sailing_outlined,
      _ => Icons.check_circle_outline,
    };

/// Small outlined chips, e.g. park facilities, that wrap at large text sizes.
/// With [icons], each chip starts with its facility icon.
class InfoChips extends StatelessWidget {
  const InfoChips(this.labels, {super.key, this.icons = false});
  final List<String> labels;
  final bool icons;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final l in labels)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: DL.edge(context), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icons) ...[Icon(facilityIcon(l), size: 16), const SizedBox(width: 4)],
                  Flexible(child: Text(l, style: Theme.of(context).textTheme.labelMedium)),
                ],
              ),
            ),
        ],
      );
}

/// A row of small facility icons for list rows; the labels are read out by screen readers.
class FacilityIcons extends StatelessWidget {
  const FacilityIcons(this.labels, {super.key});
  final List<String> labels;

  @override
  Widget build(BuildContext context) => Semantics(
        label: labels.join(', '),
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final l in labels) Tooltip(message: l, child: Icon(facilityIcon(l), size: 18)),
            ],
          ),
        ),
      );
}

/// A short message with one action (Undo, Open...). Snack bars with an action stay on screen
/// until dismissed in current Flutter (and follow the user to other pages), so this one goes
/// away by itself after a few seconds and has a close button.
void showActionSnackBar(ScaffoldMessengerState messenger, String text, {String? actionLabel, VoidCallback? onAction}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(text),
    duration: const Duration(seconds: 4),
    persist: false,
    showCloseIcon: true,
    action: actionLabel == null || onAction == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction),
  ));
}

/// Cancel and confirm side by side for an AlertDialog's actions, equal width. The theme makes
/// filled buttons full width, which pushed Cancel onto its own line above a wide confirm button.
class DialogButtons extends StatelessWidget {
  const DialogButtons({
    super.key,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
  });
  final String cancelLabel;
  final String confirmLabel;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: onCancel,
              child: Text(cancelLabel, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: onConfirm,
              child: Text(confirmLabel, textAlign: TextAlign.center),
            ),
          ),
        ],
      );
}

/// Closes the keyboard, waits until it is gone, then pops [result]. Popping while the
/// keyboard is still up left the page below half drawn on some phones (blank where the
/// keyboard was) until something else redrew it.
Future<void> popAfterKeyboard<T>(BuildContext context, [T? result]) async {
  final nav = Navigator.of(context);
  FocusManager.instance.primaryFocus?.unfocus();
  final view = View.of(context);
  for (var i = 0; i < 12 && view.viewInsets.bottom > 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  if (nav.mounted) nav.pop(result);
}

/// A big count with a small label under it, right-aligned (car park lots, EV chargers);
/// [warn] draws it in an amber box (nothing free).
class BigNumber extends StatelessWidget {
  const BigNumber({super.key, required this.value, required this.label, this.warn = false});
  final String value;
  final String label;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: warn
          ? BoxDecoration(
              color: DL.attention,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DL.edge(context), width: 2),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(value, style: t.displaySmall?.copyWith(fontSize: 26, height: 1, color: warn ? DL.ink : null)),
          Text(label, textAlign: TextAlign.end, style: t.labelSmall?.copyWith(color: warn ? DL.ink : null)),
        ],
      ),
    );
  }
}

/// One to three people for a station's crowd level ('l', 'm', 'h'); the text beside it says
/// the level, so this is decoration for screen readers.
class CrowdPeople extends StatelessWidget {
  const CrowdPeople(this.level, {super.key});
  final String level;

  @override
  Widget build(BuildContext context) {
    final n = switch (level) { 'h' => 3, 'm' => 2, _ => 1 };
    final on = Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Icon(i < n ? Icons.person : Icons.person_outline, size: 18, color: i < n ? on : DL.muted(context)),
        ],
      ),
    );
  }
}

/// Optional meal price: quick chips ($4, $6, $8) and "Other" for a typed amount. Amber marks the
/// picked price (look now); tapping it again clears it, a typed one too. [value] is in cents,
/// null for no price.
class MealPricePicker extends StatelessWidget {
  const MealPricePicker({super.key, required this.s, required this.value, required this.onChanged});
  final S s;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final other = v != null && !mealPriceChips.contains(v);
    Widget chip(String label, bool on, VoidCallback onTap) => ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          selectedColor: DL.amber,
          labelStyle: on ? const TextStyle(color: DL.ink, fontWeight: FontWeight.w700) : null,
          side: BorderSide(color: DL.edge(context), width: on ? DL.stroke : 1),
          onSelected: (_) => onTap(),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final c in mealPriceChips) chip(s.moneyShort(c), v == c, () => onChanged(v == c ? null : c)),
        chip(other ? s.money(v) : s.mealPriceOther, other, () async {
          if (other) return onChanged(null);
          final typed = await askMealPrice(context, s, null);
          if (typed != null) onChanged(typed);
        }),
      ],
    );
  }
}

/// Asks for a meal price in SGD (2 decimals, up to $200); null when cancelled.
Future<int?> askMealPrice(BuildContext context, S s, int? initial) =>
    showDialog<int>(context: context, builder: (_) => _MealPriceDialog(s: s, initial: initial));

class _MealPriceDialog extends StatefulWidget {
  const _MealPriceDialog({required this.s, required this.initial});
  final S s;
  final int? initial;

  @override
  State<_MealPriceDialog> createState() => _MealPriceDialogState();
}

class _MealPriceDialogState extends State<_MealPriceDialog> {
  late final _ctrl = TextEditingController(text: widget.initial == null ? '' : (widget.initial! / 100).toStringAsFixed(2));
  bool _bad = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    final c = parseMealCents(_ctrl.text);
    if (c == null) {
      setState(() => _bad = true);
      return;
    }
    Navigator.of(context).pop(c);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return AlertDialog(
      title: Text(s.mealPriceAsk),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}([.,]\d{0,2})?'))],
        decoration: InputDecoration(prefixText: r'$ ', labelText: s.costLabel, errorText: _bad ? s.mealPriceInvalid : null),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        DialogButtons(
          cancelLabel: s.cancel,
          confirmLabel: s.save,
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _save,
        ),
      ],
    );
  }
}


/// Marks a child of [CardColumns] that spans both columns on a wide window: a banner, a row
/// of tiles, a note under the cards. On a phone it is just its child.
class FullWidth extends StatelessWidget {
  const FullWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Marks a child of [CardColumns] that belongs to the child after it (a heading that is not a
/// [SectionTitle]): on a wide window it stays in that card's column. On a phone it is just its child.
class KeepWithNext extends StatelessWidget {
  const KeepWithNext({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// The cards of a tab: one column on a phone, two on a wide window ([isWide]).
///
/// On a phone the children are stacked and stretched to the width, like the `Column` the tabs
/// always had. On a wide window they keep their order: each run of cards between two
/// [FullWidth] children is split once, where the two columns come out closest in height, and
/// reads down the left column and then down the right one. A [SectionTitle], a [KeepWithNext]
/// child or an empty `SizedBox` spacer stays in the column of the card after it.
///
/// Both layouts are the same widgets, so folding, unfolding and turning the phone keep the
/// state of the cards (an opened list, a typed text).
class CardColumns extends StatelessWidget {
  const CardColumns({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Already in one of two columns (a section's list inside a card of the page's list): stack.
    final inside = context.dependOnInheritedWidgetOfExactType<_Cell>()?.inColumn ?? false;
    final two = isWide(context) && !inside;
    return _Columns(
      two: two,
      spans: [for (final c in children) c is FullWidth],
      leads: [
        for (final c in children) c is SectionTitle || c is KeepWithNext || (c is SizedBox && c.child == null),
      ],
      // Still inside a column when this list only stacks there: a list below must not split either.
      children: [for (final c in children) c is FullWidth ? c : _Cell(inColumn: two || inside, child: c)],
    );
  }
}

/// Says whether its child sits in one of two columns, so a [CardColumns] below does not split again.
class _Cell extends InheritedWidget {
  const _Cell({required this.inColumn, required super.child});
  final bool inColumn;

  @override
  bool updateShouldNotify(_Cell old) => old.inColumn != inColumn;
}

class _Columns extends MultiChildRenderObjectWidget {
  const _Columns({required this.two, required this.spans, required this.leads, required super.children});

  /// Two columns, or one.
  final bool two;

  /// Per child: spans both columns.
  final List<bool> spans;

  /// Per child: belongs to the child after it (a heading, a spacer).
  final List<bool> leads;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderColumns(two, spans, leads);

  @override
  void updateRenderObject(BuildContext context, covariant _RenderColumns renderObject) =>
      renderObject.update(two, spans, leads);
}

class _ColumnsParentData extends ContainerBoxParentData<RenderBox> {}

/// Where to split a run of cards with these [heights] into a left and a right column: the
/// number of cards on the left. The taller column is as short as it can be (on a tie the left
/// one is the taller), and a card whose [leads] flag is set is never the last on the left.
int splitColumns(List<double> heights, List<bool> leads) {
  final total = heights.fold<double>(0, (a, b) => a + b);
  var best = heights.length;
  var bestTall = total;
  var left = 0.0;
  for (var k = 1; k < heights.length; k++) {
    left += heights[k - 1];
    if (leads[k - 1]) continue;
    final right = total - left;
    final tall = left > right ? left : right;
    if (tall < bestTall || (tall == bestTall && left >= right)) {
      best = k;
      bestTall = tall;
    }
  }
  return best;
}

class _RenderColumns extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ColumnsParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ColumnsParentData> {
  _RenderColumns(this._two, this._spans, this._leads);

  bool _two;
  List<bool> _spans;
  List<bool> _leads;

  void update(bool two, List<bool> spans, List<bool> leads) {
    _two = two;
    _spans = spans;
    _leads = leads;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ColumnsParentData) child.parentData = _ColumnsParentData();
  }

  /// Lays the children out for [width] and returns the height. [heightOf] gives a child's
  /// height at a width; [place] is told where each child goes (not when only measuring).
  double _arrange(
    double width,
    double Function(RenderBox child, double width) heightOf,
    void Function(RenderBox child, Offset at)? place,
  ) {
    final column = _two ? (width - kColumnGap) / 2 : width;
    final boxes = getChildrenAsList();
    var y = 0.0;
    var i = 0;
    while (i < boxes.length) {
      if (!_two || _spans[i]) {
        place?.call(boxes[i], Offset(0, y));
        y += heightOf(boxes[i], width);
        i++;
        continue;
      }
      var end = i;
      while (end < boxes.length && !_spans[end]) {
        end++;
      }
      final heights = [for (var n = i; n < end; n++) heightOf(boxes[n], column)];
      final k = splitColumns(heights, _leads.sublist(i, end));
      var left = 0.0;
      var right = 0.0;
      for (var n = 0; n < heights.length; n++) {
        if (n < k) {
          place?.call(boxes[i + n], Offset(0, y + left));
          left += heights[n];
        } else {
          place?.call(boxes[i + n], Offset(column + kColumnGap, y + right));
          right += heights[n];
        }
      }
      y += left > right ? left : right;
      i = end;
    }
    return y;
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final height = _arrange(
      width,
      (child, w) {
        child.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
        return child.size.height;
      },
      (child, at) => (child.parentData! as _ColumnsParentData).offset = at,
    );
    size = constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    final height =
        _arrange(width, (child, w) => child.getDryLayout(BoxConstraints.tightFor(width: w)).height, null);
    return constraints.constrain(Size(width, height));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _arrange(width, (child, w) => child.getMinIntrinsicHeight(w), null);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _arrange(width, (child, w) => child.getMaxIntrinsicHeight(w), null);

  double _widest(double Function(RenderBox child) widthOf) {
    var widest = 0.0;
    for (final (i, child) in getChildrenAsList().indexed) {
      final w = widthOf(child);
      final needs = _two && !_spans[i] ? 2 * w + kColumnGap : w;
      if (needs > widest) widest = needs;
    }
    return widest;
  }

  @override
  double computeMinIntrinsicWidth(double height) => _widest((c) => c.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) => _widest((c) => c.getMaxIntrinsicWidth(double.infinity));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
