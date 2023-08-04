import 'dart:async'; //비동기 사용하려고 import
import 'package:camera/camera.dart'; //카메라 package 사용하려고 import
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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
    super.dispose();
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
    );
  }

// ...
}
