import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
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
      // Normal users can sign in; only the allowlisted development account
      // receives the administrator claim.
      debugPrint('Development admin bootstrap skipped: ${error.code} ${error.message}');
    }
  }

  Future<void> _sendOtp() async {
    setState(() { _busy = true; _error = null; });
    final number = _phone.text.trim();
    if (!number.startsWith('+') || number.length < 9) {
      setState(() { _busy = false; _error = 'Enter the number with country code, for example +91XXXXXXXXXX.'; });
      return;
    }
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: number,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          await _bootstrapDevelopmentAdmin();
        },
        verificationFailed: (exception) => setState(() => _error = '${exception.code}: ${exception.message ?? 'Phone verification failed.'}'),
        codeSent: (verificationId, _) => setState(() => _verificationId = verificationId),
        codeAutoRetrievalTimeout: (verificationId) => setState(() => _verificationId = verificationId),
      );
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final id = _verificationId;
    if (id == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final credential = PhoneAuthProvider.credential(verificationId: id, smsCode: _otp.text.trim());
      await FirebaseAuth.instance.signInWithCredential(credential);
      await _bootstrapDevelopmentAdmin();
    } on FirebaseAuthException catch (error) {
      setState(() => _error = '${error.code}: ${error.message ?? 'The OTP is invalid or expired.'}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.account_balance, size: 64, color: Color(0xFF245C4A)),
                const SizedBox(height: 20),
                Text(strings.appTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(strings.signIn, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                TextField(controller: _phone, keyboardType: TextInputType.phone, textInputAction: TextInputAction.done, decoration: InputDecoration(labelText: strings.phoneNumber, hintText: '+91XXXXXXXXXX')),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _busy ? null : _sendOtp, icon: const Icon(Icons.sms_outlined), label: Text(strings.sendOtp), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
                if (_verificationId != null) ...[
                  const SizedBox(height: 20),
                  TextField(controller: _otp, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: strings.otp)),
                  FilledButton(onPressed: _busy ? null : _verifyOtp, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: Text(strings.verifyOtp)),
                ],
                if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
