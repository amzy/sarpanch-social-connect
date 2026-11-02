import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../services/image_upload_service.dart';
import 'data/profile_repository.dart';

const supportedLanguages = [
  'English',
  'Hindi',
  'Marathi',
  'Telugu',
  'Tamil',
  'Gujarati',
];

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.initialProfile});

  final Map<String, dynamic>? initialProfile;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _sarpanch = TextEditingController();
  final _panchayat = TextEditingController();
  final _sarpanchHindi = TextEditingController();
  final _panchayatHindi = TextEditingController();
  final _district = TextEditingController();
  final _state = TextEditingController();
  final _picker = ImagePicker();
  final _uploads = ImageUploadService();
  XFile? _profileImage;
  XFile? _sealImage;
  String _language = 'Hindi';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    if (profile != null) {
      _sarpanch.text = (profile['sarpanchName'] as String?) ?? '';
      _panchayat.text = (profile['panchayatName'] as String?) ?? '';
      _sarpanchHindi.text = (profile['sarpanchNameHindi'] as String?) ?? '';
      _panchayatHindi.text = (profile['panchayatNameHindi'] as String?) ?? '';
      _district.text = (profile['district'] as String?) ?? '';
      _state.text = (profile['state'] as String?) ?? '';
      final language = profile['primaryLanguage'] as String?;
      if (supportedLanguages.contains(language)) _language = language!;
    }
  }

  @override
  void dispose() {
    _sarpanch.dispose();
    _panchayat.dispose();
    _sarpanchHindi.dispose();
    _panchayatHindi.dispose();
    _district.dispose();
    _state.dispose();
    super.dispose();
  }

  Future<XFile?> _pick() =>
      _picker.pickImage(source: ImageSource.gallery, imageQuality: 90);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String imageUrl = '';
      String sealUrl = '';
      if (_profileImage != null) {
        imageUrl = await _uploads.uploadFile(
          uid: user.uid,
          path: 'users/${user.uid}/profile/profile.jpg',
          file: _profileImage!,
        );
      }
      if (_sealImage != null) {
        sealUrl = await _uploads.uploadFile(
          uid: user.uid,
          path: 'users/${user.uid}/profile/seal.jpg',
          file: _sealImage!,
        );
      }
      await ProfileRepository().completeProfile(
        uid: user.uid,
        profile: {
          'sarpanchName': _sarpanch.text.trim(),
          'panchayatName': _panchayat.text.trim(),
          'sarpanchNameHindi': _sarpanchHindi.text.trim(),
          'panchayatNameHindi': _panchayatHindi.text.trim(),
          'district': _district.text.trim(),
          'state': _state.text.trim(),
          'primaryLanguage': _language,
          'imageUrl': imageUrl,
          'sealUrl': sealUrl,
          'profileComplete': true,
        },
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _imagePicker(String title, XFile? file, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        file == null ? Icons.add_a_photo_outlined : Icons.check_circle_outline,
      ),
      label: Text(file == null ? title : '$title selected'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialProfile == null ? strings.profileSetup : 'Edit Panchayat profile')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _sarpanch,
                decoration: InputDecoration(labelText: strings.sarpanchName),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _panchayat,
                decoration: InputDecoration(labelText: strings.panchayatName),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              Text('Names for official Hindi posters', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              const Text('Enter these exactly as they should appear. The app will not transliterate or guess spellings.'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sarpanchHindi,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(labelText: 'Sarpanch name (Hindi)', hintText: 'उदाहरण: उमर फारुख'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _panchayatHindi,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(labelText: 'Gram Panchayat name (Hindi)', hintText: 'उदाहरण: गगवाना'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _district,
                decoration: InputDecoration(labelText: strings.district),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _state,
                decoration: InputDecoration(labelText: strings.state),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: InputDecoration(labelText: strings.language),
                items: supportedLanguages
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _language = value ?? 'Hindi'),
              ),
              const SizedBox(height: 18),
              _imagePicker('Profile picture', _profileImage, () async {
                final file = await _pick();
                if (file != null) setState(() => _profileImage = file);
              }),
              const SizedBox(height: 10),
              _imagePicker('Official Panchayat seal', _sealImage, () async {
                final file = await _pick();
                if (file != null) setState(() => _sealImage = file);
              }),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: _saving
                    ? const CircularProgressIndicator()
                    : Text(strings.saveProfile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
