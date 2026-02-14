import 'package:aura_mobile/domain/services/intent_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = IntentDetectionService();

  group('IntentDetectionService Tests', () {
    test('Detects Memory Store Intent', () {
      expect(service.detectIntent('remember that I need milk'), IntentType.storeMemory);
      expect(service.detectIntent('save this idea'), IntentType.storeMemory);
    });

    test('Detects Memory Retrieve Intent', () {
      expect(service.detectIntent('what did i save about milk'), IntentType.retrieveMemory);
      expect(service.detectIntent('do you remember my idea'), IntentType.retrieveMemory);
      expect(service.detectIntent('retrieve old notes'), IntentType.retrieveMemory);
      expect(service.detectIntent('remind me about the meeting'), IntentType.retrieveMemory);
    });

    test('Detects Document Query Intent (with hasDocuments=true)', () {
      expect(
        service.detectIntent('summarize this pdf', hasDocuments: true), 
        IntentType.queryDocument
      );
      expect(
        service.detectIntent('read file details', hasDocuments: true), 
        IntentType.queryDocument
      );
    });

    test('Defaults to Normal Chat if no trigger', () {
      expect(service.detectIntent('hello world'), IntentType.normalChat);
      expect(service.detectIntent('how are you'), IntentType.normalChat);
    });

    test('Extracts Memory Content Correctly', () {
      expect(service.extractMemoryContent('remember that buy eggs'), 'buy eggs');
      expect(service.extractMemoryContent('save this meeting at 5pm'), 'meeting at 5pm');
    });
  });
}
