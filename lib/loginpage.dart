import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mainscreen.dart';
import 'signupscreen.dart';

// --- Define Custom Colors as top-level constants or static const in the class ---
const Color _bgColor = Color(0xFFF5F7FA);
const Color _buttonColor = Color(0xFF4A90E2);
const Color _buttonTextColor = Color(0xFFFFFFFF); // White
const Color _textFieldBgColor = Color(0xFFE9EEF6);
const Color _textFieldTextColor = Color(0xFF333333); // Dark Gray
const Color _hintTextColor = Color(0xFF666666); // Slightly lighter gray for hints/labels
const Color _errorTextColor = Colors.red; // Standard error color
const Color _successTextColor = Colors.green; // For success messages

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _forgotPasswordEmailController = TextEditingController(); // For dialog

  bool _isLoading = false;
  bool _obscureText = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _forgotPasswordEmailController.dispose(); // Dispose new controller
    super.dispose();
  }

  Future<void> _saveEmailLocally(String? email) async {
    if (email == null || email.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);
      debugPrint('Email saved: $email');
    } catch (e) {
      debugPrint('Error saving email: $e');
    }
  }

  Future<void> _signInWithEmailAndPassword() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await _saveEmailLocally(credential.user?.email);
      _navigateToMainScreen();
    } on FirebaseAuthException catch (e) {
      String friendlyMessage;
      debugPrint('FirebaseAuthException code: ${e.code}');
      debugPrint('FirebaseAuthException message: ${e.message}');

      if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'INVALID_LOGIN_CREDENTIALS') {
        friendlyMessage = 'Wrong credentials entered. Please try again.';
      } else if (e.code == 'invalid-email') {
        friendlyMessage = 'The email address is badly formatted.';
      } else if (e.code == 'user-disabled') {
        friendlyMessage = 'This account has been disabled.';
      } else {
        friendlyMessage = 'Login failed. Please check your connection or try again later.';
      }
      _handleAuthError(friendlyMessage);
    } catch (e) {
      _handleAuthError('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showInfoSnackBar('Google sign-in cancelled.');
        }
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      await _saveEmailLocally(userCredential.user?.email);
      _navigateToMainScreen();
    } on FirebaseAuthException catch (e) {
      String friendlyMessage;
      // Handle Google Sign-In specific errors if needed, or use a generic one
      if (e.code == 'account-exists-with-different-credential') {
        friendlyMessage = 'An account already exists with the same email address but different sign-in credentials. Try signing in with a different method.';
      } else {
        friendlyMessage = 'Google sign-in failed. Please try again.';
      }
      _handleAuthError(friendlyMessage);
    } catch (e) {
      _handleAuthError('An unexpected error occurred during Google sign-in.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleAuthError(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message; // Keep for inline error text
      });
      _showErrorSnackBar(message); // Also show as SnackBar
    }
  }

  Future<void> _sendPasswordResetEmail(String email) async {
    if (email.trim().isEmpty) {
      _showErrorSnackBar('Please enter your email address.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      _showSuccessSnackBar('Password reset email sent to $email. Please check your inbox.');
    } on FirebaseAuthException catch (e) {
      String friendlyMessage = 'Failed to send reset email. Please try again.';
      if (e.code == 'user-not-found') {
        friendlyMessage = 'No user found with this email address.';
      } else if (e.code == 'invalid-email') {
        friendlyMessage = 'The email address is not valid.';
      }
      _showErrorSnackBar(friendlyMessage);
    } catch (e) {
      _showErrorSnackBar('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showForgotPasswordDialog() {
    if (_emailController.text.isNotEmpty) {
      _forgotPasswordEmailController.text = _emailController.text.trim();
    } else {
      _forgotPasswordEmailController.clear();
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
          title: const Text('Reset Password', style: TextStyle(color: _textFieldTextColor)),
          backgroundColor: _bgColor,
          content: TextField(
            controller: _forgotPasswordEmailController,
            autofocus: true,
            style: const TextStyle(color: _textFieldTextColor),
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email Address',
              labelStyle: const TextStyle(color: _hintTextColor),
              hintText: 'Enter your registered email',
              hintStyle: const TextStyle(color: _hintTextColor),
              prefixIcon: const Icon(Icons.email_outlined, color: _hintTextColor),
              filled: true,
              fillColor: _textFieldBgColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: _hintTextColor)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _buttonColor,
                foregroundColor: _buttonTextColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              child: const Text('Send Reset Link'),
              onPressed: () async {
                final emailToSend = _forgotPasswordEmailController.text.trim();
                Navigator.of(dialogContext).pop();
                if (emailToSend.isNotEmpty) {
                  await _sendPasswordResetEmail(emailToSend);
                } else {
                  _showErrorSnackBar("Email cannot be empty.");
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _navigateToMainScreen() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    }
  }

  void _navigateToSignUpScreen() {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SignUpScreen()),
      );
    }
  }

  void _showSnackBar(String message, Color backgroundColor, {Color textColor = Colors.white}) {
    if (mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: textColor)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: backgroundColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.fromLTRB(15, 5, 15, 15),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    _showSnackBar(message, Theme.of(context).colorScheme.error.withOpacity(0.95));
  }

  void _showSuccessSnackBar(String message) {
    _showSnackBar(message, _successTextColor.withOpacity(0.95));
  }

  void _showInfoSnackBar(String message) {
    _showSnackBar(message, Colors.blueGrey.withOpacity(0.95));
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: _bgColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 80,
                  errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.image_not_supported, size: 80, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                Text(
                  'Welcome Back!',
                  style: textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: _textFieldTextColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Login to continue',
                  style: textTheme.bodyLarge?.copyWith(color: _hintTextColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: _textFieldTextColor),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: _hintTextColor),
                    prefixIcon: Icon(Icons.email_outlined, color: _hintTextColor),
                    filled: true,
                    fillColor: _textFieldBgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12.0)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: _textFieldTextColor),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: _hintTextColor),
                    prefixIcon: const Icon(Icons.lock_outline, color: _hintTextColor),
                    filled: true,
                    fillColor: _textFieldBgColor,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12.0)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: _hintTextColor,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureText = !_obscureText;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureText,
                  textInputAction: TextInputAction.done,
                  onEditingComplete: _isLoading ? null : _signInWithEmailAndPassword,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: TextButton(
                      onPressed: _isLoading ? null : _showForgotPasswordDialog,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: _buttonColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_errorMessage != null && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: _errorTextColor, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_errorMessage == null && !_isLoading) const SizedBox(height: 16),
                _isLoading
                    ? const Center(child: CircularProgressIndicator(color: _buttonColor))
                    : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _buttonColor,
                      foregroundColor: _buttonTextColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      )),
                  onPressed: _signInWithEmailAndPassword,
                  child: const Text('Login', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account?", style: textTheme.bodyMedium?.copyWith(color: _hintTextColor)),
                    TextButton(
                      onPressed: _isLoading ? null : _navigateToSignUpScreen,
                      child: const Text(
                        'Sign up',
                        style: TextStyle(
                          color: _buttonColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: Divider(thickness: 1, color: Colors.grey[300])),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Text('OR', style: TextStyle(color: _hintTextColor)),
                    ),
                    Expanded(child: Divider(thickness: 1, color: Colors.grey[300])),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: _buttonColor,
                    foregroundColor: _buttonTextColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    elevation: 1,
                  ),
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: Image.asset(
                    'assets/google_icon.png',
                    height: 24,
                    width: 24,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.g_mobiledata, size: 24, color: _buttonTextColor),
                  ),
                  label: const Text('Continue with Google', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}