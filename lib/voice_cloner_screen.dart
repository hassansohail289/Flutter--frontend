import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:io';
import 'login_screen.dart';

class VoiceClonerScreen extends StatefulWidget {
  final String userEmail;
  const VoiceClonerScreen({super.key, required this.userEmail});

  @override
  State<VoiceClonerScreen> createState() => _VoiceClonerScreenState();
}

class _VoiceClonerScreenState extends State<VoiceClonerScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isProcessing = false;
  List<dynamic> _speakers = [];
  Map<String, dynamic>? _selectedSpeaker;
  String? _outputAudioUrl;

  final String baseUrl = dotenv.env['BASE_URL'] ?? "";

  @override
  void initState() {
    super.initState();
    _fetchSpeakers();
  }

  String get _userInitial {
    if (widget.userEmail.isEmpty) return "U";
    return widget.userEmail[0].toUpperCase();
  }

  void _handleLogout() {
    print("User logged out successfully.");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  Future<void> _fetchSpeakers() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/registered-speakers'));
      if (response.statusCode == 200) {
        setState(() {
          _speakers = jsonDecode(response.body)['speakers'];
          if (_speakers.isNotEmpty) _selectedSpeaker = _speakers[0];
        });
      }
    } catch (e) {
      print("Error fetching speakers: $e");
    }
  }

  Future<void> _handleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });
      if (path != null && _selectedSpeaker != null) {
        _uploadToServer(File(path));
      }
    } else {
      try {
        if (await _recorder.hasPermission()) {
          final directory = await getApplicationDocumentsDirectory();
          final String path = '${directory.path}/clone_sample.wav';
          await _recorder.start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              bitRate: 128000,
              sampleRate: 44100,
            ),
            path: path,
          );
          setState(() {
            _isRecording = true;
            _outputAudioUrl = null;
          });
        }
      } catch (e) {
        print("Recording error: $e");
      }
    }
  }

  Future<void> _uploadToServer(File audioFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/voice-lab/process'));
      request.fields['mode'] = 'file_input';
      request.fields['speaker'] = _selectedSpeaker!['name'];

      var stream = http.ByteStream(audioFile.openRead());
      var length = await audioFile.length();
      var multipartFile = http.MultipartFile(
        'audio_file',
        stream,
        length,
        filename: audioFile.path.split('/').last,
      );

      request.files.add(multipartFile);
      var response = await request.send();
      var responseData = await response.stream.bytesToString();

      setState(() => _isProcessing = false);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseData);
        String fullUrl = "$baseUrl${decoded['audio_url']}";
        setState(() => _outputAudioUrl = fullUrl);
        await _audioPlayer.play(UrlSource(fullUrl));
      } else {
        print("Backend Error: $responseData");
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      print("Upload Exception: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Good morning 👋",
                style: GoogleFonts.dmSans(fontSize: 12, color: const Color(0xFF64748B))),
            Text("Voice Clone",
                style: GoogleFonts.sora(
                    fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') _handleLogout();
              },
              child: Center(
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF6366F1),
                  child: Text(_userInitial,
                      style: GoogleFonts.sora(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      const Icon(Icons.logout, color: Color(0xFF64748B), size: 20),
                      const SizedBox(width: 10),
                      Text("Logout", style: GoogleFonts.dmSans(fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("SELECT SPEAKER",
                      style: GoogleFonts.sora(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: const Color(0xFF94A3B8))),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 140,
                    child: _speakers.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _speakers.length,
                            itemBuilder: (context, index) {
                              final s = _speakers[index];
                              bool isSelected = _selectedSpeaker?['name'] == s['name'];
                              return GestureDetector(
                                onTap: () => setState(() => _selectedSpeaker = s),
                                child: _buildSpeakerCard(s, isSelected),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 32),
                  if (_isProcessing) _buildProcessingCard(),
                  if (_outputAudioUrl != null && !_isProcessing) _buildWaveformCard(),
                  const SizedBox(height: 80),
                  _buildRecordInterface(),
                ],
              ),
            ),
          ),
          _buildBottomNav(),
        ],
      ),
    );
  }

  Widget _buildSpeakerCard(Map<String, dynamic> s, bool isSelected) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: isSelected ? const Color(0xFF6366F1) : Colors.transparent, width: 2),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: Image.network(
              "$baseUrl/${s['photo']}",
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (c, e, st) => const Text("🎬", style: TextStyle(fontSize: 24)),
            ),
          ),
          const SizedBox(height: 8),
          Text(s['name'],
              style: GoogleFonts.dmSans(
                  fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
          if (isSelected)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
              child: Text("SELECTED",
                  style: GoogleFonts.sora(
                      fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1))),
            )
        ],
      ),
    );
  }

  Widget _buildWaveformCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("LAST RECORDING",
              style: GoogleFonts.sora(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Icon(Icons.graphic_eq, color: Color(0xFF6366F1), size: 30),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _audioPlayer.play(UrlSource(_outputAudioUrl!)),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildProcessingCard() {
    return const Center(
      child: Column(
        children: [
          CircularProgressIndicator(color: Color(0xFF6366F1)),
          SizedBox(height: 12),
          Text("Processing Voice AI...", style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRecordInterface() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _handleRecording,
            child: Container(
              height: 80,
              width: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 5)
                ],
              ),
              child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 35),
            ),
          ),
          const SizedBox(height: 16),
          Text(_isRecording ? "Stop Recording" : "Tap to Record",
              style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.mic, "Clone", true),
          _navItem(Icons.history, "History", false),
          _navItem(Icons.person_outline, "Profile", false),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8)),
        const SizedBox(height: 4),
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8))),
      ],
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}