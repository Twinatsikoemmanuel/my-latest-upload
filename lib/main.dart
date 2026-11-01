import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'src/auth_screen.dart';
import 'src/dashboard.dart';
import 'src/debtmate_models.dart';
import 'src/firestore_service.dart';

const ink = Color(0xFF172E29);
const leaf = Color(0xFF146B55);
const canvas = Color(0xFFF4F7F5);
const line = Color(0xFFE2E9E5);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = firebaseOptionsFromEnvironment;
  Object? initializationError;
  if (options != null) {
    try {
      await Firebase.initializeApp(options: options)
          .timeout(const Duration(seconds: 20));
    } catch (error) {
      initializationError = error;
    }
  }
  runApp(
    DebtMateApp(
      configured: options != null && initializationError == null,
      error: initializationError,
    ),
  );
}

class DebtMateApp extends StatelessWidget {
  const DebtMateApp({super.key, required this.configured, this.error});

  final bool configured;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: leaf,
          brightness: Brightness.light,
        ).copyWith(
          primary: leaf,
          onPrimary: Colors.white,
          secondary: const Color(0xFFD99A45),
          surface: Colors.white,
          error: const Color(0xFFB5433C),
        );
    return MaterialApp(
      title: 'DebtMate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: canvas,
        dividerColor: line,
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: leaf, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: line),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      home: configured
          ? const SessionRouter()
          : FirebaseSetupPage(error: error),
    );
  }
}

class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                color: leaf,
                size: 34,
              ),
              const SizedBox(height: 18),
              Text(
                'Connect DebtMate to Firebase',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(color: ink, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Create or select the DabtMateApp Firebase project, enable Email/Password authentication, and create a Cloud Firestore database.',
              ),
              const SizedBox(height: 20),
              const SelectableText(
                'flutter run -d chrome --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=... --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=... --dart-define=FIREBASE_AUTH_DOMAIN=...',
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  'Firebase initialization failed: $error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class SessionRouter extends StatelessWidget {
  const SessionRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = FirebaseAuth.instance;
    final service = FirestoreService(FirebaseFirestore.instance);
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const LoadingPage();
        }
        final authUser = authSnapshot.data;
        if (authUser == null) return AuthScreen(auth: auth, service: service);
        return StreamBuilder<BusinessUser?>(
          stream: service.watchProfile(authUser.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return ErrorPage(message: profileSnapshot.error.toString());
            }
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingPage();
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              return ProfileSetupPage(authUser: authUser, service: service);
            }
            if (!profile.isCustomer && profile.businessId.isEmpty) {
              return const LoadingPage();
            }
            return DashboardPage(
              auth: auth,
              authUser: authUser,
              profile: profile,
              service: service,
            );
          },
        );
      },
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SelectableText(message),
      ),
    ),
  );
}

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({
    super.key,
    required this.authUser,
    required this.service,
  });

  final User authUser;
  final FirestoreService service;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _businessController = TextEditingController();
  String _role = 'owner';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _businessController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_role == 'owner') {
        await widget.service.createOwnerProfile(
          authUser: widget.authUser,
          name: _nameController.text,
          businessName: _businessController.text,
        );
      } else {
        await widget.service.createCustomerProfile(
          authUser: widget.authUser,
          name: _nameController.text,
        );
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: leaf,
                    size: 34,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Set up your DebtMate account',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 20),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'owner',
                        label: Text('Business owner'),
                        icon: Icon(Icons.storefront_outlined),
                      ),
                      ButtonSegment(
                        value: 'customer',
                        label: Text('Customer'),
                        icon: Icon(Icons.person_outline),
                      ),
                    ],
                    selected: {_role},
                    onSelectionChanged: (selection) =>
                        setState(() => _role = selection.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    validator: _required,
                  ),
                  if (_role == 'owner') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _businessController,
                      decoration: const InputDecoration(
                        labelText: 'Business name',
                      ),
                      validator: _required,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Continue'),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text('Sign out'),
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

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;
