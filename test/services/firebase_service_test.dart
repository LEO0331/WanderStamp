import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wander_stamp/services/firebase_service.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirebaseService service;
  late List<(String, Map<String, Object?>)> calls;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    calls = [];
    service = FirebaseService.forTest(
      firestore: firestore,
      call: (name, data) async {
        calls.add((name, data));
        return switch (name) {
          'submitPostcard' => {'publicId': 'public-8A2C'},
          'confirmPostcard' => {'feedbackToken': 'feedback-token'},
          _ => null,
        };
      },
    );
  });

  test('public tracker and topic stats read only public documents', () async {
    final timestamp = Timestamp.fromDate(DateTime.utc(2026, 1, 1));
    await firestore.collection('postcards').doc('private-ID').set({
      'receiverName': 'Test Recipient',
      'address': 'synthetic',
      'receiptToken': 'private-token',
      'topic': 'Private topic',
      'requestDate': timestamp,
    });
    await firestore.collection('postcardTracking').doc('public-ID').set({
      'trackingCode': '8A2C',
      'topic': 'Comfort',
      'requestDate': timestamp,
    });

    final tracking = (await service.getPublicPostcards().first).single;
    expect(tracking.id, 'public-ID');
    expect(tracking.warmthId, 'W-8A2C');
    expect(tracking.receiverName, 'Anonymous');
    expect(tracking.address, isEmpty);
    expect(tracking.receiptToken, isNull);
    expect(await service.getTopicStats(), {'Comfort': 1});

    final admin = (await service.getAdminPostcards().first).single;
    expect(admin.id, 'private-ID');
    expect(admin.address, 'synthetic');
    expect(admin.receiptToken, 'private-token');
  });

  test('submission uses the callable and returns only the public ID', () async {
    final id = await service.addRequest(
      'Test Recipient',
      'synthetic',
      'Comfort',
      requestType: 'gift',
      giftFromName: 'Test Sender',
      giftMessage: 'Test message',
      campaign: 'Spring Japan Trip',
    );

    expect(id, 'public-8A2C');
    expect(calls.map((call) => [call.$1, call.$2]).toList(), [
      [
        'submitPostcard',
        {
          'name': 'Test Recipient',
          'address': 'synthetic',
          'topic': 'Comfort',
          'requestType': 'gift',
          'giftFromName': 'Test Sender',
          'giftMessage': 'Test message',
          'campaign': 'Spring Japan Trip',
        },
      ],
    ]);
    expect((await firestore.collection('postcards').get()).docs, isEmpty);
  });

  test('receipt confirmation and feedback use separate credentials', () async {
    final feedbackToken = await service.confirmPostcard('receipt-token');
    await service.updateReceiptFeedback(
      feedbackToken,
      reaction: '❤️',
      message: 'Thank you',
      showOnWall: false,
    );

    expect(calls.map((call) => [call.$1, call.$2]).toList(), [
      [
        'confirmPostcard',
        {'token': 'receipt-token'},
      ],
      [
        'submitPostcardFeedback',
        {
          'token': 'feedback-token',
          'reaction': '❤️',
          'message': 'Thank you',
          'showOnWall': false,
        },
      ],
    ]);
  });

  test('admin changes use the authenticated management callable', () async {
    await service.updateJourneyProgress('private-ID');
    await service.updateJourneyProgress(
      'private-ID',
      stage: 'writing',
      travelerNote: '',
      etaDays: 4,
    );
    await service.updateStatusWithLocation(
      'private-ID',
      'sent',
      lat: 1.25,
      lng: 4.5,
    );
    await service.updateStatus('private-ID', 'received');
    await service.deletePostcard('private-ID');

    expect(calls.map((call) => [call.$1, call.$2]).toList(), [
      [
        'managePostcard',
        {
          'id': 'private-ID',
          'action': 'progress',
          'stage': 'writing',
          'travelerNote': '',
          'etaDays': 4,
        },
      ],
      [
        'managePostcard',
        {
          'id': 'private-ID',
          'action': 'status',
          'status': 'sent',
          'lat': 1.25,
          'lng': 4.5,
        },
      ],
      [
        'managePostcard',
        {'id': 'private-ID', 'action': 'status', 'status': 'received'},
      ],
      [
        'managePostcard',
        {'id': 'private-ID', 'action': 'delete'},
      ],
    ]);
  });
}
