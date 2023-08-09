import 'dart:io';

void main() {
  // 환경 변수 읽기
  var visionApiKey = Platform.environment['SPEAK_CLOTHES_VISION_API'];
  var ttsApiKey = Platform.environment['SPEAK_CLOTHES_TTS_API'];

  if (visionApiKey != null && ttsApiKey != null) {
    // 환경 변수가 설정되어 있다면 해당 값들을 사용하여 작업을 수행할 수 있습니다.
    print('Vision API Key: $visionApiKey');
    print('TTS API Key: $ttsApiKey');
  } else {
    print('API keys are not set in environment variables.');
  }
}
