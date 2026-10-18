import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <(String, String)>[
    (
        'Data handled by the app',
        'RCD Sales handles your sign-in details, the ERP server you choose, and '
          'authorized business data such as customers, orders, invoices, and '
          'collections. Session tokens are stored securely on your device. A '
          'local copy of data needed for offline work may also be stored.',
    ),
    (
        'Location, photos, and calendar',
        'Location is requested only for actions that need proof of location, '
          'such as logging a visit or creating a field document. The camera '
          'and photos are used only when you choose to attach an image. The '
          'calendar is used only when you add a due-date reminder. The app '
          'does not track your location in the background.',
    ),
    (
        'Notifications',
        'The app uses Firebase Cloud Messaging to deliver work notifications. '
          'A device-specific notification token may be sent to the ERP server '
          'linked to your account to enable this service.',
    ),
    (
        'Data sharing and retention',
        'Business data is sent to the ERP server you sign in to and to Google '
          'services required to deliver notifications. The app does not sell '
          'your data. Session data and account-related local copies are '
          'removed from the device when you sign out.',
    ),
    (
        'Control your data',
        'You can revoke location, camera, calendar, and notification permissions '
          'in Android settings. Your employer manages user accounts on the ERP '
          'server. Contact your organization’s system administrator to request '
          'correction or deletion of your account data.',
    ),
    (
        'Contact',
        'For privacy questions, contact Red Tech For Technology or your '
          'organization’s ERP administrator. Last updated: October 9, 2026.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGray,
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final section in _sections)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    section.$1,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    section.$2,
                    style: const TextStyle(
                      height: 1.7,
                      color: AppColors.midGray,
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
