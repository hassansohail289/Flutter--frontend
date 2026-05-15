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
import 'voice_cloner_screen.dart';
import 'personal_voice_screen.dart';

class CloningEngineScreen extends StatefulWidget {
  final String userEmail;
  const CloningEngineScreen({super.key, required this.userEmail});

  @override
  State<CloningEngineScreen> createState() => _CloningEngineScreenState();
}

class _CloningEngineScreenState extends State<CloningEngineScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isLoading = true;
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
      final response = await http.get(Uri.parse('$baseUrl/get-my-voices?email=${widget.userEmail}'));
      if (response.statusCode == 200) {
        setState(() {
          _speakers = jsonDecode(response.body)['voices'];
          if (_speakers.isNotEmpty) _selectedSpeaker = _speakers[0];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error fetching speakers: $e");
    }
  }

  Future<void> _deleteSpeaker(Map<String, dynamic> s) async {
    String speakerName = s['speaker_name'] ?? s['name'] ?? "";
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/delete-my-voice'),
        body: jsonEncode({
          'email': widget.userEmail,
          'speaker_name': speakerName,
        }),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Voice deleted successfully"), backgroundColor: Colors.green));
        _fetchSpeakers();
      }
    } catch (e) {
      debugPrint("Delete error: $e");
    }
  }

  void _showDeleteDialog(Map<String, dynamic> s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Clone?"),
        content: const Text("Are you sure you want to delete this registered voice?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSpeaker(s);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAudioToPhone(String url) async {
    try {
      Directory? directory;
      String fileName = "MyClone_${DateTime.now().millisecondsSinceEpoch}.wav";
      
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
        await Share.shareXFiles([XFile(savePath)], text: 'My AI Voice Clone from Personal Studio');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved to Downloads: $fileName"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint("Download Error: $e");
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
      request.headers.addAll({"ngrok-skip-browser-warning": "69420"});
      request.fields['mode'] = 'file_input';
      request.fields['speaker'] = _selectedSpeaker!['speaker_name'] ?? _selectedSpeaker!['name'] ?? "";
      request.fields['user_email'] = widget.userEmail;

      var stream = http.ByteStream(audioFile.openRead());
      var length = await audioFile.length();
      var multipartFile = http.MultipartFile('audio_file', stream, length, filename: audioFile.path.split('/').last);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final double sw = size.width;
    final double sh = size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Colors.black, size: sw * 0.05),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Personal Voice Cloning",
                style: GoogleFonts.sora(fontSize: sw * 0.045, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: sw * 0.04),
            child: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'logout') _handleLogout();
              },
              child: Center(
                child: CircleAvatar(
                  radius: sw * 0.045,
                  backgroundColor: const Color(0xFF6366F1),
                  child: Text(_userInitial, style: GoogleFonts.sora(color: Colors.white, fontSize: sw * 0.035, fontWeight: FontWeight.bold)),
                ),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: const Color(0xFF64748B), size: sw * 0.05),
                      SizedBox(width: sw * 0.02),
                      Text("Logout", style: GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: sw * 0.035)),
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
                padding: EdgeInsets.all(sw * 0.06),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("SELECT YOUR VOICE",
                        style: GoogleFonts.sora(fontSize: sw * 0.028, fontWeight: FontWeight.w600, letterSpacing: 1.5, color: const Color(0xFF94A3B8))),
                    SizedBox(height: sh * 0.02),
                    SizedBox(
                      height: sh * 0.18,
                      child: _isLoading 
                          ? const Center(child: CircularProgressIndicator())
                          : _speakers.isEmpty
                              ? Center(
                                  child: RichText(
                                    textAlign: TextAlign.center,
                                    text: TextSpan(
                                      style: GoogleFonts.dmSans(color: const Color(0xFF64748B), fontSize: sw * 0.035),
                                      children: [
                                        const TextSpan(text: "To view your clone voice(s) press "),
                                        TextSpan(text: "Register Clone", style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _speakers.length,
                                  itemBuilder: (context, index) {
                                    final s = _speakers[index];
                                    bool isSelected = (_selectedSpeaker?['speaker_name'] ?? _selectedSpeaker?['name']) == (s['speaker_name'] ?? s['name']);
                                    return GestureDetector(
                                      onTap: () => setState(() => _selectedSpeaker = s),
                                      onLongPress: () => _showDeleteDialog(s),
                                      child: _buildSpeakerCard(s, isSelected, sw, sh),
                                    );
                                  },
                                ),
                    ),
                    SizedBox(height: sh * 0.04),
                    if (_isProcessing) _buildProcessingCard(sw, sh),
                    if (_outputAudioUrl != null && !_isProcessing) _buildWaveformCard(sw, sh),
                    if (_speakers.isNotEmpty) ...[
                      SizedBox(height: sh * 0.08),
                      _buildRecordInterface(sw, sh),
                      SizedBox(height: sh * 0.02),
                      Center(
                        child: Text(
                          "In order to delete your clone, hold the icon for a few seconds",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(fontSize: sw * 0.028, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomNav(sw),
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
        border: Border.all(color: isSelected ? const Color(0xFF6366F1) : Colors.transparent, width: 2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(sw * 0.08),
            child: Image.network(
              "$baseUrl/${s['photo'] ?? s['photo_path']}",
              width: sw * 0.13,
              height: sw * 0.13,
              fit: BoxFit.cover,
              errorBuilder: (c, e, st) => Text("👤", style: TextStyle(fontSize: sw * 0.06)),
            ),
          ),
          SizedBox(height: sh * 0.01),
          Text(s['speaker_name'] ?? s['name'] ?? "Voice",
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(fontSize: sw * 0.03, fontWeight: FontWeight.bold, color: const Color(0xFF334155))),
          if (isSelected)
            Container(
              margin: EdgeInsets.only(top: sh * 0.005),
              padding: EdgeInsets.symmetric(horizontal: sw * 0.015, vertical: sh * 0.002),
              decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(6)),
              child: Text("SELECTED", style: GoogleFonts.sora(fontSize: sw * 0.02, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1))),
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
                  Text("Download", style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green)),
                  const SizedBox(width: 45),
                  Text("Play", style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
                  const SizedBox(width: 15),
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
                    icon: Container(
                      padding: EdgeInsets.all(sw * 0.02),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), shape: BoxShape.circle),
                      child: Icon(Platform.isIOS ? Icons.ios_share : Icons.download_rounded, color: Colors.green, size: sw * 0.05),
                    ),
                  ),
                  const SizedBox(width: 15),
                  IconButton(
                    onPressed: () => _audioPlayer.play(UrlSource(_outputAudioUrl!)),
                    icon: Container(
                      padding: EdgeInsets.all(sw * 0.02),
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)])),
                      child: Icon(Icons.play_arrow, color: Colors.white, size: sw * 0.05),
                    ),
                  ),
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
          Text("Cloning your voice...", style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: sw * 0.035)),
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
                boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 20, spreadRadius: 5)],
              ),
              child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: sw * 0.09),
            ),
          ),
          SizedBox(height: sh * 0.02),
          Text(_isRecording ? "Stop Recording" : "Tap to Record & Clone", style: GoogleFonts.dmSans(fontSize: sw * 0.035, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
        ],
      ),
    );
  }

  Widget _buildBottomNav(double sw) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.mic, "Clone", false, sw, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => VoiceClonerScreen(userEmail: widget.userEmail)));
          }),
          _navItem(Icons.mic, "Personal Clone", true, sw, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CloningEngineScreen(userEmail: widget.userEmail)));
          }),
          _navItem(Icons.person_outline, "Register Clone", false, sw, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => PersonalVoiceScreen(userEmail: widget.userEmail)));
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
          Text(label, style: GoogleFonts.dmSans(fontSize: sw * 0.025, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8))),
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