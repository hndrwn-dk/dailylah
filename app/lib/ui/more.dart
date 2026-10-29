import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

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

    Widget toggle(String title, bool value, Favorites Function(Favorites, bool) set, {String? sub}) =>
        SwitchListTile(
          title: Text(title, style: t.bodyMedium),
          subtitle: sub == null ? null : Text(sub),
          value: value,
          onChanged: (v) => notifier.update((f) => set(f, v)),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(s.yourSetup),
                Panel(
                  child: Column(
                    children: [
                      _NavTile(
                        icon: Icons.tune,
                        title: s.editSetup,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SetupPage())),
                      ),
                      _NavTile(
                        icon: Icons.qr_code_2,
                        title: s.familyShare,
                        subtitle: s.familyShareSub,
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FamilySharePage())),
                      ),
                    ],
                  ),
                ),
                SectionTitle(s.alertsTitle),
                Panel(
                  child: Column(
                    children: [
                      toggle(s.alertMrt, fav.mrtAlerts, (f, v) => f.copyWith(mrtAlerts: v)),
                      toggle(s.alertRain, fav.rainAlerts, (f, v) => f.copyWith(rainAlerts: v), sub: s.alertRainSub),
                      toggle(s.alertLeave, fav.leaveAlerts, (f, v) => f.copyWith(leaveAlerts: v), sub: s.alertLeaveSub),
                      toggle(s.alertDigest, fav.digestAlerts, (f, v) => f.copyWith(digestAlerts: v), sub: s.alertDigestSub),
                      toggle(s.alertHawker, fav.hawkerAlerts, (f, v) => f.copyWith(hawkerAlerts: v)),
                      toggle(s.alertDengue, fav.dengueAlerts, (f, v) => f.copyWith(dengueAlerts: v)),
                      toggle(s.alertHeat, fav.heatAlerts, (f, v) => f.copyWith(heatAlerts: v)),
                      toggle(s.alertHomes, fav.homesAlerts, (f, v) => f.copyWith(homesAlerts: v)),
                    ],
                  ),
                ),
                SectionTitle(s.extras),
                Panel(
                  child: Column(
                    children: [
                      toggle(s.showPrayer, fav.showPrayer, (f, v) => f.copyWith(showPrayer: v), sub: s.showPrayerSub),
                      toggle(s.showHalal, fav.showHalal, (f, v) => f.copyWith(showHalal: v), sub: s.showHalalSub),
                      toggle(s.evToggle, fav.drivesEv, (f, v) => f.copyWith(evPlug: v ? 'any' : ''), sub: s.evToggleSub),
                      if (fav.drivesEv)
                        ListTile(
                          leading: const Icon(Icons.power_outlined),
                          title: Text(s.evPlugTitle),
                          subtitle: Text(s.evPlugName(fav.evPlug)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final plug = await showEvPlugPicker(context, s, fav.evPlug);
                            if (plug != null) notifier.update((f) => f.copyWith(evPlug: plug));
                          },
                        ),
                      toggle(s.learnHabits, fav.learnHabits, (f, v) => f.copyWith(learnHabits: v), sub: s.learnHabitsSub),
                      ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(s.deleteHistory, style: t.bodyMedium),
                        onTap: () async {
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
                    ],
                  ),
                ),
                Panel(
                  child: _NavTile(
                    icon: Icons.info_outline,
                    title: s.about,
                    subtitle: s.aboutSubWith(appVersion),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutDailyLahPage())),
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

class _NavTile extends StatelessWidget {
  const _NavTile({required this.icon, required this.title, this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: c),
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
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
