import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {

  static final SpeechToText _speech = SpeechToText();

  static Future<String?> listen() async {

    bool available = await _speech.initialize();

    if (!available) return null;

    String resultText = "";

    await _speech.listen(
      onResult: (result) {
        resultText = result.recognizedWords;
      },
    );

    await Future.delayed(Duration(seconds: 4));

    await _speech.stop();

    return resultText;
  }
}