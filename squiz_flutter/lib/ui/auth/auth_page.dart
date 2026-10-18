import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

String? validateName(String? v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null;

String? validatePhone(String? v) {
  final d = (v ?? '').replaceAll(RegExp(r'[\s\-+()]'), '');
  if (!RegExp(r'^\d{9,15}$').hasMatch(d)) return 'Enter a valid phone number (9–15 digits)';
  return null;
}

String? validatePassword(String? v) {
  final s = v ?? '';
  if (s.length < 8) return 'Password must be at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Include both letters and numbers';
  return null;
}

/// Professional Sign in and Registration Page
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.startWithRegister = false});
  final bool startWithRegister;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  late bool _register = widget.startWithRegister;
  
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _needPhone = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final app = AppScope.read(context);
    final nav = Navigator.of(context);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_register) {
        await app.register(
          _nameController.text.trim(),
          _phoneController.text.trim(),
          _passwordController.text,
          _confirmController.text,
        );
      } else {
        await app.signIn(
          _needPhone ? _phoneController.text.trim() : _nameController.text.trim(),
          _passwordController.text,
        );
      }

      if (!mounted) return;
      if (app.user?.mustChangePassword == true) {
        await nav.push(MaterialPageRoute<void>(
          builder: (_) => const ChangePasswordPage(forced: true),
        ));
      }
      if (mounted) nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'ambiguous_name') {
          _needPhone = true;
          _errorMessage = 'Multiple students share this name. Please sign in using your phone number.';
        } else {
          _errorMessage = e.offline
              ? 'No internet connection. You can practice offline and sign in later.'
              : e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                children: [
                  // App Branding / Header Icon
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _register ? Icons.person_add_rounded : Icons.lock_person_rounded,
                        size: 32,
                        color: cs.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Title Header
                  Text(
                    _register ? 'Create Account' : 'Welcome Back',
                    textAlign: TextAlign.center,
                    style: context.tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _register
                        ? 'Sign up to sync and back up your learning progress'
                        : 'Sign in to access your saved quizzes and stats',
                    textAlign: TextAlign.center,
                    style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 28),

                  // Standard Segmented Tab Switcher (Sign In vs Register)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _register = false;
                              _errorMessage = null;
                              _needPhone = false;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_register ? cs.surface : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: !_register
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: !_register ? cs.primary : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _register = true;
                              _errorMessage = null;
                              _needPhone = false;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _register ? cs.surface : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: _register
                                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))]
                                    : [],
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'Register',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _register ? cs.primary : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Form Fields
                  if (_register || !_needPhone) ...[
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: InputDecoration(
                        labelText: _register ? 'Full Name' : 'Full Name or Phone Number',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: _register ? validateName : (v) => (v ?? '').trim().isEmpty ? 'Field cannot be empty' : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_register || _needPhone) ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: validatePhone,
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                    onFieldSubmitted: (_) => _register ? null : _handleSubmit(),
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: _register ? validatePassword : (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                  ),

                  if (_register) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleSubmit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                    ),
                  ],

                  // Forgot Password Link (Sign In view only)
                  if (!_register)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          // Standard recovery action placeholder
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Contact administration to reset your credentials.')),
                          );
                        },
                        child: Text('Forgot Password?', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                      ),
                    ),

                  // Error Display Banner
                 AnimatedContainer(
                      duration: Motion.d(context, 200),
                      curve: Curves.easeOutCubic,
                      height: _errorMessage == null ? 0 : null, // Smoothly collapses height to 0
                      child: _errorMessage == null
                          ? const SizedBox.shrink()
                          : Container(
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.sq.bad.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.sq.bad.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline_rounded, color: context.sq.bad, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(_errorMessage!, style: TextStyle(color: context.sq.bad, fontSize: 13)),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),

                  // Primary Submit Button
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _handleSubmit,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _register ? 'Create Account' : 'Sign In',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Legal Disclaimer Footer (Register view only)
                  if (_register)
                    Text(
                      'By creating an account, you agree to follow standard examination policies and student data guidelines.',
                      textAlign: TextAlign.center,
                      style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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

/// Standard Change Password Dialog / Page
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, this.forced = false});
  final bool forced;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await app.changePassword(_currentController.text, _newController.text);
      messenger.showSnackBar(const SnackBar(content: Text('Password updated successfully')));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.offline ? 'No network connection.' : e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Change Password'),
          automaticallyImplyLeading: !widget.forced,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (widget.forced)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          'Your account requires a password update before proceeding.',
                          style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    TextFormField(
                      controller: _currentController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) => (v ?? '').isEmpty ? 'Enter current password' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _newController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: validatePassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v != _newController.text ? 'Passwords do not match' : null,
                    ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_errorMessage!, style: TextStyle(color: context.sq.bad)),
                      ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _isLoading ? null : _savePassword,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Update Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
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