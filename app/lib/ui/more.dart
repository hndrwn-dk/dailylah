import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

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
                                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.cancel)),
                                FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.delete)),
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
                    subtitle: s.aboutSub,
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

/// Family share: a QR code and a copyable code with places, lines and times.
/// Import works by pasting a code; nothing goes through a server.
class FamilySharePage extends ConsumerStatefulWidget {
  const FamilySharePage({super.key});

  @override
  ConsumerState<FamilySharePage> createState() => _FamilySharePageState();
}

class _FamilySharePageState extends ConsumerState<FamilySharePage> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final s = ref.read(stringsProvider);
    final next = decodeShareCode(_ctrl.text, ref.read(favoritesProvider));
    final messenger = ScaffoldMessenger.of(context);
    if (next == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.importInvalid)));
      return;
    }
    await ref.read(favoritesProvider.notifier).update((_) => next);
    _ctrl.clear();
    messenger.showSnackBar(SnackBar(content: Text(s.importDone)));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final fav = ref.watch(favoritesProvider);
    final t = Theme.of(context).textTheme;
    final code = fav.isSetUp ? encodeShareCode(fav) : null;
    return Scaffold(
      appBar: AppBar(title: Text(s.familyShare)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.familyShareIntro, style: t.bodyMedium),
          const SizedBox(height: 16),
          if (code == null)
            Panel(child: EmptyNote(s.pickHomeFirst))
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
