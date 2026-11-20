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
        padding: const EdgeInsets.only(bottom: kNavClearance),
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
                      ],
                    ),
                    // Lunch has a time to set, so it stays a full-width row with its switch.
                    Panel(
                      child: Column(
                        children: [
                          SwitchListTile(
                            secondary: const Icon(Icons.ramen_dining_outlined),
                            title: Text(s.alertLunch, style: t.bodyMedium),
                            subtitle: Text(s.alertLunchSub),
                            value: fav.lunchAlerts,
                            onChanged: (v) => notifier.update((f) => f.copyWith(lunchAlerts: v)),
                          ),
                          if (fav.lunchAlerts)
                            ListTile(
                              leading: const Icon(Icons.schedule),
                              title: Text(s.lunchTimeAt(fav.lunchAt.format()), style: t.bodyMedium),
                              trailing: const Icon(Icons.chevron_right),
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
                        ],
                      ),
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
                        toggle(Icons.bolt_outlined, s.evToggle, fav.drivesEv,
                            (f, v) => f.copyWith(evPlug: v ? 'any' : ''), sub: s.evToggleSub),
                        toggle(Icons.insights, s.learnHabits, fav.learnHabits, (f, v) => f.copyWith(learnHabits: v),
                            sub: s.learnHabitsSub),
                      ],
                    ),
                    if (fav.drivesEv)
                      Panel(
                        child: ListTile(
                          leading: const Icon(Icons.power_outlined),
                          title: Text(s.evPlugTitle),
                          subtitle: Text(s.evPlugName(fav.evPlug)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final plug = await showEvPlugPicker(context, s, fav.evPlug);
                            if (plug != null) notifier.update((f) => f.copyWith(evPlug: plug));
                          },
                        ),
                      ),
                    Center(
                      child: TextButton.icon(
                        style: _linkStyle(DL.stopText(context)),
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: Text(s.deleteHistory),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              content: Text(s.deleteHistoryAsk),
                              actions: [
                                DialogButtons(
                                  cancelLabel: s.cancel,
                                  confirmLabel: s.delete,
                                  onCancel: () => Navigator.of(ctx).pop(false),
                                  onConfirm: () => Navigator.of(ctx).pop(true),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          await ref.read(habitsProvider.notifier).clearAll();
                          messenger.showSnackBar(SnackBar(content: Text(s.deleted)));
                        },
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

/// A text link under a grid of tiles ("Show me an example", "Delete my history"): 48 dp tall.
ButtonStyle _linkStyle(Color color) => TextButton.styleFrom(
      foregroundColor: color,
      minimumSize: const Size(kMinInteractiveDimension, kMinInteractiveDimension),
    );

/// Tiles side by side on More: two columns, one when a tile would be too narrow for whole words
/// at this width and text size (`tileColumns`). Tiles in a row are the same width and height.
/// With [wideMinWidth], all tiles share one row when each would be at least that wide (times
/// the text scale): the totals of History on a foldable or tablet.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.wideMinWidth});
  final List<Widget> children;
  final double? wideMinWidth;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(builder: (context, box) {
      final n = children.length;
      final oneRow = wideMinWidth != null && n > 2 && (box.maxWidth - _tileGap * (n - 1)) / n >= wideMinWidth! * scale;
      final cols = oneRow ? n : tileColumns(box.maxWidth, scale);
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
int tileColumns(double width, double textScale) =>
    (width - _tileGap) / 2 >= tileMinWidth * textScale ? 2 : 1;

/// One setting on More as a sticker tile. With [value] it is a switch: raised and mint when on,
/// flat with a dashed outline when off, and "On" / "Off" in words so colour is not the only
/// sign. Without [value] it opens something and shows a chevron.
class SettingTile extends ConsumerWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool? value;
  final VoidCallback onTap;

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

    return MergeSemantics(
      child: Semantics(
        toggled: value,
        // A link tile is a button to TalkBack; a switch tile is announced as a switch.
        button: value == null ? true : null,
        child: Padding(
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
                boxShadow: off ? const [] : DL.hard(context),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: r,
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
                ),
              ),
            ),
          ),
        ),
      ),
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
