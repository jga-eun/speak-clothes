import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoadingMenu(),
    );
  }
}

class LoadingMenu extends StatefulWidget {
  const LoadingMenu({Key? key}) : super(key: key);

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
    _timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
      setState(() {
        _progress += 0.01;
        if (_progress >= 1) {
          _progress = 0;
        }
      });
    });
  }

  @override
  void dispose() {
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
            Container(
              padding: const EdgeInsets.only(bottom: 80),
              width: 110,
              alignment: Alignment.center,
              child: const Text(
                'Loading',
                style: TextStyle(fontSize: 30, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
