import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'voice_cloner_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  final String baseUrl = dotenv.env['BASE_URL'] ?? "";

  Future<void> _handleSubmit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) return;
    setState(() => _isLoading = true);
    
    final endpoint = _isLogin ? '/login' : '/signup';
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": _emailController.text.trim(),
          "password": _passwordController.text.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (_isLogin) {
          // Navigation with the required email parameter
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(
              builder: (context) => VoiceClonerScreen(userEmail: _emailController.text.trim())
            )
          );
        } else {
          setState(() => _isLogin = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Account created! Please login."))
          );
        }
      } else {
        final result = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['detail'] ?? "Auth Failed"))
        );
      }
    } catch (e) {
      print("Connection error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 80),
              Center(
                child: Column(
                  children: [
                    Container(
                      height: 64, width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 24)],
                      ),
                      child: const Icon(Icons.mic, color: Colors.white, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text("VoiceClone", style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                    Text("AI-Powered Voice Synthesis", style: GoogleFonts.dmSans(fontSize: 13, color: const Color(0xFF64748B))),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(child: _tabButton("Login", _isLogin)),
                    Expanded(child: _tabButton("Sign Up", !_isLogin)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _inputField(_emailController, "Email address", Icons.email_outlined, false),
              const SizedBox(height: 14),
              _inputField(_passwordController, "Password", Icons.lock_outline, true),
              const SizedBox(height: 12),
              if (_isLogin) Align(alignment: Alignment.centerRight, child: Text("Forgot password?", style: GoogleFonts.dmSans(color: const Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.w500))),
              const SizedBox(height: 28),
              _isLoading 
                ? const CircularProgressIndicator()
                : InkWell(
                    onTap: _handleSubmit,
                    child: Container(
                      width: double.infinity, padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(colors: [Color(0xFF4F46E5), Color(0xFF8B5CF6)]),
                        boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.35), blurRadius: 20)],
                      ),
                      child: Center(child: Text(_isLogin ? "Continue →" : "Create Account", style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.bold))),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(String title, bool active) {
    return InkWell(
      onTap: () => setState(() => _isLogin = (title == "Login")),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: active ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(11), boxShadow: active ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : []),
        child: Center(child: Text(title, style: GoogleFonts.dmSans(color: active ? const Color(0xFF4F46E5) : const Color(0xFF64748B), fontWeight: active ? FontWeight.bold : FontWeight.normal))),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint, IconData icon, bool obs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: ctrl, obscureText: obs,
        decoration: InputDecoration(icon: Icon(icon, color: const Color(0xFFCBD5E1), size: 18), hintText: hint, border: InputBorder.none, hintStyle: GoogleFonts.dmSans(color: const Color(0xFFCBD5E1), fontSize: 14)),
      ),
    );
  }
}