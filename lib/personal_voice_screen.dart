import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'login_screen.dart';
import 'cloning_engine_screen.dart'; 

class PersonalVoiceScreen extends StatefulWidget {
  final String userEmail;
  const PersonalVoiceScreen({super.key, required this.userEmail});

  @override
  State<PersonalVoiceScreen> createState() => _PersonalVoiceScreenState();
}

class _PersonalVoiceScreenState extends State<PersonalVoiceScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ImagePicker _picker = ImagePicker();

  bool _isRecording = false;
  bool _isProcessing = false;
  List<dynamic> _diarizationData = [];
  String? _outputAudioUrl;

  final String baseUrl = dotenv.env['BASE_URL'] ?? "";

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

  Future<void> _handleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
        _diarizationData = [];
      });
      if (path != null) {
        _uploadForAnalysis(File(path));
      }
    } else {
      try {
        if (await _recorder.hasPermission()) {
          final directory = await getTemporaryDirectory();
          final String path = '${directory.path}/enroll_temp.wav';
          await _recorder.start(
            const RecordConfig(encoder: AudioEncoder.wav),
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

  Future<void> _uploadForAnalysis(File audioFile) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/analyze-live'));
      request.files.add(await http.MultipartFile.fromPath('audio_file', audioFile.path));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      final decoded = jsonDecode(responseData);

      setState(() => _isProcessing = false);

      if (response.statusCode == 200 && decoded['status'] == 'Done') {
        setState(() {
          _diarizationData = decoded['data'];
        });
        _showSegmentSelectionSheet();
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      debugPrint("Analysis Error: $e");
    }
  }

  void _showSegmentSelectionSheet() {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true, // Zaroori hai responsive height ke liye
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: EdgeInsets.all(sw * 0.06),
        constraints: BoxConstraints(maxHeight: sh * 0.7), // Tablet/Phone dono ke liye safe
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: sw * 0.1, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            SizedBox(height: sh * 0.02),
            Text("SELECT YOUR VOICE SEGMENT", style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: sw * 0.035, color: const Color(0xFF0F172A))),
            SizedBox(height: sh * 0.02),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _diarizationData.length,
                itemBuilder: (context, i) => Card(
                  elevation: 0,
                  color: const Color(0xFFF1F5F9),
                  margin: EdgeInsets.only(bottom: sh * 0.01),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: Icon(Icons.waves, color: const Color(0xFF6366F1), size: sw * 0.05),
                    title: Text(_diarizationData[i], style: GoogleFonts.dmSans(fontSize: sw * 0.03, fontWeight: FontWeight.w500)),
                    onTap: () {
                      Navigator.pop(context);
                      _pickDetailsAndEnroll(_diarizationData[i]);
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDetailsAndEnroll(String segment) async {
    final sw = MediaQuery.of(context).size.width;
    final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
    if (photo == null) return;

    TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Speaker Name", style: GoogleFonts.sora(fontSize: sw * 0.045, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: "Enter name...",
            filled: true,
            fillColor: const Color(0xFFF1F5F9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _finalizeEnrollment(segment, File(photo.path), nameController.text);
            },
            child: Text("Register", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: const Color(0xFF6366F1), fontSize: sw * 0.035)),
          )
        ],
      ),
    );
  }

  Future<void> _finalizeEnrollment(String segment, File photo, String name) async {
    setState(() => _isProcessing = true);
    try {
      RegExp regExp = RegExp(r"(\d+\.\d+)");
      var matches = regExp.allMatches(segment).toList();
      
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/confirm-personal-registration'));
      request.fields['name'] = name;
      request.fields['user_email'] = widget.userEmail;
      request.fields['enroll_start'] = matches[0].group(0)!;
      request.fields['enroll_end'] = matches[1].group(0)!;
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));

      var response = await request.send();
      setState(() => _isProcessing = false);

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Voice Registered Successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      debugPrint("Enrollment Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Register Personal Voice", style: GoogleFonts.dmSans(fontSize: sw * 0.03, color: const Color(0xFF64748B))),
            Text("Personal Studio", style: GoogleFonts.sora(fontSize: sw * 0.045, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
          ],
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: sw * 0.04),
            child: CircleAvatar(
              radius: sw * 0.045,
              backgroundColor: const Color(0xFF6366F1),
              child: Text(_userInitial, style: GoogleFonts.sora(color: Colors.white, fontSize: sw * 0.035, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: sw * 0.06, vertical: sh * 0.02),
                child: Column(
                  children: [
                    SizedBox(height: sh * 0.04),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.mic_none_rounded, size: sw * 0.2, color: Colors.grey[300]),
                          SizedBox(height: sh * 0.02),
                          Text("Record at least 5-10 seconds", style: GoogleFonts.dmSans(color: const Color(0xFF64748B), fontSize: sw * 0.035)),
                          Text("to extract high quality voice DNA", style: GoogleFonts.dmSans(color: const Color(0xFF64748B), fontSize: sw * 0.035)),
                        ],
                      ),
                    ),
                    SizedBox(height: sh * 0.06),
                    if (_isProcessing) _buildProcessingCard(sw, sh),
                    SizedBox(height: sh * 0.04),
                    _buildRecordInterface(sw, sh),
                    SizedBox(height: sh * 0.06),
                    _buildCloningEngineButton(sw, sh),
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

  Widget _buildCloningEngineButton(double sw, double sh) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CloningEngineScreen(userEmail: widget.userEmail),
          ),
        );
      },
      child: Container(
        padding: EdgeInsets.all(sw * 0.045),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: const Color(0xFF6366F1).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Clone Your Registered Voices", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold, fontSize: sw * 0.035)),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessingCard(double sw, double sh) {
    return Center(
      child: Column(
        children: [
          CircularProgressIndicator(color: const Color(0xFF6366F1), strokeWidth: sw * 0.01),
          SizedBox(height: sh * 0.02),
          Text("Analyzing Voice DNA...", style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, color: const Color(0xFF0F172A), fontSize: sw * 0.035)),
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
          Text(_isRecording ? "Stop Recording" : "Tap to Record", style: GoogleFonts.dmSans(fontSize: sw * 0.035, fontWeight: FontWeight.w500, color: const Color(0xFF64748B))),
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
          _navItem(Icons.mic, "Clone", true, sw),
          _navItem(Icons.history, "History", false, sw),
          _navItem(Icons.person_outline, "Profile", false, sw),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive, double sw) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8), size: sw * 0.06),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.dmSans(fontSize: sw * 0.025, fontWeight: FontWeight.bold, color: isActive ? const Color(0xFF6366F1) : const Color(0xFF94A3B8))),
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