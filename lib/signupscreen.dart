import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'loginpage.dart'; // Import your LoginPage

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key}); // Use super parameters

  @override
  State<SignUpScreen> createState() => _SignUpScreenState(); // Use modern syntax
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false; // Track loading state
  String? _errorMessage; // For displaying inline errors
  bool _isVerificationSent = false; // Track if verification link has been sent
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // --- Define Custom Colors (same as LoginPage) ---
  static const Color bgColor = Color(0xFFF5F7FA);
  static const Color buttonColor = Color(0xFF4A90E2);
  static const Color buttonTextColor = Color(0xFFFFFFFF);
  static const Color textFieldBgColor = Color(0xFFE9EEF6);
  static const Color textFieldTextColor = Color(0xFF333333);
  static const Color hintTextColor = Color(0xFF666666);
  static const Color errorTextColor = Colors.red;
  static const Color successColor = Colors.green; // For success messages/icons

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- Input Validation ---
  bool _validateInputs() {
    final email = _emailController.text.trim();
    final password = _passwordController.text; // Don't trim password
    final confirmPassword = _confirmPasswordController.text;

    // Basic Email Regex (Consider a more robust one if needed)
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      setState(() => _errorMessage = 'All fields are required.');
      return false;
    }
    if (!emailRegex.hasMatch(email)) {
      setState(() => _errorMessage = 'Please enter a valid email address.');
      return false;
    }
    // Basic Password Strength (Example: Minimum 6 characters)
    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters long.');
      return false;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return false;
    }

    // Clear error if validation passes
    setState(() => _errorMessage = null);
    return true;
  }

  // --- Send Verification Email ---
  Future<void> _signUpAndSendVerification() async {
    // Hide keyboard
    FocusScope.of(context).unfocus();

    if (!_validateInputs()) {
      return; // Stop if validation fails
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null; // Clear previous errors
      _isVerificationSent = false; // Reset verification status on new attempt
    });

    try {
      // 1. Create the user
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text, // Use untrimmed password
      );

      // 2. Send verification email (check if user is not null)
      if (userCredential.user != null) {
        await userCredential.user!.sendEmailVerification();

        if (mounted) {
          setState(() {
            _isVerificationSent = true;
            // Provide positive feedback inline or via SnackBar
            _errorMessage = 'Verification link sent! Check your email (and spam folder).'; // Use _errorMessage for feedback too
          });
          _showFeedbackSnackBar('Verification link sent!', isError: false);
        }
      } else {
        _handleError("User creation succeeded but user object is null.");
      }

    } on FirebaseAuthException catch (e) {
      _handleFirebaseAuthError(e);
    } catch (e) {
      _handleError("An unexpected error occurred: ${e.toString()}");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- Error Handling ---
  void _handleFirebaseAuthError(FirebaseAuthException e) {
    String message;
    switch (e.code) {
      case 'email-already-in-use':
        message = 'This email address is already registered. Try logging in.';
        break;
      case 'weak-password':
        message = 'The password provided is too weak.';
        break;
      case 'invalid-email':
        message = 'The email address is not valid.';
        break;
      default:
        message = 'An error occurred during sign up. Please try again.';
    // Log the specific error for debugging: print('SignUp Error: ${e.code} - ${e.message}');
    }
    if (mounted) {
      setState(() => _errorMessage = message);
      _showFeedbackSnackBar(message, isError: true);
    }
  }

  void _handleError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
      _showFeedbackSnackBar(message, isError: true);
    }
  }


  // --- Navigate to Login ---
  void _navigateToLogin() {
    if (mounted) {
      // Maybe clear fields before navigating back? Optional.
      // _emailController.clear();
      // _passwordController.clear();
      // _confirmPasswordController.clear();
      Navigator.pushReplacement( // Use pushReplacement if you don't want users going back to signup after verifying
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  // --- Show SnackBar for Feedback ---
  void _showFeedbackSnackBar(String message, {bool isError = true}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error.withValues(alpha: 0.95)
              : successColor.withValues(alpha: 0.95), // Use success color for non-errors
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: bgColor, // Apply background color
      // No AppBar for consistency with LoginPage example
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Optional: Add Logo consistent with Login Page
                Image.asset(
                  'assets/logo.png', // Replace with your logo
                  height: 80,
                  errorBuilder: (context, error, stackTrace) => Icon(Icons.app_registration, size: 80, color: Colors.grey[400]),
                ),
                const SizedBox(height: 32),

                Text(
                  'Create Account', // Clearer Title
                  style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold, color: textFieldTextColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your details below',
                  style: textTheme.bodyLarge?.copyWith(color: hintTextColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // --- Email Field ---
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: textFieldTextColor),
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: const TextStyle(color: hintTextColor),
                    prefixIcon: const Icon(Icons.email_outlined, color: hintTextColor),
                    filled: true,
                    fillColor: textFieldBgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading, // Disable during loading
                ),
                const SizedBox(height: 16),

                // --- Password Field ---
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: textFieldTextColor),
                  decoration: InputDecoration(
                    labelText: 'Create Password',
                    labelStyle: const TextStyle(color: hintTextColor),
                    prefixIcon: const Icon(Icons.lock_outline, color: hintTextColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: hintTextColor,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: textFieldBgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                  ),
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // --- Confirm Password Field ---
                TextField(
                  controller: _confirmPasswordController,
                  style: const TextStyle(color: textFieldTextColor),
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    labelStyle: const TextStyle(color: hintTextColor),
                    prefixIcon: const Icon(Icons.lock_outline, color: hintTextColor),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: hintTextColor,
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    filled: true,
                    fillColor: textFieldBgColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
                  ),
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done, // Last field
                  onEditingComplete: _isLoading ? null : _signUpAndSendVerification, // Allow submit from keyboard
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 16),

                // --- Inline Error/Feedback Message Display ---
                if (_errorMessage != null && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      // Use success color if verification was just sent, otherwise error color
                      style: TextStyle(color: _isVerificationSent ? successColor : errorTextColor, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // --- Loading Indicator / Sign Up Button ---
                _isLoading
                    ? const Center(child: CircularProgressIndicator(color: buttonColor))
                    : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: buttonColor,
                      foregroundColor: buttonTextColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.0),
                      )
                  ),
                  onPressed: _signUpAndSendVerification, // Call the combined function
                  child: const Text('Sign Up & Verify Email', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 10),

                // --- Verification Info Box (conditionally shown or always visible) ---
                if (_isVerificationSent) // Show only after attempting to send
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: successColor.withValues(alpha: 0.1), // Light success background
                      border: Border.all(color: successColor.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Check your email (including spam) for the verification link.',
                      style: TextStyle(
                        // --- FIX HERE ---
                        // Directly use the shade from the MaterialColor
                        color: Colors.green.shade800, // Darker success text
                        // fontWeight: FontWeight.bold, // Optional: Remove or keep as needed
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                // --- Conditional "Go to Login" Button ---
                // This button simply navigates. Verification is checked on Login attempt.
                if (_isVerificationSent && !_isLoading) // Show only after sending and not loading
                  Padding(
                    padding: const EdgeInsets.only(top: 10.0), // Add some space if it appears
                    child: OutlinedButton( // Use OutlinedButton for secondary action
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: buttonColor, // Use button color for text/border
                          side: const BorderSide(color: buttonColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                          )
                      ),
                      onPressed: _navigateToLogin,
                      child: const Text('Verified? Go to Login', style: TextStyle(fontSize: 16)),
                    ),
                  ),

                const SizedBox(height: 24),

                // --- Navigate Back to Login ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Already have an account?", style: textTheme.bodyMedium?.copyWith(color: hintTextColor)),
                    TextButton(
                      // Navigate back to the LoginPage instance if it exists, otherwise push new
                      onPressed: _isLoading ? null : () => Navigator.maybePop(context),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          color: buttonColor, // Use button color for emphasis
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}