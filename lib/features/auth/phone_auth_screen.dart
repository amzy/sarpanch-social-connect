import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});
  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController(),
      _username = TextEditingController(),
      _mobile = TextEditingController();
  bool _register = false, _busy = false, _hide = true;
  String _dialCode = '+91';
  String? _error, _notice;
  static const _codes = {
    'India (+91)': '+91',
    'US (+1)': '+1',
    'UK (+44)': '+44',
    'UAE (+971)': '+971',
    'Canada (+1)': '+1',
    'Australia (+61)': '+61',
  };
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _username.dispose();
    _mobile.dispose();
    super.dispose();
  }

  String? _emailValid(String? v) =>
      (v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()))
          ? null
          : 'Enter a valid email address.';
  String? _passwordValid(String? v) =>
      (v != null && v.length >= 8) ? null : 'Use at least 8 characters.';
  String? _usernameValid(String? v) => (v != null &&
          RegExp(r'^[a-z][a-z0-9_]{2,19}$').hasMatch(v.trim().toLowerCase()))
      ? null
      : 'Use 3–20 letters, numbers or underscores; start with a letter.';
  String? _mobileValid(String? v) {
    final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return d.length >= 7 && d.length <= 15 ? null : 'Enter 7–15 digits.';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => {_busy = true, _error = null, _notice = null});
    try {
      final auth = FirebaseAuth.instance,
          email = _email.text.trim().toLowerCase();
      if (!_register) {
        await auth.signInWithEmailAndPassword(
          email: email,
          password: _password.text,
        );
      } else {
        final username = _username.text.trim().toLowerCase(),
            mobile = _dialCode + _mobile.text.replaceAll(RegExp(r'\D'), '');
        final user = (await auth.createUserWithEmailAndPassword(
          email: email,
          password: _password.text,
        ))
            .user!;
        try {
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final claim = FirebaseFirestore.instance
                .collection('username_claims')
                .doc(username);
            if ((await tx.get(claim)).exists)
              throw StateError('Username already taken. Choose another.');
            tx.set(claim, {
              'uid': user.uid,
              'createdAt': FieldValue.serverTimestamp(),
            });
            tx.set(
              FirebaseFirestore.instance.collection('users').doc(user.uid),
              {
                'uid': user.uid,
                'email': email,
                'username': username,
                'mobileNumber': mobile,
                'profileComplete': false,
                'plan': 'free',
                'billingStatus': 'active',
                'createdAt': FieldValue.serverTimestamp(),
              },
            );
          });
        } catch (_) {
          await user.delete();
          rethrow;
        }
        await user.updateDisplayName(username);
        try {
          await user.sendEmailVerification();
        } catch (error) {
          debugPrint('Email verification message could not be sent: $error');
        }
        await auth.signOut();
        if (mounted)
          setState(
            () => _notice =
                'Account created. You can now sign in. A verification email was sent if email delivery is enabled.',
          );
      }
    } on FirebaseAuthException catch (e) {
      final msg = switch (e.code) {
        'email-already-in-use' => 'An account already exists for this email.',
        'invalid-email' => 'Enter a valid email address.',
        'weak-password' => 'Choose a stronger password.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'too-many-requests' => 'Too many attempts. Try again later.',
        'network-request-failed' => 'Check your internet connection.',
        _ => e.message ?? 'Authentication failed: ' + e.code,
      };
      if (mounted) setState(() => _error = msg);
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final validation = _emailValid(_email.text);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() => {_busy = true, _error = null});
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _email.text.trim(),
      );
      if (mounted)
        setState(() => _notice = 'Password reset link sent. Check your email.');
    } on FirebaseAuthException catch (e) {
      if (mounted)
        setState(() => _error = e.message ?? 'Unable to send reset email.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
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
                      'Sarpanch Social Connect',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _register
                          ? 'Create your account'
                          : 'Sign in to your account',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_register) ...[
                      TextFormField(
                        controller: _username,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z0-9_]'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          helperText: 'Unique username, 3–20 characters.',
                        ),
                        validator: _usernameValid,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: DropdownButtonFormField<String>(
                              initialValue: _dialCode,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Country code',
                              ),
                              items: _codes.entries
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e.value,
                                      child: Text(e.value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => _dialCode = v ?? '+91'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _mobile,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(15),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Mobile number',
                              ),
                              validator: _mobileValid,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email address',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      validator: _emailValid,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _hide,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hide = !_hide),
                          icon: Icon(
                            _hide ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: _passwordValid,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                        ),
                        validator: (v) => v == _password.text
                            ? null
                            : 'Passwords do not match.',
                      ),
                    ] else
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _reset,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const CircularProgressIndicator()
                          : Text(_register ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                                () => {
                                  _register = !_register,
                                  _error = null,
                                  _notice = null,
                                },
                              ),
                      child: Text(
                        _register
                            ? 'Already registered? Sign in'
                            : 'New here? Create an account',
                      ),
                    ),
                    if (_notice != null)
                      Text(
                        _notice!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.primary),
                      ),
                    if (_error != null)
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    if (_register)
                      Text(
                        'Email is used for sign-in and password recovery. Username and mobile are linked for future sign-in options.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
