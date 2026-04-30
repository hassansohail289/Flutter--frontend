import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Naya import
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MaterialApp(home: VoiceClonerScreen(), debugShowCheckedModeBanner: false));
}

class VoiceClonerScreen extends StatefulWidget {
  const VoiceClonerScreen({super.key});

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
  
  // Ab URL hardcoded nahi hai, .env se aa raha hai
  final String baseUrl = dotenv.env['BASE_URL'] ?? "";

  @override
  void initState() {
    super.initState();
    _fetchSpeakers();
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
      print(e);
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
            path: path
          );
          setState(() {
            _isRecording = true;
            _outputAudioUrl = null;
          });
        }
      } catch (e) {
        print(e);
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
      appBar: AppBar(title: const Text("AI Project Hub - Voice Clone"), elevation: 0),
      body: Column(
        children: [
          const SizedBox(height: 20),
          const Text("Select Speaker", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
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
                      child: Container(
                        width: 110,
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: 2),
                          boxShadow: isSelected ? [BoxShadow(color: Colors.blue.withOpacity(0.2), blurRadius: 5)] : [],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(40),
                              child: Image.network(
                                "$baseUrl/${s['photo']}",
                                width: 60, height: 60, fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Icon(Icons.person, size: 40),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(s['name'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
          const Spacer(),
          if (_isProcessing)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text("Processing Voice AI...", style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          if (_outputAudioUrl != null && !_isProcessing)
            Container(
              padding: const EdgeInsets.all(15),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill, color: Colors.green, size: 30),
                  const SizedBox(width: 10),
                  const Expanded(child: Text("Clone Playing...", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
                  IconButton(
                    icon: const Icon(Icons.replay, color: Colors.green),
                    onPressed: () => _audioPlayer.play(UrlSource(_outputAudioUrl!)),
                  )
                ],
              ),
            ),
          const SizedBox(height: 30),
          GestureDetector(
            onTap: _handleRecording,
            child: CircleAvatar(
              radius: 60,
              backgroundColor: _isRecording ? Colors.red : Colors.blue,
              child: Icon(_isRecording ? Icons.stop : Icons.mic, color: Colors.white, size: 50),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            _isRecording ? "Recording... Tap to Stop" : "Tap to Record", 
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
          ),
          const SizedBox(height: 60),
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