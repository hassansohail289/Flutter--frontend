import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'login_screen.dart';
import 'personal_voice_screen.dart';
import 'cloning_engine_screen.dart';

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
      debugPrint("Error fetching speakers: $e");
    }
  }

  Future<void> _saveAudioToPhone(String url) async {
    try {
      Directory? directory;
      String fileName = "Clone_${DateTime.now().millisecondsSinceEpoch}.wav";
      
      if (Platform.isAndroid) {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else {
        directory = await getTemporaryDirectory();
      }

      String savePath = "${directory!.path}/$fileName";

      Dio dio = Dio();
      await dio.download(url, savePath);

      if (Platform.isIOS) {
        await Share.shareXFiles([XFile(savePath)], text: 'Check out my AI Voice Clone!');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved to Downloads: $fileName"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Download Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to save audio"), backgroundColor: Colors.red),
      );
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
        debugPrint("Recording error: $e");
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
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      debugPrint("Upload Exception: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double screenWidth = size.width;
    final double screenHeight = size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Voice Clone",
                style: GoogleFonts.sora(
                    fontSize: screenWidth * 0.045,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A))),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: screenWidth * 0.04),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') _handleLogout();
              },
              child: Center(
                child: CircleAvatar(
                  radius: screenWidth * 0.045,
                  backgroundColor: const Color(0xFF6366F1),
                  child: Text(_userInitial,
                      style: GoogleFonts.sora(
                          color: Colors.white,
                          fontSize: screenWidth * 0.035,
                          fontWeight: FontWeight.bold)),
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
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(screenWidth * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("SELECT SPEAKER",
                        style: GoogleFonts.sora(
                            fontSize: screenWidth * 0.028,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.5,
                            color: const Color(0xFF94A3B8))),
                    SizedBox(height: screenHeight * 0.02),
                    SizedBox(
                      height: screenHeight * 0.18,
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
                                  child: _buildSpeakerCard(s, isSelected, screenWidth, screenHeight),
                                );
                              },
                            ),
                    ),
                    SizedBox(height: screenHeight * 0.04),
                    if (_isProcessing) _buildProcessingCard(screenWidth, screenHeight),
                    if (_outputAudioUrl != null && !_isProcessing) _buildWaveformCard(screenWidth, screenHeight),
                    SizedBox(height: screenHeight * 0.08),
                    _buildRecordInterface(screenWidth, screenHeight),
                  ],
                ),
              ),
            ),
            _buildBottomNav(screenWidth),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerCard(Map<String, dynamic> s, bool isSelected, double sw, double sh) {
    return Container(
      width: sw * 0.25,
      margin: EdgeInsets.only(right: sw * 0.03),
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
            borderRadius: BorderRadius.circular(sw * 0.08),
            child: Image.network(
              "$baseUrl/${s['photo']}",
              width: sw * 0.13,
              height: sw * 0.13,
              fit: BoxFit.cover,
              errorBuilder: (c, e, st) => Text("🎬", style: TextStyle(fontSize: sw * 0.06)),
            ),
          ),
          SizedBox(height: sh * 0.01),
          Text(s['name'],
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                  fontSize: sw * 0.03, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
          if (isSelected)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
              child: Text("SELECTED",
                  style: GoogleFonts.sora(
                      fontSize: sw * 0.02, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1))),
            )
        ],
      ),
    );
  }

  Widget _buildWaveformCard(double sw, double sh) {
    return Container(
      padding: EdgeInsets.all(sw * 0.05),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("LAST RECORDING", style: GoogleFonts.sora(fontSize: sw * 0.025, fontWeight: FontWeight.bold, color: Colors.grey)),
              Row(
                children: [
                  Text("Download", style: GoogleFonts.dmSans(fontSize: sw * 0.030, fontWeight: FontWeight.w600, color: Colors.green)),
                   SizedBox(width: 25),
                  Text("Play", style: GoogleFonts.dmSans(fontSize: sw * 0.030, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
                   SizedBox(width: 15),
                ],
              ),
            ],
          ),
          SizedBox(height: sh * 0.015),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.graphic_eq, color: const Color(0xFF6366F1), size: sw * 0.08),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _saveAudioToPhone(_outputAudioUrl!),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(Platform.isIOS ? Icons.ios_share : Icons.download_rounded, color: Colors.green, size: sw * 0.05),
                    ),
                  ),
                  const SizedBox(width: 15),
                  IconButton(
                    onPressed: () => _audioPlayer.play(UrlSource(_outputAudioUrl!)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                      child:  Icon(Icons.play_arrow, color: Colors.white, size: sw * 0.05),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildProcessingCard(double sw, double sh) {
    return Center(
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFF6366F1)),
          SizedBox(height: sh * 0.02),
          Text("Processing Voice AI...", style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: sw * 0.035)),
        ],
      ),
    );
  }

  Widget _buildRecordInterface(double sw, double sh) {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _handleRecording,
            child: Container(
              height: sw * 0.2,
              width: sw * 0.2,
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
              child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: sw * 0.09),
            ),
          ),
          SizedBox(height: sh * 0.02),
          Text(_isRecording ? "Stop Recording" : "Tap to Record",
              style: GoogleFonts.dmSans(
                  fontSize: sw * 0.035, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }

  Widget _buildBottomNav(double sw) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
          color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.mic, "Clone", true, sw, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => VoiceClonerScreen(userEmail: widget.userEmail)),
            );
          }),
          _navItem(Icons.mic, "Personal Clone", false, sw, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => CloningEngineScreen(userEmail: widget.userEmail)),
            );
          }),
          _navItem(Icons.person_outline, "Register clone", false, sw, () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => PersonalVoiceScreen(userEmail: widget.userEmail)),
            );
          }),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive, double sw, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8), size: sw * 0.06),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.dmSans(
                fontSize: sw * 0.025,
                fontWeight: FontWeight.bold,
                color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8),
              )),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _recorder.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}