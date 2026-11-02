import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

class _DialingCountry {
  const _DialingCountry({
    required this.name,
    required this.isoCode,
    required this.dialCode,
    this.flag = '',
  });

  final String name;
  final String isoCode;
  final String dialCode;
  final String flag;

  @override
  String toString() => '$flag $name (+$dialCode)';
}

const _supportedCountries = <_DialingCountry>[
  _DialingCountry(name: 'India', isoCode: 'IN', dialCode: '91', flag: '🇮🇳'),
  _DialingCountry(name: 'United States', isoCode: 'US', dialCode: '1', flag: '🇺🇸'),
  _DialingCountry(name: 'United Kingdom', isoCode: 'GB', dialCode: '44', flag: '🇬🇧'),
  _DialingCountry(name: 'United Arab Emirates', isoCode: 'AE', dialCode: '971', flag: '🇦🇪'),
  _DialingCountry(name: 'Canada', isoCode: 'CA', dialCode: '1', flag: '🇨🇦'),
  _DialingCountry(name: 'Australia', isoCode: 'AU', dialCode: '61', flag: '🇦🇺'),
];

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  _DialingCountry _country = _supportedCountries.first;
  String? _verificationId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _bootstrapDevelopmentAdmin() async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('bootstrapDevelopmentAdmin');
      await callable.call();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } on FirebaseFunctionsException catch (error) {
      // Only the verified development allowlist account receives admin claims.
      debugPrint(
        'Development admin bootstrap skipped: ${error.code} ${error.message}',
      );
    }
  }

  String? _validateMobile(String digits) {
    if (_country.isoCode == 'IN') {
      if (!RegExp(r'^[6-9][0-9]{9}$').hasMatch(digits)) {
        return 'Enter a valid 10-digit Indian mobile number.';
      }
      return null;
    }
    if (!RegExp(r'^[0-9]{7,15}$').hasMatch(digits)) {
      return 'Enter a valid mobile number (7–15 digits).';
    }
    return null;
  }

  Future<void> _sendOtp() async {
    final mobile = _phone.text.trim();
    final validationError = _validateMobile(mobile);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: '+${_country.dialCode}$mobile',
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _bootstrapDevelopmentAdmin();
        },
        verificationFailed: (exception) {
          if (mounted) {
            setState(() {
              _error =
                  '${exception.code}: ${exception.message ?? 'Phone verification failed.'}';
            });
          }
        },
        codeSent: (verificationId, _) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _error = null;
            });
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (mounted) setState(() => _verificationId = verificationId);
        },
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() => _error = '${error.code}: ${error.message ?? 'Unable to send OTP.'}');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final id = _verificationId;
    if (id == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: id,
        smsCode: _otp.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _bootstrapDevelopmentAdmin();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        setState(() {
          _error = '${error.code}: ${error.message ?? 'The OTP is invalid or expired.'}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeCountry(_DialingCountry? country) {
    if (country == null || country.isoCode == _country.isoCode) return;
    setState(() {
      _country = country;
      _phone.clear();
      _otp.clear();
      _verificationId = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_balance,
                    size: 64,
                    color: Color(0xFF245C4A),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    strings.appTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(strings.signIn, textAlign: TextAlign.center),
                  const SizedBox(height: 28),
                  DropdownButtonFormField<_DialingCountry>(
                    initialValue: _country,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Country'),
                    items: _supportedCountries
                        .map(
                          (country) => DropdownMenuItem(
                            value: country,
                            child: Text(
                              '${country.flag}  ${country.name} (+${country.dialCode})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy ? null : _changeCountry,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    maxLength: _country.isoCode == 'IN' ? 10 : 15,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        _country.isoCode == 'IN' ? 10 : 15,
                      ),
                    ],
                    decoration: InputDecoration(
                      labelText: strings.phoneNumber,
                      hintText: _country.isoCode == 'IN'
                          ? '10-digit mobile number'
                          : 'Mobile number',
                      prefixText: '+${_country.dialCode} ',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sendOtp,
                    icon: const Icon(Icons.sms_outlined),
                    label: Text(strings.sendOtp),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  if (_verificationId != null) ...[
                    const SizedBox(height: 20),
                    TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(labelText: strings.otp),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _verifyOtp,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(strings.verifyOtp),
                    ),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
