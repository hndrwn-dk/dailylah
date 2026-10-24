import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers.dart';
import 'widgets.dart';

const privacyUrl = 'https://www.tursinalabs.com/dailylah/privacy';
const termsUrl = 'https://www.tursinalabs.com/dailylah/terms';
const productUrl = 'https://www.tursinalabs.com/products/dailylah';

/// The app's own website (landing page). Legal pages stay on tursinalabs.com.
const siteUrl = 'https://dailylah.sg';
const supportEmail = 'support@tursinalabs.com';

/// Google Play listing. The market:// link opens the Play Store app; the web link is the fallback.
const playPackage = 'com.tursinalabs.dailylah';
const playMarketUrl = 'market://details?id=$playPackage';
const playWebUrl = 'https://play.google.com/store/apps/details?id=$playPackage';

/// Opens the Play Store listing to rate the app (Play app first, then the browser).
Future<void> openPlayListing(BuildContext context, String failText) async {
  if (await launchUrl(Uri.parse(playMarketUrl), mode: LaunchMode.externalApplication)) return;
  if (!context.mounted) return;
  await openExternal(context, Uri.parse(playWebUrl), failText);
}

/// App version, injected by CI or set manually: --dart-define=APP_VERSION=0.2.0
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.2.0');

Future<void> openExternal(BuildContext context, Uri uri, String failText) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failText)));
  }
}

/// Privacy, terms, data attribution (required by the Singapore Open Data Licence)
/// and contact.
class AboutDailyLahPage extends ConsumerWidget {
  const AboutDailyLahPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    void open(String url) => openExternal(context, Uri.parse(url), s.cannotOpen(url));
    return Scaffold(
      appBar: AppBar(title: Text(s.about)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('DailyLah', style: t.displayMedium),
          Text(s.version(appVersion), style: t.bodySmall),
          const SizedBox(height: 12),
          Text(s.aboutIntro, style: t.bodyLarge),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(s.website),
                  subtitle: const Text('dailylah.sg'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => open(siteUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: Text(s.shareApp),
                  subtitle: Text(s.shareAppSub),
                  onTap: () => SharePlus.instance.share(ShareParams(text: s.shareAppText, subject: 'DailyLah')),
                ),
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: Text(s.rateApp),
                  subtitle: Text(s.rateAppSub),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => openPlayListing(context, s.cannotOpen('Google Play')),
                ),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(s.privacyPolicy),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => open(privacyUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(s.termsOfService),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => open(termsUrl),
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: Text(s.contactUs),
                  subtitle: const Text(supportEmail),
                  onTap: () => openExternal(
                    context,
                    Uri(scheme: 'mailto', path: supportEmail, query: 'subject=DailyLah'),
                    s.cannotOpen(supportEmail),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(s.dataSources),
          Text(s.dataAttribution, style: t.bodyMedium),
          const SizedBox(height: 8),
          Text(s.independent, style: t.bodyMedium),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => open('https://data.gov.sg/open-data-licence'),
            child: const Text('Singapore Open Data Licence'),
          ),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'DailyLah',
              applicationVersion: appVersion,
            ),
            child: Text(s.openSourceLicences),
          ),
        ],
      ),
    );
  }
}
