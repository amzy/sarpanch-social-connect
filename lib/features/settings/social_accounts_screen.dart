import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/backend_api_service.dart';

class SocialAccountsScreen extends StatefulWidget {
  const SocialAccountsScreen({super.key});

  @override
  State<SocialAccountsScreen> createState() => _SocialAccountsScreenState();
}

class _SocialAccountsScreenState extends State<SocialAccountsScreen> {
  bool _loading = true;
  String? _busyProvider;
  String? _message;
  String? _error;
  List<Map<String, dynamic>> _accounts = [];

  static const _providers = <(String, String, IconData, String)>[
    (
      'facebook',
      'Facebook Pages',
      Icons.facebook,
      'Publish to Pages you manage'
    ),
    (
      'instagram',
      'Instagram',
      Icons.camera_alt_outlined,
      'Professional Creator or Business accounts'
    ),
    (
      'threads',
      'Threads',
      Icons.alternate_email,
      'Connect your Threads profile'
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
    final status = Uri.base.queryParameters['social_oauth'];
    final provider = Uri.base.queryParameters['provider'];
    if (status == 'connected') {
      _message = '${provider ?? 'Social'} account connected successfully.';
    } else if (status == 'failed') {
      _error =
          'Account connection was not completed. Check provider permissions and try again.';
    }
  }

  Future<void> _loadAccounts() async {
    setState(() => _loading = true);
    try {
      final accounts = await BackendApiService().socialAccounts();
      if (mounted)
        setState(() {
          _accounts = accounts;
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(String provider) async {
    setState(() {
      _busyProvider = provider;
      _message = null;
      _error = null;
    });
    try {
      final authorizationUrl =
          await BackendApiService().connectSocialAccount(provider);
      final launched = await launchUrl(
        Uri.parse(authorizationUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched)
        throw StateError('Could not open the provider login page.');
      if (mounted) {
        setState(() => _message =
            'Finish authorization in the browser. Return here after the provider redirects you back.');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyProvider = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Social accounts'),
        actions: [
          IconButton(
            tooltip: 'Refresh accounts',
            onPressed: _loading ? null : _loadAccounts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Connect the social accounts managed by this Sarpanch. Each user authorizes their own accounts. Access tokens stay encrypted in the backend and are never shown in the app.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (_loading) const LinearProgressIndicator(),
          ..._providers.map((provider) {
            final connected = _accounts
                .where(
                  (account) => account['provider'] == provider.$1,
                )
                .toList();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(provider.$3, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(provider.$2,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(provider.$4,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        if (connected.isNotEmpty)
                          Chip(
                            avatar: const Icon(Icons.check_circle, size: 16),
                            label: Text('${connected.length} connected'),
                          )
                        else
                          const Chip(label: Text('Not connected')),
                      ],
                    ),
                    if (connected.isNotEmpty) ...[
                      const Divider(height: 22),
                      ...connected.map((account) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.account_circle_outlined),
                            title:
                                Text(account['name']?.toString() ?? 'Account'),
                            subtitle: Text('ID: ${account['id'] ?? ''}'),
                          )),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: _busyProvider == provider.$1
                            ? null
                            : () => _connect(provider.$1),
                        icon: _busyProvider == provider.$1
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.link),
                        label: Text(connected.isEmpty
                            ? 'Connect account'
                            : 'Connect another'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('WhatsApp Groups and Channels'),
              subtitle: const Text(
                'Use manual sharing from the post approval screen. Official APIs do not provide general publishing to arbitrary existing groups or channels.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_message != null)
            Text(_message!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          if (_error != null)
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _loadAccounts,
            icon: const Icon(Icons.sync),
            label: const Text('Refresh connected accounts'),
          ),
        ],
      ),
    );
  }
}
