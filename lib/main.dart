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
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
    Key? key,
    required this.camera,
    required this.visionApiKey,
    required this.ttsApiKey,
  }): super(key: key);

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

  Future<String> _translateText(String text) async {
    final apiKey = dotenv.env['SPEAK_CLOTHES_API'];

    if (apiKey == null) {
      print('Translation API key not found in environment variables.');
      return text; // Return the original text if API key is not available
    }

    final url = Uri.parse('https://translation.googleapis.com/language/translate/v2');
    final response = await http.post(url, body: {
      'key': apiKey,
      'source': 'en',
      'target': 'ko',
      'q': text,
    });

    if (response.statusCode == 200) {
      final translatedText = json.decode(response.body)['data']['translations'][0]['translatedText'];
      return translatedText;
    } else {
      print('텍스트 번역 중 오류 발생: ${response.body}');
      return text;
    }
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
    final imageBytes = await File(picture.path).readAsBytes();

    if (apiKey == null) {
      print('환경 변수에서 API 키를 찾을 수 없습니다.');
      return;
    }

    final client = auth.clientViaApiKey(apiKey);
    final visionApi = vision.VisionApi(client);

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
          final colorInfo = await _getColorInfo(label!, picture);
          print('이미지 분석 결과: $label\n색상: $colorInfo');
          final translatedLabel = await _translateText(label!);
          await _speakText('이미지 분석 결과: $translatedLabel\n색상: $colorInfo');

          setState(() {
            _analysisResult = '이미지 분석 결과: $translatedLabel\n색상: $colorInfo';
          });

          await flutterTts.setLanguage('en-US');
          await flutterTts.setSpeechRate(0.4);
          await flutterTts.setVolume(1.0);
          await flutterTts.speak('이미지 분석 결과: $translatedLabel\n색상: $colorInfo');
        }
      }
    } catch (e) {
      print("사진 처리 중 오류 발생 $e");
      setState(() {
        _analysisResult = '이미지 처리 중 오류 발생';
      });
    }
  }

  Future<String> _getColorInfo(String label, XFile picture) async {
    // Vision API에서 가져온 이미지 색상 정보를 Firebase에 저장하고 가져오는 부분
    final firebaseAuth = FirebaseAuth.instance;
    final user = firebaseAuth.currentUser;
    if (user == null) {
      print('User not logged in.');
      return 'Unknown';
    }

    final visionApiKey = widget.visionApiKey;

    if (visionApiKey == null) {
      print('API key not found in environment variables.');
      return 'Unknown';
    }

    final client = auth.clientViaApiKey(visionApiKey);
    final visionApi = vision.VisionApi(client);

    final imageBytes = await File(picture.path!).readAsBytes();
    final imageContent = base64Encode(imageBytes);

    final request = vision.Image.fromJson({'content': imageContent});
    final response = await visionApi.images.annotate(
      vision.BatchAnnotateImagesRequest.fromJson({
        'requests': [
          {
            'image': request,
            'features': [
              {'type': 'IMAGE_PROPERTIES'}
            ],
          },
        ],
      }),
    );

    if (response.responses != null && response.responses!.isNotEmpty) {
      final color = response.responses!.first.imagePropertiesAnnotation
          ?.dominantColors?.colors?.first;
      if (color != null && color.color != null) {
        final r = (color.color!.red! * 255).toInt();
        final g = (color.color!.green! * 255).toInt();
        final b = (color.color!.blue! * 255).toInt();
        return 'RGB: $r, $g, $b';
      }
    }

    return 'Unknown';
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
                    _isDetecting ? '이미지 분석 중' : _analysisResult,
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
