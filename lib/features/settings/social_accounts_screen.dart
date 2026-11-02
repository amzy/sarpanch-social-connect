import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/backend_api_service.dart';

class SocialAccountsScreen extends StatefulWidget {
  const SocialAccountsScreen({super.key});
  @override
  State<SocialAccountsScreen> createState() => _SocialAccountsScreenState();
}

class _SocialAccountsScreenState extends State<SocialAccountsScreen> {
  static const platforms = <_Platform>[
    _Platform('facebook', 'Facebook Page', 'Create the official public Panchayat Page.', 'https://www.facebook.com/pages/create/'),
    _Platform('instagram', 'Instagram', 'Create a Professional Business account.', 'https://www.instagram.com/accounts/emailsignup/'),
    _Platform('whatsappBusiness', 'WhatsApp Business', 'Create the official Panchayat contact profile.', 'https://www.whatsapp.com/business/'),
    _Platform('whatsappChannel', 'WhatsApp Channel', 'Create a public channel for Panchayat announcements.', 'https://whatsapp.com/channel/'),
    _Platform('youtube', 'YouTube', 'Create the official Panchayat video channel.', 'https://www.youtube.com/create_channel'),
    _Platform('x', 'X', 'Create the official public information profile.', 'https://x.com/i/flow/signup'),
  ];
  final handles = <String, TextEditingController>{};
  final urls = <String, TextEditingController>{};
  final statuses = <String, String>{};
  bool loading = true, saving = false;
  String? message, error;

  @override
  void initState() {
    super.initState();
    for (final p in platforms) {
      handles[p.id] = TextEditingController(text: '@PanchayatSarpanch');
      urls[p.id] = TextEditingController();
      statuses[p.id] = 'not_started';
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await BackendApiService().getSocialSetup();
      final profiles = data['profiles'];
      if (profiles is Map) {
        for (final p in platforms) {
          final item = profiles[p.id];
          if (item is Map) {
            handles[p.id]!.text = item['handle']?.toString() ?? '@PanchayatSarpanch';
            urls[p.id]!.text = item['profileUrl']?.toString() ?? '';
            final status = item['status']?.toString() ?? 'not_started';
            statuses[p.id] = ['not_started', 'created', 'connected', 'manual_only'].contains(status) ? status : 'not_started';
          }
        }
      }
    } catch (e) { error = e.toString(); }
    finally { if (mounted) setState(() => loading = false); }
  }

  @override
  void dispose() {
    for (final c in handles.values) { c.dispose(); }
    for (final c in urls.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() { saving = true; message = null; error = null; });
    try {
      final profiles = <String, dynamic>{};
      for (final p in platforms) {
        profiles[p.id] = {'handle': handles[p.id]!.text.trim(), 'profileUrl': urls[p.id]!.text.trim(), 'status': statuses[p.id]};
      }
      await BackendApiService().saveSocialSetup(profiles);
      if (mounted) setState(() => message = 'Official account setup saved.');
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => saving = false); }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied. Open it in your browser to continue.')));
  }

  @override
  Widget build(BuildContext context) {
    final completed = statuses.values.where((s) => s != 'not_started').length;
    return Scaffold(
      appBar: AppBar(title: const Text('Official social accounts')),
      body: loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Panchayat social identity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Create and manage official public accounts for the Panchayat. Keep ownership under institutional control, not a single office bearer’s personal account.'),
            const SizedBox(height: 12),
            Text('Setup progress: $completed of 6 platforms', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: completed / 6),
            const SizedBox(height: 12),
            const Text('Suggested identity: Panchayat Sarpanch\nSuggested handle: @PanchayatSarpanch', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Check username availability on each platform. This app cannot reserve usernames or create third-party accounts automatically.', style: TextStyle(fontSize: 12)),
          ]))),
          const SizedBox(height: 8),
          for (final p in platforms) _platformCard(p),
          if (message != null) Padding(padding: const EdgeInsets.all(8), child: Text(message!, style: TextStyle(color: Theme.of(context).colorScheme.primary))),
          if (error != null) Padding(padding: const EdgeInsets.all(8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton.icon(onPressed: saving ? null : _save, icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(saving ? 'Saving…' : 'Save account setup')),
          const SizedBox(height: 20),
          const Text('Connection and publishing', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('OAuth connection requires official developer apps and platform permissions. Never paste passwords or access tokens here. WhatsApp Group and Channel publishing remains a manual admin-confirmed action where official publishing APIs are unavailable.', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _platformCard(_Platform p) {
    final status = statuses[p.id] ?? 'not_started';
    final color = status == 'connected' ? Colors.green : status == 'created' ? Colors.orange : status == 'manual_only' ? Colors.blue : Theme.of(context).colorScheme.outline;
    final label = status == 'connected' ? 'Connected' : status == 'created' ? 'Account created' : status == 'manual_only' ? 'Manual publishing' : 'Not started';
    return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), Chip(visualDensity: VisualDensity.compact, label: Text(label), labelStyle: TextStyle(color: color, fontSize: 11))]),
      Text(p.description, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(controller: handles[p.id], decoration: const InputDecoration(labelText: 'Preferred username / handle', border: OutlineInputBorder(), isDense: true)),
      const SizedBox(height: 10),
      TextField(controller: urls[p.id], keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Official profile URL (after creation)', hintText: 'https://…', border: OutlineInputBorder(), isDense: true)),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: status,
        decoration: const InputDecoration(labelText: 'Account status', border: OutlineInputBorder(), isDense: true),
        items: const [
          DropdownMenuItem(value: 'not_started', child: Text('Not started')),
          DropdownMenuItem(value: 'created', child: Text('Account created')),
          DropdownMenuItem(value: 'connected', child: Text('Connected through official authorization')),
          DropdownMenuItem(value: 'manual_only', child: Text('Manual publishing only')),
        ],
        onChanged: (v) => setState(() => statuses[p.id] = v ?? 'not_started'),
      ),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => _copy(p.signupUrl, '${p.name} signup link'), icon: const Icon(Icons.open_in_new), label: const Text('Copy official signup link'))),
    ])));
  }
}

class _Platform {
  const _Platform(this.id, this.name, this.description, this.signupUrl);
  final String id, name, description, signupUrl;
}
