import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../profile/profile_setup_screen.dart';
import 'approval_queue_screen.dart';
import 'failed_posts_screen.dart';
import 'post_composer_screen.dart';
import '../profile/data/profile_repository.dart';
import '../settings/appearance_settings_screen.dart';
import '../settings/social_accounts_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ProfileRepository().watchProfile(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.data!.exists ||
            snapshot.data!.data()?['profileComplete'] != true) {
          return const ProfileSetupScreen();
        }
        final profile = snapshot.data!.data()!;
        return _HomeContent(profile: profile);
      },
    );
  }
}

class _HomeContent extends StatefulWidget {
  const _HomeContent({required this.profile});
  final Map<String, dynamic> profile;

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          IconButton(
            tooltip: 'Edit Panchayat profile',
            icon: const Icon(Icons.edit_note),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ProfileSetupScreen(initialProfile: widget.profile),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Appearance and themes',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const AppearanceSettingsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Social accounts',
            icon: const Icon(Icons.link),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SocialAccountsScreen()),
            ),
          ),
          IconButton(
            tooltip: strings.signOut,
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _index == 0
          ? _Dashboard(
              profile: widget.profile,
              onCompose: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostComposerScreen(profile: widget.profile),
                ),
              ),
            )
          : _index == 1 ? const ApprovalQueueScreen() : const FailedPostsScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.fact_check_outlined),
            selectedIcon: const Icon(Icons.fact_check),
            label: strings.approvalQueue,
          ),
          const NavigationDestination(
            icon: Icon(Icons.error_outline),
            selectedIcon: Icon(Icons.error),
            label: 'Failed',
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PostComposerScreen(profile: widget.profile),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(strings.createPost),
            )
          : null,
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.profile, required this.onCompose});
  final Map<String, dynamic> profile;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final name = (profile['sarpanchName'] as String?) ?? '';
    final panchayat = (profile['panchayatName'] as String?) ?? '';
    final language = (profile['primaryLanguage'] as String?) ?? 'Hindi';
    final imageUrl = (profile['imageUrl'] as String?) ?? '';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  foregroundImage:
                      imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
                  child: imageUrl.isEmpty
                      ? const Icon(Icons.person, size: 30)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(panchayat),
                      Text(
                        language,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Create a clear, accessible update for your village.',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onCompose,
          icon: const Icon(Icons.auto_awesome),
          label: Text(strings.createPost),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        ),
        const SizedBox(height: 20),
        const Card(
          child: ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Approval before publishing'),
            subtitle: Text(
              'AI drafts are never published automatically. Review and edit every caption before dispatch.',
            ),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.wifi_off_outlined),
            title: Text('Offline-friendly'),
            subtitle: Text(
              'Images are compressed on your phone. Failed submissions are retained in a local retry queue.',
            ),
          ),
        ),
      ],
    );
  }
}
