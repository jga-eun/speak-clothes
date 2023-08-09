import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'dart:convert';
import 'package:googleapis/texttospeech/v1.dart' as tts;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // .env 파일에서 API 키 로드
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
    super.key,
    required this.camera,
    required this.visionApiKey,
    required this.ttsApiKey,
  });

  final CameraDescription camera;
  final String? visionApiKey;
  final String? ttsApiKey;

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  File? _imageFile;
  late FlutterTts flutterTts;
  String _analysisResult = '';

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();
    _loadImage();
    flutterTts = FlutterTts();
  }

  void _loadImage() async {
    final imageFile =
        await rootBundle.load('assets/speak_clothes_top_icon.png');
    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/speak_clothes_top_icon.png';
    final bytes = imageFile.buffer.asUint8List();
    await File(tempPath).writeAsBytes(bytes);
    setState(() {
      _imageFile = File(tempPath);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (!_controller.value.isInitialized) {
      return;
    }
    try {
      final XFile picture = await _controller.takePicture();
      await _processImage(picture);
    } catch (e) {
      print("Error taking picture: $e");
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
          await flutterTts.setSpeechRate(0.8);
          await flutterTts.setVolume(1.0);
          await flutterTts.speak('Detected label: $label');

          double screenWidth = MediaQuery.of(context).size.width;
          double objectPositionX = screenWidth / 2;
          double distanceThreshold = 20;
          bool imageMatched = false;

          while (!imageMatched) {
            String instructionText;
            if ((objectPositionX - screenWidth / 2).abs() < distanceThreshold) {
              imageMatched = true;
              await _takePicture();
              instructionText = "촬영을 시작하겠습니다.";
            } else if (objectPositionX > screenWidth / 2) {
              await _speakText("왼쪽으로 이동하세요.");
              instructionText = "왼쪽으로 이동하세요.";
            } else {
              await _speakText("오른쪽으로 이동하세요.");
              instructionText = "오른쪽으로 이동하세요.";
            }

            setState(() {
              _analysisResult = instructionText;
            });
          }
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
        tts.VoiceSelectionParams(languageCode: 'en-US', ssmlGender: 'FEMALE');
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
      appBar: AppBar(title: const Text('Camera')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_imageFile != null) {
              return Stack(
                children: [
                  CameraPreview(_controller),
                  Positioned.fill(child: Image.file(_imageFile!)),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Text(
                      _analysisResult,
                      style: TextStyle(
                          fontSize: 16,
                          color: const Color.fromARGB(255, 150, 5, 5)),
                    ),
                  ),
                ],
              );
            } else {
              return CameraPreview(_controller);
            }
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture,
        child: Icon(Icons.camera),
      ),
    );
  }
}
