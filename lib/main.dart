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
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> main() async {
  // Flutter 앱 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // API 키 로드
  await dotenv.load(fileName: ".env");
  final visionApiKey = dotenv.env['SPEAK_CLOTHES_API'];
  final ttsApiKey = dotenv.env['SPEAK_CLOTHES_API'];

  // 사용 가능한 카메라 목록 가져오기
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  // 앱 실행
  runApp(
    MaterialApp(
      home:
      LoadingMenu(
        camera: firstCamera,
        visionApiKey: visionApiKey,
        ttsApiKey: ttsApiKey,)
    ),
  );
}

// 로딩화면
class LoadingMenu extends StatefulWidget {
  const LoadingMenu({
    Key? key,
    required this.camera,
    required this.visionApiKey,
    required this.ttsApiKey,}) : super(key: key);

  final CameraDescription camera;
  final visionApiKey;
  final ttsApiKey;

  @override
  // ignore: library_private_types_in_public_api
  _LoadingMenuState createState() {
    return _LoadingMenuState();
  }
}

class _LoadingMenuState extends State<LoadingMenu> {
  double _progress = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    // 일정 간격마다 로딩 화면을 업데이트하고, 카메라 화면으로 전환
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        _progress += 0.01;
        if (_progress >= 1) {
          _progress = 0;
          _timer?.cancel(); // 타이머 취소
          Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (context) => CameraScreen(
              camera: widget.camera,
              visionApiKey: widget.visionApiKey,
              ttsApiKey: widget.ttsApiKey,
            ),
          ));
        }
      });
    });
  }

  @override
  void dispose() {
    // 위젯이 제거될 때 타이머 정리
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 225, 50),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 로딩 화면 구성 요소
            SizedBox(
              width: 230,
              height: 230,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale:
                    4.5, // Adjust the scale to make the CircularProgressIndicator larger
                    child: CircularProgressIndicator(
                      value: _progress,
                      strokeWidth: 7,
                      color: Colors.white,
                      backgroundColor: const Color.fromARGB(255, 226, 208, 49),
                    ),
                  ),
                  Image.network(
                    "https://i.ibb.co/ZcbRhJd/1.jpg",
                    width: 80,
                    height: 80,
                  ),
                ],
              ),
            ),
            // 로딩 텍스트
            Container(
              padding: const EdgeInsets.only(bottom: 80),
              width: 110,
              alignment: Alignment.center,
              child: const Text(
                'Loading',
                style: TextStyle(fontSize: 25, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 카메라 화면 위젯
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

    // 카메라 컨트롤러 초기화
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();

    // 텍스트 음성 변환을 위한 플러터 TTS 초기화
    flutterTts = FlutterTts();

    // Google Cloud Vision API와 통신하기 위한 클라이언트 초기화
    _initializeAuthClient();

    // 일정 간격마다 사진 촬영 후 처리 함수 호출
    Timer.periodic(Duration(seconds: 7), (_) {
      _takePictureAndProcess();
    });
  }

  Future<void> _initializeAuthClient() async {
    final credentials = auth.ServiceAccountCredentials.fromJson({
    });

    final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
    _authClient = await clientViaServiceAccount(credentials, scopes);
  }

  @override
  void dispose() {
    // 위젯이 제거될 때 카메라 컨트롤러와 TTS 정리
    _controller.dispose();
    flutterTts.stop();
    super.dispose();
  }

  // 사진 촬영 및 처리
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

  // 이미지 처리
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
          'Vision API Response: $response');
      if (response.responses != null && response.responses!.isNotEmpty) {
        final labelAnnotations = response.responses!.first.labelAnnotations;
        if (labelAnnotations != null && labelAnnotations.isNotEmpty) {
          final labelAnnotation = labelAnnotations.first;
          final label = labelAnnotation.description ??
              'Unknown';
          if (label != null) {
            final colorInfo = await _getColorInfo(label, picture);
            print('이미지 분석 결과: $label\n색상: $colorInfo');

            // Vertex AI 예측 모델 호출 및 결과 처리
            final prevertexPrediction = await _getVertexPrediction(imageBytes);
            final vertexPrediction;
            switch (prevertexPrediction) {
              case 'hood_zip_up':
                vertexPrediction = '후드집업';
                break;
              case 'knit':
                vertexPrediction = '니트';
                break;
              case 'check_shirt':
                vertexPrediction = '체크 셔츠';
                break;
              case 'shirt':
                vertexPrediction = '셔츠';
                break;
              case 'stripe_t_shirt':
                vertexPrediction = '줄무늬 티셔츠';
                break;
              case 't_shirt':
                vertexPrediction = '티셔츠';
                break;
              case 'hood_t_shirt':
                vertexPrediction = '후드티';
                break;
              case 'cardigan':
                vertexPrediction = '가디건';
                break;
              case 'jacket':
                vertexPrediction = '재킷';
                break;
              case 'sweatshirt':
                vertexPrediction = '맨투맨';
                break;
              case 'sleeveless':
                vertexPrediction = '민소매';
                break;
              case 'blouse':
                vertexPrediction = '블라우스';
                break;
              default:
                vertexPrediction = '인식 불가능';
            }
            print('옷 종류: $vertexPrediction');

            setState(() {
              //_analysisResult = '옷 종류: $vertexPrediction\n색상: $colorInfo';
              _analysisResult = '$colorInfo상의 $vertexPrediction입니다.';
            });

            await flutterTts.setLanguage('ko-KR');
            await flutterTts.setSpeechRate(0.4);
            await flutterTts.setVolume(1.0);
            await flutterTts.speak('$colorInfo상의 $vertexPrediction입니다.');
          }
        }
      }
    } catch (e) {
      print("사진 처리 중 오류 발생 $e");
      setState(() {
        //_analysisResult = '이미지 처리 중 오류 발생';
        _analysisResult = ' ';
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

    //print('Sending API request to Vertex AI...');

    try {
      final response = await _authClient.post(
        vertexEndpoint,
        headers: headers,
        body: json.encode(requestBody),
      );

      //print('Response status code: ${response.statusCode}');
      //print('Response from Vertex AI: ${response.body}');

      if (response.statusCode == 200) {
        final decodedResponse = json.decode(response.body);
        final predictions =
        decodedResponse['predictions'] as List<dynamic>;
        final confidenceList = predictions[0]['confidences'];
        final maxConfidence =
        confidenceList.reduce((max, value) => value > max ? value : max);
        final maxConfidenceIndex = confidenceList.indexOf(maxConfidence);
        if (predictions.isNotEmpty) {
          final prediction = predictions[0]['displayNames'][maxConfidenceIndex]
          as String?;
          //print('예측 결과: $prediction');
          return prediction ?? 'Unknown1';
        } else {
          //print('예측 결과 없음');
          return 'Unknown2';
        }
      } else {
        //print('Error, Failed to load prediction from Vertex AI: ${response.reasonPhrase}');
        return 'Error1';
      }
    } catch (e) {
      //print("Error, Failed to send API request to Vertex AI: $e"); // 예외 출력
      return 'Error2';
    }
  }

  // 색상 정보 가져오기
  Future<String> _getColorInfo(String label, XFile picture) async {
    final apiKey = widget.visionApiKey;

    if (apiKey == null) {
      print('환경 변수에서 API 키를 찾을 수 없습니다.');
      return 'Unknown';
    }

    final client = auth.clientViaApiKey(apiKey);
    final visionApi = vision.VisionApi(client);

    final imageBytes = await File(picture.path).readAsBytes();
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

          final hexColor = '0xff${r.toRadixString(16).padLeft(2, '0')}'
              '${g.toRadixString(16).padLeft(2, '0')}'
              '${b.toRadixString(16).padLeft(2, '0')}';
          print('hexColor : $hexColor');

          final colorLabel = _findAndPrintMatchingFields(hexColor);

          return colorLabel;
        }
      }
    } catch (e) {
      print("사진 처리 중 오류 발생 $e");
    }

    return 'Unknown';
  }

  // 데이터베이스에 있는 색상값과 가장 유사한 값을 찾고, 필드 찾기
  Future<String> _findAndPrintMatchingFields(String targetValue) async {
    int intTargetValue = int.parse(targetValue);
    List<int> numbers = [4281479730, 4286085240, 4279500800, 4278190080, 4288059030,
      4280888355, 4280819230, 4278523202, 4280627566, 4284075519, 4282344053, 4280147668,
      4279918763, 4287275708, 4279511456, 4290102217, 4278254591, 4278254591, 4278452479,
      4287734453, 4290896092, 4287408760, 4292999880, 4278251610, 4282808350, 4278206740,
      4285446440, 4283479150, 4286767360, 4280862815, 4282152960, 4280870400, 4281497600,
      4291361440, 4284136960, 4280199680, 4286758500, 4282140210, 4279834900, 4291989870,
      4294927360, 4294935110, 4284759075, 4286732860, 4294947990, 4291975720, 4291340950,
      4284764230, 4286735440, 4294940260, 4294932480, 4291655750, 4287383070, 4286739305,
      4294932530, 4288035850, 4284753920, 4292625920, 4291791501, 4289206329, 4283503921,
      4290075545, 4283042929, 4293867102, 4289272714, 4284361801, 4294810021, 4292527587,
      4294956260, 4288046180, 4285071360, 4294955730, 4294948020, 4294924890, 4294901760,
      4290641920, 4285411890, 4292935680, 4294937740, 4294940310, 4285399040, 4294927460,
      4294909470, 4285419600, 4282122240, 4282129950, 4290667620, 4290680470, 4290654770,
      4294917180, 4294638280, 4294963440, 4294310889, 4294766802, 4294967295, 4294965760,
      4287794944, 4294632985, 4291347260, 4291347260, 4292203008, 4294967075, 4294307920,
      4292335385, 4294440342, 4294638270];
    int realIntTargetValue = numbers.reduce((closest, current) {
      int currentDistance = (current - intTargetValue).abs();
      int closestDistance = (closest - intTargetValue).abs();

      if (currentDistance < closestDistance) {
        return current;
      } else {
        return closest;
      }
    });
    final collectionRef = FirebaseFirestore.instance.collection('colors');
    final querySnapshot = await collectionRef.get();

    for (final doc in querySnapshot.docs) {
      final fieldMap = doc.data() as Map<String, dynamic>;
      for (final fieldName in fieldMap.keys) {
        final fieldValue = fieldMap[fieldName];
        if (fieldValue is int) {
          if (fieldValue == realIntTargetValue) {
            print('Matching field name in document "${doc.id}": $fieldName');

            return fieldName;
          }
        }
      }
    }
    throw Exception('Matching field not found');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: const Text('Speak Clothes')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                Positioned.fill(
                  child: CameraPreview(_controller),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        //_isDetecting ? '이미지 분석 중' : _analysisResult,
                        _isDetecting ? ' ' : _analysisResult,
                        style: TextStyle(
                          fontSize: 16,
                          color: const Color.fromARGB(255, 150, 5, 5),
                        ),
                      ),
                    ],
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