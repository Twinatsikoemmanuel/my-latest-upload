import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'firestore_service.dart';

const _ink = Color(0xFF172E29);
const _leaf = Color(0xFF146B55);

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.auth, required this.service});

  final FirebaseAuth auth;
  final FirestoreService service;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _registering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_registering) {
        await widget.auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await widget.auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _authMessage(error));
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    try {
      await widget.auth.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset email sent.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _authMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Row(
            children: [
              if (wide)
                Expanded(
                  child: Container(
                    color: _ink,
                    padding: const EdgeInsets.all(56),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_outlined,
                              color: Color(0xFFB8DDC8),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'DebtMate',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Clear records.\nBetter follow-up.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 42,
                                height: 1.12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 18),
                            Text(
                              'A calmer way to keep credit moving.',
                              style: TextStyle(
                                color: Color(0xFFC1D1CA),
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'PRIVATE BUSINESS LEDGER',
                          style: TextStyle(
                            color: Color(0xFFB8DDC8),
                            letterSpacing: 1.4,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 52 : 24,
                        vertical: 32,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!wide)
                              const Row(
                                children: [
                                  Icon(
                                    Icons.account_balance_wallet_outlined,
                                    color: _leaf,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'DebtMate',
                                    style: TextStyle(
                                      color: _ink,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 36),
                            Text(
                              _registering
                                  ? 'Create your account'
                                  : 'Welcome back',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: _ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _registering
                                  ? 'Start keeping your credit records in one place.'
                                  : 'Sign in to your business ledger or customer account.',
                              style: const TextStyle(color: Color(0xFF62716B)),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Email address',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) =>
                                  value == null || !value.contains('@')
                                  ? 'Enter a valid email address'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              autofillHints: [
                                _registering
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              validator: (value) =>
                                  value == null || value.length < 6
                                  ? 'Use at least 6 characters'
                                  : null,
                            ),
                            if (!_registering)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _resetPassword,
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: _busy ? null : _submitEmail,
                              child: _busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _registering
                                          ? 'Create account'
                                          : 'Sign in',
                                    ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () => setState(() {
                                _registering = !_registering;
                                _error = null;
                              }),
                              child: Text(
                                _registering
                                    ? 'Already registered? Sign in'
                                    : 'New to DebtMate? Create an account',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

String _authMessage(FirebaseAuthException error) => switch (error.code) {
  'user-not-found' ||
  'wrong-password' ||
  'invalid-credential' => 'Email or password is incorrect.',
  'email-already-in-use' => 'An account already exists for this email.',
  'weak-password' => 'Choose a stronger password.',
  'invalid-email' => 'Enter a valid email address.',
  'operation-not-allowed' => 'Email/password sign-in is disabled. Enable Email/Password in Firebase Authentication settings.',
  'unauthorized-domain' => 'This website is not authorized for Firebase sign-in. Add its domain in Firebase Authentication settings.',
  'network-request-failed' =>
    'Could not reach Firebase. Check your internet connection and try again.',
  _ =>
    error.message == null || error.message!.trim().isEmpty
        ? 'Authentication failed (Firebase code: ${error.code}). Check the Firebase Authentication settings.'
        : '${error.message} (Firebase code: ${error.code})',
};
