import 'dart:async'; //비동기 사용하려고 import
import 'package:camera/camera.dart'; //카메라 package 사용하려고 import
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'dart:convert';
import 'package:googleapis/texttospeech/v1.dart' as tts; // Text-to-Speech API
import 'package:flutter_tts/flutter_tts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(
    MaterialApp(
      theme: ThemeData(
        //테마는 기본값
        appBarTheme: const AppBarTheme(
          color: Color.fromARGB(255, 230, 211, 34), // AppBar의 배경색 설정
        ),
      ),
      home: CameraScreen(
        camera: firstCamera, //카메라 여러개 있는 핸드폰 때문에 First라고 지정
      ),
    ),
  );
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.camera, //필수로 받아와야 하는 카메라 정보 저장 변수
  });

  final CameraDescription camera; //cameradescription타입 변수 camera 선언

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late CameraController _controller; //카메라 제어를 위한 컨트롤러 선언
  late Future<void> _initializeControllerFuture; //카메라 초기화
  File? _imageFile; // 이미지 파일 변수 추가
  late FlutterTts flutterTts; // TTS 라이브러리 인스턴스
  String _analysisResult = ''; // 이미지 분석 결과를 보여줄 텍스트 상태 변수 추가


  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera, //위젯에서 전달받은 카메라 정보로 컨트롤러 생성
      ResolutionPreset.medium, //화질 높아지면 로딩 오래 걸릴 수 있다길래 우선 medium으로 설정
    );
    _initializeControllerFuture = _controller.initialize();

    // 이미지 파일 불러오기
    _loadImage();

    flutterTts = FlutterTts(); // TTS 라이브러리 초기화
  }

  // 이미지 파일 불러오기 함수
  void _loadImage() async {
    final imageFile = await rootBundle.load('assets/speak_clothes_top_icon.png');
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
    //사용 끝나거나 강제 종료 당했을때 해제 안 하면 오류 생긴다고 해서 추가
    _controller.dispose();
    flutterTts.stop(); // TTS 정리
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (!_controller.value.isInitialized) {
      return;
    }
    try {
      final XFile picture = await _controller.takePicture();
      await _processImage(picture); // 사진 처리 및 Vision API 호출
    } catch (e) {
      print("Error taking picture: $e");
    }
  }

  Future<void> _processImage(XFile picture) async {
    final apiKey = Platform.environment['SPEAK_CLOTHES_VISION_API'];

    if (apiKey == null) {
      print('API key not found in environment variables.');
      return;
    }

    final client = await auth.clientViaApiKey('SPEAK_CLOTHES_VISION_API');
    final visionApi = vision.VisionApi(client);

    final imageBytes = await picture.readAsBytes();
    final imageContent = base64Encode(imageBytes);

    final request = vision.BatchAnnotateImagesRequest.fromJson({
      'requests': [
        {
          'image': {'content': imageContent},
          'features': [{'type': 'LABEL_DETECTION'}],
        },
      ],
    });

    // 새로운 이미지 촬영 요청
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
    final apiKey = Platform.environment['SPEAK_CLOTHES_TTS_API'];

    if (apiKey == null) {
      print('Text-to-Speech API key not found in environment variables.');
      return;
    }

    final client = await auth.clientViaApiKey(apiKey);
    final ttsApi = tts.TexttospeechApi(client);

    final synthesisInput = tts.SynthesisInput(text: text);
    final voiceSelection = tts.VoiceSelectionParams(languageCode: 'en-US', ssmlGender: 'FEMALE');
    final audioConfig = tts.AudioConfig(audioEncoding: 'MP3');

    final ttsRequest = tts.SynthesizeSpeechRequest(
      input: synthesisInput,
      voice: voiceSelection,
      audioConfig: audioConfig,
    );

    final ttsResponse = await ttsApi.text.synthesize(ttsRequest);

    // TODO: ttsResponse에서 음성 파일을 재생하거나 저장할 수 있습니다.
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
                    bottom: 16, // 텍스트를 아래쪽으로 위치시킴
                    left: 16,
                    right: 16,
                    child: Text(
                      _analysisResult, // 이미지 분석 결과를 표시
                      style: TextStyle(fontSize: 16, color: Colors.black),
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
      // ...
      floatingActionButton: FloatingActionButton(
        onPressed: _takePicture, // 이미지 촬영 버튼 클릭 시 _takePicture 함수 호출
        child: Icon(Icons.camera),
      ),
    );
  }
}
