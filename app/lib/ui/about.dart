import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n.dart';
import '../providers.dart';
import 'widgets.dart';

const privacyUrl = 'https://www.tursinalabs.com/dailylah/privacy';
const termsUrl = 'https://www.tursinalabs.com/dailylah/terms';
const productUrl = 'https://www.tursinalabs.com/products/dailylah';

/// The app's own website (landing page). Legal pages stay on tursinalabs.com.
const siteUrl = 'https://dailylah.sg';
const supportEmail = 'support@tursinalabs.com';

/// Data sources credited on About, and the licence most of the data comes under.
const ltaDataMallUrl = 'https://datamall.lta.gov.sg';
const dataGovUrl = 'https://data.gov.sg';
const muslimSgUrl = 'https://www.muslim.sg';
const osmCopyrightUrl = 'https://www.openstreetmap.org/copyright';
const oneMapUrl = 'https://www.onemap.gov.sg';
const uraUrl = 'https://www.ura.gov.sg';
const sodlUrl = 'https://data.gov.sg/open-data-licence';

/// One credited data source on About: what it is, what it powers in the app and its page.
class DataSource {
  const DataSource({
    required this.key,
    required this.icon,
    required this.url,
    required this.title,
    required this.powers,
    this.chips,
  });

  /// Widget key of the row (`source-lta`...).
  final String key;
  final IconData icon;
  final String url;
  final String Function(S s) title;

  /// What it powers, with the credit its licence asks for.
  final String Function(S s) powers;

  /// Small chips under the text (the agencies behind data.gov.sg).
  final List<String> Function(S s)? chips;
}

/// The rows of About > Data sources, in order.
final dataSources = <DataSource>[
  DataSource(
    key: 'source-lta',
    icon: Icons.directions_bus_outlined,
    url: ltaDataMallUrl,
    title: (s) => s.sourceLta,
    powers: (s) => s.sourceLtaSub,
  ),
  DataSource(
    key: 'source-datagov',
    icon: Icons.account_balance_outlined,
    url: dataGovUrl,
    title: (s) => s.sourceDataGov,
    powers: (s) => s.sourceDataGovSub,
    chips: (s) => s.dataAgencies,
  ),
  DataSource(
    key: 'source-muslimsg',
    icon: Icons.restaurant_outlined,
    url: muslimSgUrl,
    title: (s) => s.sourceMuslimSg,
    powers: (s) => s.sourceMuslimSgSub,
  ),
  DataSource(
    key: 'source-osm',
    icon: Icons.public,
    url: osmCopyrightUrl,
    title: (s) => s.sourceOsm,
    powers: (s) => s.sourceOsmSub,
  ),
  DataSource(
    key: 'source-onemap',
    icon: Icons.map_outlined,
    url: oneMapUrl,
    title: (s) => s.sourceOneMap,
    powers: (s) => s.sourceOneMapSub,
  ),
  DataSource(
    key: 'source-ura',
    icon: Icons.apartment_outlined,
    url: uraUrl,
    title: (s) => s.sourceUra,
    powers: (s) => s.sourceUraSub,
  ),
];

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

/// App version, injected by CI or set manually: --dart-define=APP_VERSION=2.0.0
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '2.0.0');

/// Short commit the APK was built from: --dart-define=GIT_SHA=$(git rev-parse --short HEAD).
/// Empty for builds that skip it (flutter run).
const appCommit = String.fromEnvironment('GIT_SHA');

/// Build number (Android versionCode), injected by CI: --dart-define=BUILD_NUMBER=123.
const appBuild = String.fromEnvironment('BUILD_NUMBER');

/// Version as shown on About, More and the licence page, e.g. "2.0.0 (build 123 · a8d2bba)".
String get appVersionLabel {
  final extra = [if (appBuild.isNotEmpty) 'build $appBuild', if (appCommit.isNotEmpty) appCommit];
  return extra.isEmpty ? appVersion : '$appVersion (${extra.join(' · ')})';
}

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
    // Read out with the row, so a screen reader says the row leaves the app.
    final external = Icon(Icons.open_in_new, size: 18, semanticLabel: s.opensWebsite);
    return Scaffold(
      appBar: AppBar(title: Text(s.about)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('DailyLah', style: t.displayMedium),
          Text('Tursina Labs', style: t.bodySmall),
          const SizedBox(height: 12),
          Text(s.aboutIntro, style: t.bodyLarge),
          const SizedBox(height: 16),
          // Version first and easy to copy, for bug reports.
          Panel(
            child: ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(s.versionTitle),
              subtitle: Text(appVersionLabel, style: t.titleMedium),
              trailing: IconButton(
                tooltip: s.copyVersion,
                icon: const Icon(Icons.copy, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: 'DailyLah $appVersionLabel'));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.versionCopied)));
                  }
                },
              ),
            ),
          ),
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
                  onTap: () => SharePlus.instance.share(ShareParams(text: s.shareAppText(playWebUrl), subject: 'DailyLah')),
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
          Panel(
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                for (final d in dataSources)
                  ListTile(
                    key: ValueKey(d.key),
                    leading: Icon(d.icon),
                    title: Text(d.title(s)),
                    subtitle: d.chips == null
                        ? Text(d.powers(s))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.powers(s)),
                              const SizedBox(height: 6),
                              InfoChips(d.chips!(s)),
                              const SizedBox(height: 4),
                            ],
                          ),
                    trailing: external,
                    onTap: () => open(d.url),
                  ),
              ],
            ),
          ),
          // The statement the Singapore Open Data Licence asks for stays in full under the card.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(s.dataAttribution, style: t.bodySmall),
          ),
          AlertBanner(
            key: const ValueKey('estimates-note'),
            icon: Icons.info_outline,
            text: s.estimatesNote,
            tone: AlertTone.info,
          ),
          const SizedBox(height: 4),
          Panel(
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                ListTile(
                  key: const ValueKey('licence-sodl'),
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(s.openDataLicence),
                  trailing: external,
                  onTap: () => open(sodlUrl),
                ),
                ListTile(
                  key: const ValueKey('licence-oss'),
                  leading: const Icon(Icons.code),
                  title: Text(s.openSourceLicences),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'DailyLah',
                    applicationVersion: appVersionLabel,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(s.independent, style: t.bodySmall),
          ),
        ],
      ),
    );
  }
}
