import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../data/api.dart';
import '../app_scope.dart';

String? validateName(String? v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null;

String? validateUsername(String? v) {
  final s = (v ?? '').trim();
  if (!RegExp(r'^[A-Za-z0-9_.]{3,30}$').hasMatch(s)) return '3–30 characters: letters, numbers, _ or .';
  if (RegExp(r'^\d+$').hasMatch(s)) return 'Username cannot be only numbers';
  return null;
}

String? validatePhone(String? v) {
  final d = (v ?? '').replaceAll(RegExp(r'[\s\-+()]'), '');
  if (!RegExp(r'^\d{9,15}$').hasMatch(d)) return 'Enter a valid phone number (9–15 digits)';
  return null;
}

/// Any characters are allowed; the only rule is a length of at least 6.
String? validatePassword(String? v) => (v ?? '').length < 6 ? 'At least 6 characters' : null;

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
  final _name = TextEditingController(), _username = TextEditingController(), _identifier = TextEditingController();
  final _phone = TextEditingController(), _pass = TextEditingController(), _confirm = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;
  bool? _usernameFree; // null = not checked yet
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _username, _identifier, _phone, _pass, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _checkUsername(String v) {
    _debounce?.cancel();
    setState(() => _usernameFree = null);
    if (validateUsername(v) != null) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      try {
        final free = await AppScope.read(context).auth.usernameAvailable(v.trim());
        if (mounted && _username.text.trim() == v.trim()) setState(() => _usernameFree = free);
      } catch (_) {/* offline: the server checks again when you submit */}
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    if (_register && _usernameFree == false) {
      setState(() => _error = 'That username is already taken. Please choose another.');
      return;
    }
    final app = AppScope.read(context);
    final nav = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_register) {
        await app.register(_name.text.trim(), _username.text.trim(), _phone.text.trim(), _pass.text, _confirm.text);
      } else {
        await app.signIn(_identifier.text.trim(), _pass.text);
      }
      if (!mounted) return;
      if (app.user?.mustChangePassword == true) {
        await nav.push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordPage(forced: true)));
      }
      if (mounted) nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'username_taken') _usernameFree = false;
        _error = e.offline ? 'No connection. You can keep practising offline and sign in later.' : e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
                Text(_register ? 'Create your account' : 'Welcome back', style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_register ? 'Your progress is saved and follows you to any phone.' : 'Sign in with your username or phone number.', style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 24),
                if (_register) ...[
                  TextFormField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                    validator: validateName,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _username,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.newUsername],
                    onChanged: _checkUsername,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      helperText: _usernameFree == true ? 'Available' : 'Letters, numbers, _ or . (you can sign in with it)',
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                      suffixIcon: _usernameFree == null ? null : Icon(_usernameFree! ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _usernameFree! ? context.sq.good : context.sq.bad),
                    ),
                    validator: (v) => validateUsername(v) ?? (_usernameFree == false ? 'That username is taken' : null),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone_outlined)),
                    validator: validatePhone,
                  ),
                ] else
                  TextFormField(
                    controller: _identifier,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Username or phone number', prefixIcon: Icon(Icons.person_outline_rounded)),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your username or phone number' : null,
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pass,
                  obscureText: _hide,
                  textInputAction: _register ? TextInputAction.next : TextInputAction.done,
                  onFieldSubmitted: (_) => _register ? null : _submit(),
                  autofillHints: [_register ? AutofillHints.newPassword : AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: 'Password',
                    helperText: _register ? 'At least 6 characters' : null,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(tooltip: _hide ? 'Show password' : 'Hide password', icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => _hide = !_hide)),
                  ),
                  validator: _register ? validatePassword : (v) => (v ?? '').isEmpty ? 'Enter your password' : null,
                ),
                if (_register) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _hide,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline_rounded)),
                    validator: (v) => v != _pass.text ? 'Passwords do not match' : null,
                  ),
                ],
                AnimatedSize(
                  duration: Motion.d(context, 200),
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: context.sq.bad.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(Icons.error_outline_rounded, color: context.sq.bad, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: context.tt.bodyMedium)),
                          ]),
                        ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : Text(_register ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _register = !_register;
                            _error = null;
                          }),
                  child: Text(_register ? 'I already have an account' : 'New here? Create an account'),
                ),
              ]),
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
          child: Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(24), children: [
              if (widget.forced) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text('You must choose a new password before continuing.', style: context.tt.bodyMedium)),
              TextFormField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password'), validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null),
              const SizedBox(height: 14),
              TextFormField(controller: _new, obscureText: true, decoration: const InputDecoration(labelText: 'New password'), validator: validatePassword),
              const SizedBox(height: 14),
              TextFormField(controller: _conf, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password'), validator: (v) => v != _new.text ? 'Passwords do not match' : null),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: TextStyle(color: context.sq.bad))),
              const SizedBox(height: 24),
              FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Save password')),
            ]),
          ),
        ),
      ),
    );
  }
}
