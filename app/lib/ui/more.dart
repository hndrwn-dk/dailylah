import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../background.dart' show showExampleAlerts;
import '../l10n.dart';
import '../logic.dart';
import '../models.dart';
import '../providers.dart';
import 'about.dart';
import 'setup.dart';
import 'theme.dart';
import 'widgets.dart';

/// More: setup, alert toggles, language, family share and about.
class MorePage extends ConsumerWidget {
  const MorePage({super.key, this.controller});

  /// Main list scroll, owned by the shell.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final notifier = ref.read(favoritesProvider.notifier);
    final t = Theme.of(context).textTheme;

    Widget toggle(IconData icon, String title, bool value, Favorites Function(Favorites, bool) set,
            {String? sub}) =>
        SettingTile(
          icon: icon,
          title: title,
          subtitle: sub,
          value: value,
          onTap: () => notifier.update((f) => set(f, !value)),
        );

    return Scaffold(
      body: ListView(
        controller: controller,
        padding: EdgeInsets.only(bottom: navClearance(context)),
        children: [
          HeroHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                PageTitle(s.tabMore),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: CardColumns(
              children: [
                SectionTitle(s.yourSetup),
                TileGrid(
                  children: [
                    SettingTile(
                      icon: Icons.tune,
                      title: s.editSetup,
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupPage())),
                    ),
                    SettingTile(
                      icon: Icons.qr_code_2,
                      title: s.familyShare,
                      subtitle: s.familyShareSub,
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilySharePage())),
                    ),
                  ],
                ),
                SectionTitle(
                  s.alertsTitle,
                  trailing: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(s.alertsOn(alertsOn(fav), alertKinds), style: t.bodySmall),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TileGrid(
                      children: [
                        toggle(Icons.directions_subway_outlined, s.alertMrt, fav.mrtAlerts,
                            (f, v) => f.copyWith(mrtAlerts: v), sub: s.alertMrtSub),
                        toggle(Icons.water_drop_outlined, s.alertRain, fav.rainAlerts,
                            (f, v) => f.copyWith(rainAlerts: v), sub: s.alertRainSub),
                        toggle(Icons.directions_bus_outlined, s.alertLeave, fav.leaveAlerts,
                            (f, v) => f.copyWith(leaveAlerts: v), sub: s.alertLeaveSub),
                        toggle(Icons.wb_sunny_outlined, s.alertHeat, fav.heatAlerts,
                            (f, v) => f.copyWith(heatAlerts: v), sub: s.alertNearSub),
                        toggle(Icons.bug_report_outlined, s.alertDengue, fav.dengueAlerts,
                            (f, v) => f.copyWith(dengueAlerts: v), sub: s.alertNearSub),
                        toggle(Icons.home_work_outlined, s.alertHomes, fav.homesAlerts,
                            (f, v) => f.copyWith(homesAlerts: v), sub: s.alertHomesSub),
                        toggle(Icons.restaurant_outlined, s.alertHawker, fav.hawkerAlerts,
                            (f, v) => f.copyWith(hawkerAlerts: v), sub: s.alertHawkerSub),
                        toggle(Icons.calendar_today_outlined, s.alertDigest, fav.digestAlerts,
                            (f, v) => f.copyWith(digestAlerts: v), sub: s.alertDigestSub),
                        // Lunch is a tile like the others; while it is on, its time is the link
                        // tile beside it.
                        toggle(Icons.ramen_dining_outlined, s.alertLunch, fav.lunchAlerts,
                            (f, v) => f.copyWith(lunchAlerts: v), sub: s.alertLunchSub),
                        if (fav.lunchAlerts)
                          SettingTile(
                            icon: Icons.schedule,
                            title: s.lunchTimeAt(fav.lunchAt.format()),
                            subtitle: s.lunchTimeHelp,
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                helpText: s.lunchTimeHelp,
                                initialTime: TimeOfDay(hour: fav.lunchAt.hour, minute: fav.lunchAt.minute),
                              );
                              if (picked == null) return;
                              notifier.update((f) => f.copyWith(lunchAt: TimeOfDayHM(picked.hour, picked.minute)));
                            },
                          ),
                        // Last, so Lunch keeps its time tile beside it.
                        toggle(Icons.notifications_active_outlined, s.alertBus, fav.busAlerts,
                            (f, v) => f.copyWith(busAlerts: v), sub: s.alertBusSub),
                      ],
                    ),
                    Center(
                      child: TextButton.icon(
                        style: _linkStyle(DL.goText(context)),
                        icon: const Icon(Icons.notifications_active_outlined, size: 20),
                        label: Text(s.alertExample),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          if (!await showExampleAlerts(s)) {
                            messenger.showSnackBar(SnackBar(content: Text(s.alertExampleOff)));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                SectionTitle(s.extras),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TileGrid(
                      children: [
                        toggle(Icons.access_time, s.showPrayer, fav.showPrayer, (f, v) => f.copyWith(showPrayer: v),
                            sub: s.showPrayerSub),
                        toggle(Icons.restaurant_menu, s.showHalal, fav.showHalal, (f, v) => f.copyWith(showHalal: v),
                            sub: s.showHalalSub),
                      ],
                    ),
                    // Three switches would leave a hole in the grid, so the last two take the
                    // whole width; the electric car one holds its own plug choice.
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: toggle(Icons.insights, s.learnHabits, fav.learnHabits, (f, v) => f.copyWith(learnHabits: v),
                          sub: s.learnHabitsSub),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SettingTile(
                        icon: Icons.bolt_outlined,
                        title: s.evToggle,
                        subtitle: s.evToggleSub,
                        value: fav.drivesEv,
                        holdsRow: true,
                        onTap: () => notifier.update((f) => f.copyWith(evPlug: fav.drivesEv ? '' : 'any')),
                        below: fav.drivesEv
                            ? _PlugRow(
                                label: s.evPlugTitle,
                                value: s.evPlugName(fav.evPlug),
                                onTap: () async {
                                  final plug = await showEvPlugPicker(context, s, fav.evPlug);
                                  if (plug != null) notifier.update((f) => f.copyWith(evPlug: plug));
                                },
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                SectionTitle(s.theApp),
                TileGrid(
                  children: [
                    SettingTile(
                      icon: Icons.contrast,
                      title: s.appearance,
                      subtitle: s.appearanceName(fav.theme),
                      onTap: () async {
                        final theme = await showAppearancePicker(context, s, fav.theme);
                        if (theme != null) notifier.update((f) => f.copyWith(theme: theme));
                      },
                    ),
                    SettingTile(
                      icon: Icons.info_outline,
                      title: s.about,
                      subtitle: s.aboutSubWith(appVersion),
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutDailyLahPage())),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A text link under a grid of tiles ("Show me an example"): 48 dp tall.
ButtonStyle _linkStyle(Color color) => TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension),
    );

/// Tiles side by side on More: two columns, one when a tile would be too narrow for whole words
/// at this width and text size (`tileColumns`). Tiles in a row are the same width and height.
/// With [wideMinWidth], all tiles share one row when each would be at least that wide (times
/// the text scale): the totals of History on a foldable or tablet.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.wideMinWidth, this.minTileWidth = tileMinWidth});
  final List<Widget> children;
  final double? wideMinWidth;

  /// The narrowest a tile may be at 100% text before the grid goes to one column.
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, box) {
      final n = children.length;
      final oneRow = wideMinWidth != null && n > 2 && (box.maxWidth - _tileGap * (n - 1)) / n >= wideMinWidth! * scale;
      final cols = oneRow ? n : tileColumns(box.maxWidth, scale, minTileWidth);
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i += cols)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = i; j < i + cols; j++) ...[
                        if (j > i) const SizedBox(width: _tileGap),
                        Expanded(child: j < children.length ? children[j] : const SizedBox()),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

const _tileGap = 12.0;

/// The narrowest a tile may be at 100% text for its longest words ("disruption", "Appearance")
/// to stay whole; it grows with the text size.
const tileMinWidth = 120.0;

/// Columns of a [TileGrid] that is [width] wide at this text scale: two while each tile keeps
/// [tileMinWidth] times the scale, else one. So a 360 dp phone has two up to 130% text, a 320 dp
/// phone up to 110%, and 200% text is always one.
int tileColumns(double width, double textScale, [double minWidth = tileMinWidth]) =>
    (width - _tileGap) / 2 >= minWidth * textScale ? 2 : 1;

/// One setting on More as a sticker tile. With [value] it is a switch: mint with a solid outline
/// when on, a dashed outline when off, flat either way, and "On" / "Off" in words so colour is
/// not the only sign. Without [value] it opens something: raised, with a chevron. So here, as
/// on the other tabs, a shadow means the tile opens something. [below] is a row of its own inside
/// the same outline, under a line (the plug of "My car is electric"), with its own tap.
class SettingTile extends ConsumerWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
    this.below,
    this.holdsRow = false,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool? value;
  final VoidCallback onTap;
  final Widget? below;

  /// True for a tile that can have a [below] row, whether it has one now or not: its tree then
  /// keeps one shape, so switching the row in or out keeps the ripple, the colour change and
  /// TalkBack's focus on the tile.
  final bool holdsRow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final isSwitch = value != null;
    final off = value == false;
    final r = BorderRadius.circular(DL.radius);
    // Mint is a sticker surface: ink text in light and dark. An off tile sits on the page.
    final Color? fg = !isSwitch ? null : (off ? DL.muted(context) : DL.ink);
    final Color subColor = isSwitch && !off ? DL.ink : DL.muted(context);
    final still = MediaQuery.disableAnimationsOf(context);

    final badge = ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: off ? null : DL.teal,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: off ? DL.muted(context) : DL.ink, width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!off) const Padding(padding: EdgeInsets.only(right: 3), child: Icon(Icons.check, size: 13, color: DL.ink)),
            Text(off ? s.tileOff : s.tileOn,
                style: t.labelSmall?.copyWith(color: off ? DL.muted(context) : DL.ink, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
    final lead = isSwitch
        ? Icon(icon, size: 24, color: fg)
        : Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: DL.sky,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DL.edge(context), width: 2),
            ),
            child: Icon(icon, size: 20, color: DL.ink),
          );

    final tap = InkWell(
      borderRadius: below == null ? r : const BorderRadius.vertical(top: Radius.circular(DL.radius)),
      onTap: () {
        if (isSwitch) HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 108),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  lead,
                  const Spacer(),
                  if (isSwitch) badge else Icon(Icons.chevron_right, color: DL.muted(context)),
                ],
              ),
              const SizedBox(height: 10),
              Text(title, style: t.titleSmall?.copyWith(color: fg)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: t.bodySmall?.copyWith(color: subColor)),
              ],
            ],
          ),
        ),
      ),
    );
    // One node for TalkBack: a link tile is a button, a switch tile is announced as a switch.
    Widget node(Widget child) => MergeSemantics(
          child: Semantics(toggled: value, button: value == null ? true : null, child: child),
        );
    Widget sticker(Widget child) => Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: CustomPaint(
            foregroundPainter: off ? _DashedOutline(DL.muted(context)) : null,
            child: AnimatedContainer(
              duration: still ? Duration.zero : const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: off
                    ? Colors.transparent
                    : (isSwitch ? DL.mint : Theme.of(context).colorScheme.surfaceContainerLowest),
                borderRadius: r,
                border: Border.all(color: off ? Colors.transparent : DL.edge(context), width: DL.stroke),
                boxShadow: isSwitch ? const [] : DL.hard(context),
              ),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        );

    // With a row below, the tile and that row are two things to TalkBack inside one outline.
    return !holdsRow && below == null
        ? node(sticker(tap))
        : sticker(Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [node(tap), if (below != null) below!],
          ));
  }
}

/// The plug choice inside the "My car is electric" tile: a line, then "Charger plug · Any plug"
/// and a chevron, 48 dp tall. It sits on mint, so its text is ink in light and dark.
class _PlugRow extends StatelessWidget {
  const _PlugRow({required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 12), color: DL.ink.withValues(alpha: 0.25)),
        Semantics(
          container: true,
          button: true,
          child: InkWell(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(DL.radius - DL.stroke)),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinInteractiveDimension),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.power_outlined, size: 22, color: DL.ink),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: label,
                          style: t.titleSmall?.copyWith(color: DL.ink),
                          children: [TextSpan(text: ' · $value', style: t.bodyMedium?.copyWith(color: DL.ink))],
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: DL.ink),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The dashed outline of a switched-off [SettingTile].
class _DashedOutline extends CustomPainter {
  const _DashedOutline(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(DL.stroke / 2), const Radius.circular(DL.radius - DL.stroke / 2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = DL.stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    for (final m in (Path()..addRRect(box)).computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 11) {
        canvas.drawPath(m.extractPath(d, min(d + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) => old.color != color;
}

/// Family share: the sender picks what goes in the code (QR or text); the receiver picks
/// what to take, and places they already saved are only replaced when they tick them.
/// Nothing goes through a server.
class FamilySharePage extends ConsumerStatefulWidget {
  const FamilySharePage({super.key});

  @override
  ConsumerState<FamilySharePage> createState() => _FamilySharePageState();
}

class _FamilySharePageState extends ConsumerState<FamilySharePage> {
  final _ctrl = TextEditingController();
  ShareChoice _choice = const ShareChoice();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final s = ref.read(stringsProvider);
    final messenger = ScaffoldMessenger.of(context);
    final imp = readShareCode(_ctrl.text);
    if (imp == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.importInvalid)));
      return;
    }
    final current = ref.read(favoritesProvider);
    final conflicts = shareConflicts(imp, current);
    final picked = await showModalBottomSheet<(Set<PlaceKind>, bool, bool)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ImportSheet(imp: imp, conflicts: conflicts),
    );
    if (picked == null) return;
    final (take, lines, hawkers) = picked;
    await ref
        .read(favoritesProvider.notifier)
        .update((f) => applyShare(f, imp, take: take, lines: lines, hawkers: hawkers));
    _ctrl.clear();
    messenger.showSnackBar(SnackBar(content: Text(s.importDone)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final t = Theme.of(context).textTheme;
    final kinds = [for (final k in const [PlaceKind.home, PlaceKind.school, PlaceKind.work]) if (fav.places.containsKey(k)) k];
    final choice = _choice.copyWith(places: _choice.places.where(kinds.contains).toSet());
    final empty = choice.places.isEmpty && !choice.lines && !(choice.hawkers && fav.hawkers.isNotEmpty);
    final code = !fav.isSetUp || empty ? null : encodeShareCode(fav, choice);
    return Scaffold(
      appBar: AppBar(title: Text(s.familyShare)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.familyShareIntro, style: t.bodyMedium),
          const SizedBox(height: 16),
          if (!fav.isSetUp)
            Panel(child: EmptyNote(s.pickHomeFirst))
          else ...[
            Text(s.shareInclude, style: t.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in kinds)
                  FilterChip(
                    label: Text(s.placeLabel(k.name)),
                    selected: choice.places.contains(k),
                    onSelected: (on) => setState(() => _choice = _choice.copyWith(
                          places: on ? {..._choice.places, k} : ({..._choice.places}..remove(k)),
                        )),
                  ),
                FilterChip(
                  label: Text(s.shareLinesTimes),
                  selected: choice.lines,
                  onSelected: (on) => setState(() => _choice = _choice.copyWith(lines: on)),
                ),
                if (fav.hawkers.isNotEmpty)
                  FilterChip(
                    label: Text(s.shareHawkers),
                    selected: choice.hawkers,
                    onSelected: (on) => setState(() => _choice = _choice.copyWith(hawkers: on)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (code == null)
              Panel(child: EmptyNote(s.shareNothing))
            else
              Panel(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                        child: QrImageView(
                          data: code,
                          size: 220,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: DL.ink),
                          dataModuleStyle:
                              const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: DL.ink),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                              icon: const Icon(Icons.copy),
                              label: Text(s.copyCode),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: code));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.codeCopied)));
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                              icon: const Icon(Icons.share),
                              label: Text(s.shareCode),
                              onPressed: () => SharePlus.instance.share(ShareParams(text: code, subject: 'DailyLah')),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
          SectionTitle(s.importCode),
          TextField(
            controller: _ctrl,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(hintText: s.pasteCode),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: _import, child: Text(s.importCode)),
        ],
      ),
    );
  }
}

/// Lets the receiver tick what to take from a code. New places are ticked; places that
/// would replace one they saved are not, and say so.
class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet({required this.imp, required this.conflicts});
  final ShareImport imp;
  final Set<PlaceKind> conflicts;

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  late final Set<PlaceKind> _take = widget.imp.places.keys.where((k) => !widget.conflicts.contains(k)).toSet();
  late bool _lines = widget.imp.lines != null;
  late bool _hawkers = widget.imp.hawkers.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final imp = widget.imp;
    final nothing = _take.isEmpty && !_lines && !_hawkers;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(s.importWhat, style: t.titleMedium),
          ),
          for (final e in imp.places.entries)
            CheckboxListTile(
              value: _take.contains(e.key),
              onChanged: (on) => setState(() => on == true ? _take.add(e.key) : _take.remove(e.key)),
              title: Text(s.placeLabel(e.key.name)),
              subtitle: Text([
                if (e.value.address case final a? when a.isNotEmpty) a,
                if (widget.conflicts.contains(e.key)) s.replacesYours(s.placeLabel(e.key.name).toLowerCase()),
              ].join(' · ')),
            ),
          if (imp.lines != null)
            CheckboxListTile(
              value: _lines,
              onChanged: (on) => setState(() => _lines = on ?? false),
              title: Text(s.shareLinesTimes),
              subtitle: imp.lines!.isEmpty ? null : Text(imp.lines!.map(s.lineName).join(', ')),
            ),
          if (imp.hawkers.isNotEmpty)
            CheckboxListTile(
              value: _hawkers,
              onChanged: (on) => setState(() => _hawkers = on ?? false),
              title: Text(s.shareHawkers),
              subtitle: Text(s.hawkersCount(imp.hawkers.length)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: nothing ? null : () => Navigator.of(context).pop((_take, _lines, _hawkers)),
              child: Text(s.importSelected),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lists every plug in [evPlugChoices], one row each with a short hint and a tick on the
/// current one, so more plugs can be added without the Extras panel growing.
Future<String?> showEvPlugPicker(BuildContext context, S s, String current) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(s.evPlugAsk, style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final plug in evPlugChoices)
                ListTile(
                  title: Text(s.evPlugName(plug)),
                  subtitle: Text(s.evPlugHint(plug)),
                  trailing: plug == current ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                  selected: plug == current,
                  onTap: () => Navigator.of(context).pop(plug),
                ),
            ],
          ),
        ),
      ),
    );

/// Light, dark or follow the phone. Returns the picked Favorites.theme, or null.
Future<String?> showAppearancePicker(BuildContext context, S s, String current) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(s.appearanceAsk, style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final theme in appearanceChoices)
                ListTile(
                  title: Text(s.appearanceName(theme)),
                  subtitle: Text(s.appearanceHint(theme)),
                  trailing: theme == current ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) : null,
                  selected: theme == current,
                  onTap: () => Navigator.of(context).pop(theme),
                ),
            ],
          ),
        ),
      ),
    );
