import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const privacyUrl = 'https://www.tursinalabs.com/dailylah/privacy';
const termsUrl = 'https://www.tursinalabs.com/dailylah/terms';
const productUrl = 'https://www.tursinalabs.com/products/dailylah';
const supportEmail = 'support@tursinalabs.com';

/// App version, injected by CI or set manually: --dart-define=APP_VERSION=0.1.0
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');

/// Privacy, terms, data attribution (required by the Singapore Open Data Licence)
/// and contact.
class AboutDailyLahPage extends StatelessWidget {
  const AboutDailyLahPage({super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tidak bisa membuka ${uri.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang DailyLah')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('DailyLah', style: text.headlineSmall),
          Text('Versi $appVersion · Tursina Labs', style: text.bodySmall),
          const SizedBox(height: 8),
          const Text(
            'Teman harian untuk perjalanan di Singapura. Tanpa akun, tanpa iklan. '
            'Tempat dan pengaturanmu hanya tersimpan di HP ini.',
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Kebijakan privasi'),
            onTap: () => _open(context, Uri.parse(privacyUrl)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Ketentuan layanan'),
            onTap: () => _open(context, Uri.parse(termsUrl)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.mail_outline),
            title: const Text('Hubungi kami'),
            subtitle: const Text(supportEmail),
            onTap: () => _open(
              context,
              Uri(scheme: 'mailto', path: supportEmail, query: 'subject=DailyLah'),
            ),
          ),
          const Divider(height: 32),
          Text('Sumber data', style: text.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Berisi informasi dari LTA DataMall dan dari dataset NEA yang diakses melalui '
            'data.gov.sg, tersedia berdasarkan Singapore Open Data Licence. '
            'Jadwal bus, kepadatan, dan prakiraan cuaca adalah perkiraan.',
          ),
          const SizedBox(height: 8),
          const Text(
            'DailyLah adalah aplikasi independen dan tidak berafiliasi dengan LTA, NEA, '
            'atau pemerintah Singapura.',
          ),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => _open(context, Uri.parse('https://data.gov.sg/open-data-licence')),
            child: const Text('Singapore Open Data Licence'),
          ),
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'DailyLah',
              applicationVersion: appVersion,
            ),
            child: const Text('Lisensi open-source'),
          ),
        ],
      ),
    );
  }
}
