import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'dart:convert';
import 'package:googleapis/texttospeech/v1.dart' as tts;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");
  final visionApiKey = dotenv.env['SPEAK_CLOTHES_API'];
  final ttsApiKey = dotenv.env['SPEAK_CLOTHES_API'];

  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(
    MaterialApp(
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          color: Color.fromARGB(255, 230, 211, 34),
        ),
      ),
      home: CameraScreen(
        camera: firstCamera,
        visionApiKey: visionApiKey,
        ttsApiKey: ttsApiKey,
      ),
    ),
  );
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    Key? key,
    required this.camera,
    required this.visionApiKey,
    required this.ttsApiKey,
  }) : super(key: key);

  final CameraDescription camera;
  final String? visionApiKey;
  final String? ttsApiKey;

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  late FlutterTts flutterTts;
  String _analysisResult = '';
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();
    flutterTts = FlutterTts();

    Timer.periodic(Duration(seconds: 7), (_) {
      _takePictureAndProcess();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _takePictureAndProcess() async {
    if (!_controller.value.isInitialized || _isDetecting) {
      return;
    }

    setState(() {
      _isDetecting = true;
    });

    try {
      final XFile picture = await _controller.takePicture();
      await _processImage(picture);
    } catch (e) {
      print("Error taking picture: $e");
    } finally {
      setState(() {
        _isDetecting = false;
      });
    }
  }

  Future<void> _processImage(XFile picture) async {
    final apiKey = widget.visionApiKey;

    if (apiKey == null) {
      print('API key not found in environment variables.');
      return;
    }

    final client = auth.clientViaApiKey(apiKey);
    final visionApi = vision.VisionApi(client);

    final imageBytes = await picture.readAsBytes();
    final imageContent = base64Encode(imageBytes);

    final request = vision.BatchAnnotateImagesRequest.fromJson({
      'requests': [
        {
          'image': {'content': imageContent},
          'features': [
            {'type': 'LABEL_DETECTION'}
          ],
        },
      ],
    });

    try {
      final response = await visionApi.images.annotate(request);
      if (response.responses != null && response.responses!.isNotEmpty) {
        final labelAnnotations = response.responses!.first.labelAnnotations;
        if (labelAnnotations != null && labelAnnotations.isNotEmpty) {
          final label = labelAnnotations.first.description;
          print('Detected label: $label');
          await _speakText('Detected label: $label');

          setState(() {
            _analysisResult = 'Detected label: $label';
          });

          await flutterTts.setLanguage('en-US');
          await flutterTts.setSpeechRate(0.4);
          await flutterTts.setVolume(1.0);
          await flutterTts.speak('Detected label: $label');
        }
      }
    } catch (e) {
      print("Error taking picture: $e");
      setState(() {
        _analysisResult = 'Error processing image';
      });
    }
  }

  Future<void> _speakText(String text) async {
    final apiKey = widget.ttsApiKey;

    if (apiKey == null) {
      print('Text-to-Speech API key not found in environment variables.');
      return;
    }

    final client = auth.clientViaApiKey(apiKey);
    final ttsApi = tts.TexttospeechApi(client);

    final synthesisInput = tts.SynthesisInput(text: text);
    final voiceSelection =
        tts.VoiceSelectionParams(languageCode: 'en-US', ssmlGender: 'Female');
    final audioConfig = tts.AudioConfig(audioEncoding: 'MP3');

    final ttsRequest = tts.SynthesizeSpeechRequest(
      input: synthesisInput,
      voice: voiceSelection,
      audioConfig: audioConfig,
    );

    final ttsResponse = await ttsApi.text.synthesize(ttsRequest);

    // TODO: ttsResponse에서 음성 파일을 재생하거나 저장할 수 있음
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Speak Clothes')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                CameraPreview(_controller),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Text(
                    _isDetecting ? 'Detecting...' : _analysisResult,
                    style: TextStyle(
                        fontSize: 16,
                        color: const Color.fromARGB(255, 150, 5, 5)),
                  ),
                ),
              ],
            );
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
    );
  }
}
