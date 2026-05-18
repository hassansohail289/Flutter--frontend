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
import 'package:flutter/services.dart' show rootBundle;
import 'login_screen.dart';
import 'cloning_engine_screen.dart';
import 'voice_cloner_screen.dart';

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

  final List<String> _defaultAvatars = [
    'assets/avatars/avatar1.png',
    'assets/avatars/avatar2.png',
    'assets/avatars/avatar3.png',
    'assets/avatars/avatar4.png',
    'assets/avatars/avatar5.png',
    'assets/avatars/avatar6.png',
    'assets/avatars/avatar7.png',
    'assets/avatars/avatar8.png',
    'assets/avatars/avatar9.png',
    'assets/avatars/avatar10.png',
    'assets/avatars/avatar11.png',
  ];

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

  void _playSpecificSegment(String segmentData) async {
    try {
      if (!segmentData.contains("Audio: ")) return;

      String rawPath = segmentData.split("Audio: ").last.trim();
      String fileName = rawPath.replaceAll('\\', '/').split('/').last;

      if (fileName.isEmpty) return;

      String cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      
      String audioUrl = "$cleanBaseUrl/get-audio-segment/$fileName";

      debugPrint("Hitting Custom Endpoint: $audioUrl");

      setState(() => _isProcessing = true);

      final response = await http.get(
        Uri.parse(audioUrl),
        headers: {"ngrok-skip-browser-warning": "69420"},
      );

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final localFile = File('${directory.path}/temp_seg_${DateTime.now().millisecondsSinceEpoch}.wav');
        await localFile.writeAsBytes(response.bodyBytes);

        await _audioPlayer.stop();
        await _audioPlayer.play(DeviceFileSource(localFile.path));
      } else {
        debugPrint("Server Error: ${response.statusCode}");
      }
      setState(() => _isProcessing = false);
    } catch (e) {
      setState(() => _isProcessing = false);
      debugPrint("Play Error: $e");
    }
  }

  void _showSegmentSelectionSheet() {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    dynamic longestSegment;
    double maxDuration = -1.0;

    for (var segment in _diarizationData) {
      try {
        String str = segment.toString();
        RegExp regExp = RegExp(r"(\d+\.\d+)s - (\d+\.\d+)s");
        var match = regExp.firstMatch(str);
        if (match != null) {
          double start = double.parse(match.group(1)!);
          double end = double.parse(match.group(2)!);
          double duration = end - start;
          if (duration > maxDuration) {
            maxDuration = duration;
            longestSegment = segment;
          }
        }
      } catch (e) {
        debugPrint("Error calculating duration: $e");
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(horizontal: sw * 0.06, vertical: sh * 0.03),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: sw * 0.1, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            SizedBox(height: sh * 0.02),
            Text("REVIEW YOUR VOICE CLONE", style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: sw * 0.035, color: const Color(0xFF0F172A))),
            SizedBox(height: sh * 0.03),
            if (longestSegment != null)
              Container(
                padding: EdgeInsets.symmetric(vertical: sh * 0.02, horizontal: sw * 0.04),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Play", style: GoogleFonts.dmSans(fontSize: sw * 0.03, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                        SizedBox(height: sh * 0.01),
                        _smallActionButton(Icons.play_arrow_rounded, const Color(0xFF6366F1), () {
                          _playSpecificSegment(longestSegment.toString());
                        }),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Approve", style: GoogleFonts.dmSans(fontSize: sw * 0.03, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                        SizedBox(height: sh * 0.01),
                        _smallActionButton(Icons.check_rounded, Colors.green, () {
                          _audioPlayer.stop();
                          Navigator.pop(context);
                          _showMediaSourceSelection(longestSegment.toString());
                        }),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Discard", style: GoogleFonts.dmSans(fontSize: sw * 0.03, fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                        SizedBox(height: sh * 0.01),
                        _smallActionButton(Icons.close_rounded, Colors.redAccent, () {
                          _audioPlayer.stop();
                          Navigator.pop(context);
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            SizedBox(height: sh * 0.02),
          ],
        ),
      ),
    );
  }

  void _showMediaSourceSelection(String segment) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: EdgeInsets.all(sw * 0.06),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("CHOOSE CLONE IMAGE", style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: sw * 0.038, color: const Color(0xFF0F172A))),
            SizedBox(height: sh * 0.03),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.face_rounded, color: Color(0xFF6366F1)),
              ),
              title: Text("Choose Default Avatar", style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, fontSize: sw * 0.038)),
              subtitle: Text("Select from pre-designed system avatars", style: GoogleFonts.dmSans(color: const Color(0xFF64748B), fontSize: sw * 0.03)),
              onTap: () {
                Navigator.pop(context);
                _showAvatarPickerGrid(segment);
              },
            ),
            Divider(color: Colors.grey[200]),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.photo_library_rounded, color: Colors.green),
              ),
              title: Text("Choose Photo from Gallery", style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, fontSize: sw * 0.038)),
              subtitle: Text("Browse and upload a photo from your phone", style: GoogleFonts.dmSans(color: const Color(0xFF64748B), fontSize: sw * 0.03)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
                if (photo != null) {
                  _showNameRegistrationDialog(segment, File(photo.path));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAvatarPickerGrid(String segment) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      builder: (context) => Container(
        padding: EdgeInsets.all(sw * 0.06),
        constraints: BoxConstraints(maxHeight: sh * 0.6),
        child: Column(
          children: [
            Container(width: sw * 0.1, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            SizedBox(height: sh * 0.02),
            Text("SELECT SYSTEM AVATAR", style: GoogleFonts.sora(fontWeight: FontWeight.bold, fontSize: sw * 0.035)),
            SizedBox(height: sh * 0.03),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _defaultAvatars.length,
                itemBuilder: (context, index) {
                  return GestureDetector(
                    onTap: () async {
                      Navigator.pop(context);
                      File avatarFile = await _convertAssetToFile(_defaultAvatars[index]);
                      _showNameRegistrationDialog(segment, avatarFile);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(19),
                        child: Image.asset(_defaultAvatars[index], fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<File> _convertAssetToFile(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/picked_avatar_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file;
  }

  void _showNameRegistrationDialog(String segment, File imageFile) {
    final sw = MediaQuery.of(context).size.width;
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
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
              _finalizeEnrollment(segment, imageFile, nameController.text);
            },
            child: Text("Register", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: const Color(0xFF6366F1), fontSize: sw * 0.035)),
          )
        ],
      ),
    );
  }

  Widget _smallActionButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Clone Registered Successfully, Tap personal clone to use!!"), backgroundColor: Colors.green));
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
            Text("Register Personal Voice(s)", style: GoogleFonts.dmSans(fontSize: sw * 0.03, color: const Color(0xFF64748B))),
            Text("Personal Voice Cloning", style: GoogleFonts.sora(fontSize: sw * 0.045, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
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
                padding: EdgeInsets.symmetric(horizontal: sw * 0.06, vertical: sh * 0.02),
                child: Column(
                  children: [
                    SizedBox(height: sh * 0.04),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.mic_none_rounded, size: sw * 0.2, color: Colors.grey[300]),
                          SizedBox(height: sh * 0.02),
                          Text("Tap the Record button and read the paragraph below aloud. Once you finish reading, tap the Stop button.", style: GoogleFonts.dmSans(color: const Color(0xFF64748B), fontSize: sw * 0.035)),
                          SizedBox(height: sh * 0.03),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: sw * 0.02),
                            child: Text(
                              "\"I enjoy reading thoughtful stories, exploring new ideas, and having meaningful conversations with people from different backgrounds and experiences.\"",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.dmSans(
                                color: const Color(0xFF0F172A),
                                fontSize: sw * 0.038,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: sh * 0.06),
                    if (_isProcessing) _buildProcessingCard(sw, sh),
                    SizedBox(height: sh * 0.04),
                    _buildRecordInterface(sw, sh),
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
          _navItem(Icons.mic, "Clone", false, sw, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => VoiceClonerScreen(userEmail: widget.userEmail)));
          }),
          _navItem(Icons.mic, "Personal Clone", false, sw, () {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => CloningEngineScreen(userEmail: widget.userEmail)));
          }),
          _navItem(Icons.person_outline, "Register Clone", true, sw, () {
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