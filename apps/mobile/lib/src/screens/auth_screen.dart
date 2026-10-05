import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../widgets/common.dart';

const _kOtpSeconds = 600; // 10 minutes

// ─── OTP 6-box input ─────────────────────────────────────────────────────────

class _OtpBoxes extends StatefulWidget {
  const _OtpBoxes({required this.onComplete, required this.busy});
  final void Function(String code) onComplete;
  final bool busy;

  @override
  State<_OtpBoxes> createState() => _OtpBoxesState();
}

class _OtpBoxesState extends State<_OtpBoxes> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _focusNodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(int i, String val) {
    final digit = val.replaceAll(RegExp(r'\D'), '');
    if (digit.length > 1) {
      // Paste handling — distribute digits across boxes
      final digits = digit.substring(0, digit.length.clamp(0, 6));
      for (int j = 0; j < digits.length && j < 6; j++) {
        _controllers[j].text = digits[j];
      }
      final next = (digits.length).clamp(0, 5);
      _focusNodes[next].requestFocus();
      _checkComplete();
      return;
    }
    if (digit.isNotEmpty) {
      _controllers[i].text = digit;
      if (i < 5) _focusNodes[i + 1].requestFocus();
      _checkComplete();
    } else {
      _controllers[i].clear();
    }
  }

  void _onKeyDown(int i, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[i].text.isEmpty &&
        i > 0) {
      _focusNodes[i - 1].requestFocus();
      _controllers[i - 1].clear();
    }
  }

  void _checkComplete() {
    final code = _controllers.map((c) => c.text).join();
    if (code.length == 6 &&
        code.split('').every((d) => RegExp(r'\d').hasMatch(d))) {
      widget.onComplete(code);
    }
  }

  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes[0].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (i) {
        return Padding(
          padding: EdgeInsets.only(right: i < 5 ? 8 : 0),
          child: SizedBox(
            width: 44,
            height: 52,
            child: KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (e) => _onKeyDown(i, e),
              child: TextFormField(
                controller: _controllers[i],
                focusNode: _focusNodes[i],
                enabled: !widget.busy,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 2, // allow 2 to catch paste
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF252834) : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD9DBDE)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFD9DBDE)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Color(0xFF4D40ED), width: 2),
                  ),
                ),
                onChanged: (v) => _onChanged(i, v),
                autofocus: i == 0,
                autocorrect: false,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─── OTP countdown + resend ──────────────────────────────────────────────────

class _OtpCountdown extends StatefulWidget {
  const _OtpCountdown({required this.busy, required this.onResend});
  final bool busy;
  final VoidCallback onResend;

  @override
  State<_OtpCountdown> createState() => _OtpCountdownState();
}

class _OtpCountdownState extends State<_OtpCountdown> {
  late int _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _seconds = _kOtpSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_seconds > 0) _seconds--;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void reset() {
    setState(() => _seconds = _kOtpSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final expired = _seconds == 0;
    final mins = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');
    const urgentColor = Color(0xFFDA3038);

    return Column(children: [
      if (!expired)
        Text(
          'Code expires in $mins:$secs',
          style: TextStyle(
            fontSize: 13,
            color: _seconds < 60 ? urgentColor : const Color(0xFF737887),
            fontWeight: _seconds < 60 ? FontWeight.w600 : FontWeight.normal,
          ),
        )
      else
        const Text(
          'Code expired.',
          style: TextStyle(fontSize: 13, color: Color(0xFF737887)),
        ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: widget.busy || !expired ? null : widget.onResend,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          expired ? 'Send new code' : 'Resend code',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF4D40ED),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ]);
  }
}

enum _AuthMode { login, register, otp, forgotPassword }

// Extracted so it can receive api without Provider dependency at this level.
class _AuthBody extends StatelessWidget {
  const _AuthBody({
    required this.formKey,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.mode,
    required this.busy,
    required this.obscure,
    this.error,
    this.info,
    required this.onToggleObscure,
    required this.onModeChange,
    required this.onSubmit,
    required this.onOtpComplete,
    required this.onResend,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController firstName;
  final TextEditingController lastName;
  final TextEditingController email;
  final TextEditingController password;
  final _AuthMode mode;
  final bool busy;
  final bool obscure;
  final String? error;
  final String? info;
  final VoidCallback onToggleObscure;
  final void Function(_AuthMode) onModeChange;
  final Future<void> Function(ApiClient) onSubmit;
  final void Function(String code) onOtpComplete;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: kPage,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: kLine),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.045),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TaskFlowBrand(
                      iconSize: 46,
                      textSize: 28,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.outline,
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 24),
                    if (error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(error!,
                            style: TextStyle(color: colors.onErrorContainer)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (info != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(info!,
                            style: const TextStyle(color: Colors.green)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Form(
                      key: formKey,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (mode == _AuthMode.otp) ...[
                              _OtpBoxes(
                                busy: busy,
                                onComplete: onOtpComplete,
                              ),
                              const SizedBox(height: 12),
                              _OtpCountdown(
                                busy: busy,
                                onResend: onResend,
                              ),
                            ] else ...[
                              if (mode == _AuthMode.register) ...[
                                TextFormField(
                                  controller: firstName,
                                  decoration: const InputDecoration(
                                      labelText: 'First name'),
                                  textInputAction: TextInputAction.next,
                                  validator: _required,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: lastName,
                                  decoration: const InputDecoration(
                                      labelText: 'Last name'),
                                  textInputAction: TextInputAction.next,
                                  validator: _required,
                                ),
                                const SizedBox(height: 12),
                              ],
                              TextFormField(
                                controller: email,
                                decoration: const InputDecoration(
                                    labelText: 'Email address'),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                validator: _emailValidator,
                              ),
                              if (mode != _AuthMode.forgotPassword) ...[
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: password,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    suffixIcon: IconButton(
                                      icon: Icon(obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined),
                                      onPressed: onToggleObscure,
                                    ),
                                  ),
                                  obscureText: obscure,
                                  validator: (v) =>
                                      (mode == _AuthMode.register &&
                                              (v == null || v.length < 8))
                                          ? 'Use at least 8 characters.'
                                          : (mode == _AuthMode.login &&
                                                  (v == null || v.isEmpty))
                                              ? 'Enter your password.'
                                              : null,
                                ),
                              ],
                            ],
                            const SizedBox(height: 20),
                            if (mode != _AuthMode.otp)
                              Builder(builder: (ctx) {
                                final api = _ApiScope.of(ctx);
                                return SizedBox(
                                  height: 44,
                                  child: FilledButton(
                                    onPressed:
                                        busy ? null : () => onSubmit(api),
                                    child: Text(
                                      busy ? 'Please wait…' : _submitLabel,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                );
                              }),
                            const SizedBox(height: 8),
                            if (mode == _AuthMode.otp)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => onModeChange(_AuthMode.login),
                                child: const Text('Back to log in'),
                              )
                            else ...[
                              if (mode == _AuthMode.login)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => onModeChange(
                                          _AuthMode.forgotPassword),
                                  child: const Text('Forgot password?'),
                                ),
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => onModeChange(mode == _AuthMode.login
                                        ? _AuthMode.register
                                        : _AuthMode.login),
                                child: Text(mode == _AuthMode.login
                                    ? 'Don’t have an account? Sign up'
                                    : mode == _AuthMode.register
                                        ? 'Already have an account? Log in'
                                        : 'Back to login'),
                              ),
                            ],
                          ]),
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

  String get _title {
    switch (mode) {
      case _AuthMode.login:
        return 'Welcome back';
      case _AuthMode.register:
        return 'Create your account';
      case _AuthMode.otp:
        return 'Verify your email';
      case _AuthMode.forgotPassword:
        return 'Forgot your password?';
    }
  }

  String get _subtitle {
    switch (mode) {
      case _AuthMode.login:
        return 'Log in to your workspace to continue.';
      case _AuthMode.register:
        return 'Start managing projects with your team.';
      case _AuthMode.otp:
        return 'Enter the six-digit code sent to ${email.text.trim()}.';
      case _AuthMode.forgotPassword:
        return 'Enter your email to receive a reset link.';
    }
  }

  String get _submitLabel {
    switch (mode) {
      case _AuthMode.login:
        return 'Log in';
      case _AuthMode.register:
        return 'Create account';
      case _AuthMode.otp:
        return 'Verify code';
      case _AuthMode.forgotPassword:
        return 'Send reset link';
    }
  }

  static String? _required(String? v) =>
      v == null || v.trim().isEmpty ? 'Required.' : null;

  static String? _emailValidator(String? v) =>
      v != null && RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)
          ? null
          : 'Enter a valid email address.';
}

// ─── Scope that gives AuthBody access to the ApiClient ──────────────────────

class _ApiScope extends InheritedWidget {
  const _ApiScope({required this.api, required super.child});
  final ApiClient api;

  static ApiClient of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ApiScope>()!.api;

  @override
  bool updateShouldNotify(_ApiScope old) => api != old.api;
}

/// Public wrapper that provides the ApiClient via _ApiScope
class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.api, required this.onSignedIn});
  final ApiClient api;
  final VoidCallback onSignedIn;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submitOtp(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.verifyOtp(email: _email.text.trim(), code: code);
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onSignedIn());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resendOtp() {
    setState(() {
      _mode = _AuthMode.login;
      _error = null;
      _info = 'Enter your password again to receive a new code.';
    });
  }

  Future<void> _submit(ApiClient api) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      switch (_mode) {
        case _AuthMode.login:
          await api.login(email: _email.text.trim(), password: _password.text);
          setState(() => _mode = _AuthMode.otp);
          break;
        case _AuthMode.register:
          await api.register(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
          );
          setState(() => _mode = _AuthMode.otp);
          break;
        case _AuthMode.otp:
          break;
        case _AuthMode.forgotPassword:
          await api.forgotPassword(_email.text.trim());
          setState(() {
            _info =
                'Reset link sent. Check your email or the development inbox.';
            _mode = _AuthMode.login;
          });
          break;
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ApiScope(
      api: widget.api,
      child: _AuthBody(
        formKey: _formKey,
        firstName: _firstName,
        lastName: _lastName,
        email: _email,
        password: _password,
        mode: _mode,
        busy: _busy,
        obscure: _obscure,
        error: _error,
        info: _info,
        onToggleObscure: () => setState(() => _obscure = !_obscure),
        onModeChange: (m) => setState(() {
          _mode = m;
          _error = null;
          _info = null;
        }),
        onSubmit: _submit,
        onOtpComplete: _submitOtp,
        onResend: _resendOtp,
      ),
    );
  }
}
