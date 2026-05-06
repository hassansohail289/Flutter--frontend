import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'login_screen.dart'; // Ab login screen ko load karega

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MaterialApp(
    home: LoginScreen(), // Sab se pehle login dikhao
    debugShowCheckedModeBanner: false,
  ));
}