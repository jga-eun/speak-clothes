import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/auth_io.dart' as auth;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      ),
    ),
  );
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.camera,
  });

  final CameraDescription camera;

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _processImage(File imageFile) async {
    // Google Cloud Vision API 인증
    final credentials = await auth.clientViaServiceAccount(
      auth.ServiceAccountCredentials.fromJson(
        File('assets/your_api_key_file.json').readAsStringSync(),
      ),
      // 변경된 스코프에 맞게 수정
      ['https://www.googleapis.com/auth/cloud-platform'],
    );

    // Vision API 클라이언트 생성
    final visionApi = vision.VisionApi(credentials);

    // 이미지를 Base64로 인코딩
    List<int> imageBytes = await imageFile.readAsBytes();
    String base64Image = base64Encode(imageBytes);

    // Vision API 요청 생성
    final request = vision.AnnotateImageRequest(
      image: vision.Image(content: base64Image),
      features: [vision.Feature(type: 'LABEL_DETECTION')],
    );
    final batch = vision.BatchAnnotateImagesRequest(
      requests: [request],
    );

    // Vision API 호출하여 응답 받기
    final response = await visionApi.images.annotate(batch);

    // 응답 결과 처리
    if (response.responses != null && response.responses!.isNotEmpty) {
      final labels = response.responses!.first.labelAnnotations;
      if (labels != null && labels.isNotEmpty) {
        List<String> detectedLabels =
        labels.map((label) => label.description!).toList();
        print('Detected labels: $detectedLabels');
      }
    }
  }

  void _onCaptureButtonPressed() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      _processImage(File(image.path));
    } catch (e) {
      print('Error capturing image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onCaptureButtonPressed,
        child: Icon(Icons.camera_alt),
      ),
    );
  }
}