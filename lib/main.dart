import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import "package:googleapis_auth/auth_io.dart";
import 'dart:convert';
import 'package:googleapis/texttospeech/v1.dart' as tts;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image/image.dart' as img;

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
  }) : super(key: key);

  final CameraDescription camera;
  final String? visionApiKey;
  final String? ttsApiKey;

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late auth.AuthClient _authClient;
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

    _initializeAuthClient();

    Timer.periodic(Duration(seconds: 7), (_) {
      _takePictureAndProcess();
    });
  }

  Future<void> _initializeAuthClient() async {
    final credentials = auth.ServiceAccountCredentials.fromJson({
      "type": "service_account",
      "project_id": "unique-terminus-394917",
      "private_key_id": "b6e6dbbc49a60dfc6f111df53960c9a8cfcfac6e",
      "private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC1+PySt1PXa0rZ\nGl6pEwxJZ2+TRqDoROEFSRE4zHmUqaVzQSsabKK+sziFF45JyoAPR/QgbF2+qZQC\nH9b7InTrhtwH95uh3IahQQjVVhI6i1ZnMiQ21+crm2skzTeuKwhVnnZrH8cxoV2H\nTSHA/zZS8RwIcX/ghqoyVpbk5AeczoAvW3MHxXcJLZm9uhCdnlanfjbN2Er/VZ/k\nFhlfUoniLMs67g6hBF8cYMLMYgQqR4RGfBHfllI3bEV1tOsHeutZn6LHgAaA9Cc8\nIYbbmc1eZ97Vyo+pF5OKM5ii+2ARrvs9FOOEbZyKbgSSAAQ0ppa18t2VbpNVMUKT\nI2/+bgmvAgMBAAECggEANDDr2/aZpNzAdGEUSkDM0tbIUQC+UK/ErBvnRRecPU+k\nxNgpkSQcTz6e1MlLRY2/SeK0uYHrJy6C5VMVeSTKTOz6eYyCRhu2P1SkQG+1vbXN\n+74NVe95fW/PfJghQqJT+x5+Tz4nhuwFo7MzHaP1BDfj9uX6q75j3RkpoQ9nwYia\npkpG/HmwqlAXBUd0TA6Q8SrRUPH6UtGQKmuyzxVJ7S2EKK5xQi+ChMCQBYOJ9d9a\nqJ66oeRs1XYBxwp9Q65LjNQitYiK+N9hUHTt815iIFXuWpK4MmGRa1cwhKW55Pah\ncX9rFuMGjDGCIGZbUWObSExPiiIKGpUxtfHriV4D0QKBgQDf1d81OLaaa5Ke114S\n8sXfL2QogUMCaPTuoSwuyihT4xro3yFmgGN++Uj23a2UsDKIkpgOU91iHkAnxqXr\nYnwKhnTVo65giTfnSAyTfvQW/b7zNQ5iOD2Kp3miCebFwpHtaKQJwdAJI1aGMM2T\nj0ahSeFcvazgXfLavxE/jyjAsQKBgQDQHyBjK66oet2AERyJTT1/HsLBNXk6+/ev\nlF/InlRbREkEthNGZEsk+vm2zrYvmHaBcLa39KIRTCxE8sc4KdHNGGLU6FbCTCv7\nbAvf3IfIk777RRaL4KFvPqLyubWpB3lqk8irGHAGrPdVYtTkITK0kux3lQ+C3d3R\niOHr9xkIXwKBgQCNOh4ZMG1WRSU/f1dl0TOzu+0P+W7UKHDR13NPGlITi6lA4Pfr\n+nnMdXDqAbgxpnJb5VJ3R8bYz4lfD2FEgOEOqwMwgJPXaPySuszkiydrEjLWtNUc\nd6usvjpqWKD4iekUx/8oANdHzLoc9NHglnfT8A93Ol3HOr+t8PvrBGKMIQKBgQCd\nQefHB4rB45Ta4BMf7C07kJK4Sx9/YkSVdxepD3nOPJqv5KRL3ByrpLhrWWZwMFPb\nGr/13/NV/qi0sH24AmF1B6gmGCj2R3g0Uj/mt0wiUwFL+7g9mU5iMIIPxiNtxSgJ\nUAGgxqZfZPK+oh8bAbq+lwX2lbtStzKU0UlkcyGHIQKBgE286MA0TE6rLViYeE1Q\nqC7IIzkJSf/CdXXH4y4FIskPqd1x5uBA8+LQfy2pOedHi2QkhUgGf3xpLNZVK14O\nKpg/tkTLig6paQfbobB6bWYbXS8OPnpYplLQ3pbeRtpB/SI6+5xekbylYHs1tex2\nCVu1UVZWpUTbWOugIr4fHQdC\n-----END PRIVATE KEY-----\n",
      "client_email": "speak-clothes-vertex-realreal@unique-terminus-394917.iam.gserviceaccount.com",
      "client_id": "139320715526-a9mqtprt706shu2dkm6glk36g42k438a.apps.googleusercontent.com",
      "auth_uri": "https://accounts.google.com/o/oauth2/auth",
      "token_uri": "https://oauth2.googleapis.com/token",
      "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
      "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/speak-clothes-vertex-realreal%40unique-terminus-394917.iam.gserviceaccount.com",
      "universe_domain": "googleapis.com"
    });

    final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
    _authClient = await clientViaServiceAccount(credentials, scopes);
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

    final url =
    Uri.parse('https://translation.googleapis.com/language/translate/v2');
    final response = await http.post(url, body: {
      'key': apiKey,
      'source': 'en',
      'target': 'ko',
      'q': text,
    });

    if (response.statusCode == 200) {
      final translatedText = json.decode(response.body)['data']['translations']
      [0]['translatedText'];
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

    print('Image size: ${imageBytes.length} bytes');


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
      print(
          'Vision API Response: $response'); // Add this line to log the response
      if (response.responses != null && response.responses!.isNotEmpty) {
        final labelAnnotations = response.responses!.first.labelAnnotations;
        if (labelAnnotations != null && labelAnnotations.isNotEmpty) {
          final labelAnnotation = labelAnnotations.first;
          final label = labelAnnotation.description ?? 'Unknown'; // description이 null이면 'Unknown'을 할당
          if (label != null) {
            final colorInfo = await _getColorInfo(label, picture);
            print('이미지 분석 결과: $label\n색상: $colorInfo');
            final translatedLabel = await _translateText(label!);

            // Vertex AI 예측 모델 호출 및 결과 처리
            final vertexPrediction = await _getVertexPrediction(imageBytes);
            print('옷 종류: $vertexPrediction');

            setState(() {
              _analysisResult = '옷 종류: $vertexPrediction\n색상: $colorInfo';
            });

            await flutterTts.setLanguage('en-US');
            await flutterTts.setSpeechRate(0.4);
            await flutterTts.setVolume(1.0);
            await flutterTts.speak('옷 종류: $vertexPrediction\n색상: $colorInfo');

            await _speakText('옷 종류: $vertexPrediction\n색상: $colorInfo');
          }
        }
      }
    } catch (e) {
      print("사진 처리 중 오류 발생 $e");
      setState(() {
        _analysisResult = '이미지 처리 중 오류 발생';
      });
    }
  }

  // Vertex AI 예측 모델 호출
  Future<String> _getVertexPrediction(Uint8List imageBytes) async {
    await dotenv.load(fileName: ".env");
    final vertexApiKey = dotenv.env['SPEAK_CLOTHES_API'];
    final ENDPOINT_ID = dotenv.env['ENDPOINTID'];
    final PROJECT_ID = dotenv.env['PROJECTID'];
    final vertexEndpoint = Uri.parse(
        'https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/us-central1/endpoints/${ENDPOINT_ID}:predict'); // Vertex AI 모델 엔드포인트 URL

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $vertexApiKey',
    };

    final requestBody = {
      'instances': [
        {
          "content": base64Encode(imageBytes),
        },
      ]
    };

    print('Sending API request to Vertex AI...');

    try {
      final response = await _authClient.post(
        vertexEndpoint,
        headers: headers,
        body: json.encode(requestBody),
      );

      print('Response status code: ${response.statusCode}');
      print('Response from Vertex AI: ${response.body}');

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        final predictions = decodedResponse['predictions'] as List<dynamic>; // List로 파싱
        final confidenceList = predictions[0]['confidences'];
        final maxConfidence = confidenceList.reduce((max, value) => value > max ? value : max);
        final maxConfidenceIndex = confidenceList.indexOf(maxConfidence);
        if (predictions.isNotEmpty) {
          final prediction = predictions[0]['displayNames'][maxConfidenceIndex] as String?; // 예측 결과의 키값에 따라 수정
          print('예측 결과: $prediction');
          return prediction ?? 'Unknown1'; // null이면 'Unknown'을 반환
        } else {
          print('예측 결과 없음');
          return 'Unknown2';
        }
      } else {
        print('Error, Failed to load prediction from Vertex AI: ${response.reasonPhrase}');
        return 'Error1';
      }
    } catch (e) {
      print("Error, Failed to send API request to Vertex AI: $e"); // 예외 출력
      return 'Error2';
    }
  }


  Future<String> _getColorInfo(String label, XFile picture) async {
    final visionApiKey = widget.visionApiKey;

    if (visionApiKey == null) {
      print('API key not found in environment variables.');
      return 'Unknown';
    }

    final client = auth.clientViaApiKey(visionApiKey);
    final visionApi = vision.VisionApi(client);

    final imageBytes = await File(picture.path!).readAsBytes();
    final imageContent = base64Encode(imageBytes);

    final image = vision.Image(content: imageContent);

    final request = vision.BatchAnnotateImagesRequest(
      requests: [
        vision.AnnotateImageRequest(
          image: image,
          features: [
            vision.Feature(type: 'IMAGE_PROPERTIES'),
          ],
        ),
      ],
    );

    try {
      final response = await visionApi.images.annotate(request);
      if (response.responses != null && response.responses!.isNotEmpty) {
        final color = response.responses!.first.imagePropertiesAnnotation
            ?.dominantColors?.colors?.first;
        if (color != null && color.color != null) {
          final r = (color.color!.red!).toInt();
          final g = (color.color!.green!).toInt();
          final b = (color.color!.blue!).toInt();

          // Convert RGB values to hexadecimal format
          final hexColor = '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';

          return 'RGB: $r, $g, $b\nHex: $hexColor';
        }
      }
    } catch (e) {
      print("사진 처리 중 오류 발생 $e");
      // ...
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

    //ttsResponse에서 음성 파일을 재생하거나 저장할 수 있음.
    final ttsResponse = await ttsApi.text.synthesize(ttsRequest);
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