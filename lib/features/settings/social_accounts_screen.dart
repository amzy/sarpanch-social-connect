import 'package:flutter/material.dart';

import '../../services/backend_api_service.dart';

class SocialAccountsScreen extends StatefulWidget {
  const SocialAccountsScreen({super.key});

  @override
  State<SocialAccountsScreen> createState() => _SocialAccountsScreenState();
}

class _SocialAccountsScreenState extends State<SocialAccountsScreen> {
  final _facebookPageId = TextEditingController();
  final _facebookToken = TextEditingController();
  final _instagramId = TextEditingController();
  final _xToken = TextEditingController();
  bool _saving = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _facebookPageId.dispose();
    _facebookToken.dispose();
    _instagramId.dispose();
    _xToken.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final values = <String, String>{
      if (_facebookPageId.text.trim().isNotEmpty)
        'facebookPageId': _facebookPageId.text.trim(),
      if (_facebookToken.text.trim().isNotEmpty)
        'facebookPageToken': _facebookToken.text.trim(),
      if (_instagramId.text.trim().isNotEmpty)
        'instagramId': _instagramId.text.trim(),
      if (_xToken.text.trim().isNotEmpty)
        'twitterToken': _xToken.text.trim(),
    };
    if (values.isEmpty) {
      setState(() => _error = 'Enter at least one account value to save.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
      _error = null;
    });
    try {
      await BackendApiService().saveSocialCredentials(values);
      _facebookToken.clear();
      _xToken.clear();
      if (mounted) setState(() => _message = 'Credentials saved securely.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Social accounts')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Add the credentials for the social accounts managed by this Panchayat. Access tokens are sent over HTTPS and encrypted by the backend before storage.',
          ),
          const SizedBox(height: 8),
          const Text(
            'For security, saved tokens are never displayed again. Leave a field blank to keep its existing value.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _facebookPageId,
            decoration: const InputDecoration(
              labelText: 'Facebook Page ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _facebookToken,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Facebook Page access token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instagramId,
            decoration: const InputDecoration(
              labelText: 'Instagram professional account ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _xToken,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'X user access token',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          if (_message != null)
            Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_outline),
            label: Text(_saving ? 'Saving…' : 'Save credentials securely'),
          ),
        ],
      ),
    );
  }
}
