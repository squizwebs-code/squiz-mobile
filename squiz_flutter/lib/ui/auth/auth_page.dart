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
  if (s.length < 8) return 'At least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Use letters and numbers';
  return null;
}

/// Sign in or create an account. Accounts are always student accounts; the app never sends a role.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.startWithRegister = false});
  final bool startWithRegister;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  late bool _register = widget.startWithRegister;
  final _name = TextEditingController(), _phone = TextEditingController(), _pass = TextEditingController(), _confirm = TextEditingController();
  bool _busy = false, _hide = true, _needPhone = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _phone, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await app.register(_name.text.trim(), _phone.text.trim(), _pass.text, _confirm.text);
      } else {
        await app.signIn(_needPhone ? _phone.text.trim() : _name.text.trim(), _pass.text);
      }
      if (!mounted) return;
      if (app.user?.mustChangePassword == true) {
        await nav.push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordPage(forced: true)));
      }
      if (mounted) nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'ambiguous_name') {
          _needPhone = true;
          _error = 'More than one student has that name. Sign in with your phone number instead.';
        } else {
          _error = e.offline ? 'No connection. You can keep practising offline and sign in later.' : e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                children: [
                  // App branding header icon or badge
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _register ? Icons.person_add_rounded : Icons.lock_open_rounded,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _register ? 'Create your account' : 'Welcome back',
                    style: context.tt.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _register 
                        ? 'Your progress is saved and follows you to any phone.' 
                        : 'Sign in to bring your progress with you.',
                    style: context.tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Form Fields Card Container
                  if (_register || !_needPhone) ...[
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: InputDecoration(
                        labelText: _register ? 'Full name' : 'Full name or phone number',
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: _register ? validateName : (v) => (v ?? '').trim().isEmpty ? 'Enter your name or phone number' : null,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (_register || _needPhone) ...[
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: InputDecoration(
                        labelText: 'Phone number',
                        prefixIcon: const Icon(Icons.phone_outlined),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: validatePhone,
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextFormField(
                    controller: _pass,
                    obscureText: _hide,
                    textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                    onFieldSubmitted: (_) => _register ? null : _submit(),
                    autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      suffixIcon: IconButton(
                        tooltip: _hide ? 'Show password' : 'Hide password',
                        icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hide = !_hide),
                      ),
                    ),
                    validator: _register ? validatePassword : (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                  ),

                  if (_register) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _hide,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v != _pass.text ? 'Passwords do not match' : null,
                    ),
                  ],

                  // Animated Error Banner
                  AnimatedSize(
                    duration: Motion.d(context, 200),
                    child: _error == null
                        ? const SizedBox.shrink()
                        : Container(
                            margin: const EdgeInsets.only(top: 20),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: context.sq.bad.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: context.sq.bad.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded, color: context.sq.bad, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: context.tt.bodyMedium?.copyWith(color: context.sq.bad),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 28),

                  // Action Button
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _register ? 'Create account' : 'Sign in',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Switch Mode Toggle Button
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _register = !_register;
                              _error = null;
                              _needPhone = false;
                            }),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      _register ? 'I already have an account' : 'New here? Create an account',
                      style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary),
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

/// Used from Profile, and shown automatically when the server says the password must be changed.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, this.forced = false});
  final bool forced;
  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _cur = TextEditingController(), _new = TextEditingController(), _conf = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_cur, _new, _conf]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.changePassword(_cur.text, _new.text);
      messenger.showSnackBar(const SnackBar(content: Text('Password changed')));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.offline ? 'No connection. Try again when you are online.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(title: const Text('Change password'), automaticallyImplyLeading: !widget.forced),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    if (widget.forced)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Text(
                          'You must choose a new password before continuing.',
                          style: context.tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                        ),
                      ),
                    TextFormField(
                      controller: _cur,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Current password',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _new,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: validatePassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _conf,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Confirm new password',
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v != _new.text ? 'Passwords do not match' : null,
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(_error!, style: TextStyle(color: context.sq.bad)),
                      ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text('Save password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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