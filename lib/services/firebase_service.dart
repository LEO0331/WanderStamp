import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/postcard.dart';

typedef PostcardCallable =
    Future<Object?> Function(String name, Map<String, Object?> data);

class FirebaseService {
  static FirebaseService? _instance;

  factory FirebaseService() {
    return _instance ??= FirebaseService._(
      FirebaseFirestore.instance,
      _callFirebase,
    );
  }

  final FirebaseFirestore _db;
  final PostcardCallable _call;

  FirebaseService._(this._db, this._call);

  static Future<Object?> _callFirebase(
    String name,
    Map<String, Object?> data,
  ) async {
    final functions = FirebaseFunctions.instanceFor(region: 'us-central1');
    return (await functions.httpsCallable(name).call<Object?>(data)).data;
  }

  @visibleForTesting
  factory FirebaseService.forTest({
    required FirebaseFirestore firestore,
    required PostcardCallable call,
  }) => FirebaseService._(firestore, call);

  @visibleForTesting
  static void setMockInstance(FirebaseService mock) {
    _instance = mock;
  }

  Future<String> addRequest(
    String name,
    String address,
    String topic, {
    String requestType = 'self',
    String? giftFromName,
    String? giftMessage,
    String? campaign,
  }) async {
    final result = await _call('submitPostcard', {
      'name': name,
      'address': address,
      'topic': topic,
      'requestType': requestType,
      'giftFromName': giftFromName,
      'giftMessage': giftMessage,
      'campaign': campaign,
    });
    return (result as Map)['publicId'] as String;
  }

  Stream<List<Postcard>> getPublicPostcards() =>
      _watchPostcards('postcardTracking');

  Stream<List<Postcard>> getAdminPostcards() => _watchPostcards('postcards');

  Stream<List<Postcard>> _watchPostcards(String collection) {
    return _db
        .collection(collection)
        .orderBy('requestDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Postcard.fromFirestore).toList());
  }

  Future<void> deletePostcard(String id) async {
    await _call('managePostcard', {'id': id, 'action': 'delete'});
  }

  Future<void> updateStatusWithLocation(
    String id,
    String newStatus, {
    double? lat,
    double? lng,
    String? city,
  }) async {
    await _call('managePostcard', {
      'id': id,
      'action': 'status',
      'status': newStatus,
      'lat': ?lat,
      'lng': ?lng,
      'city': ?city,
    });
  }

  Future<void> updateStatus(String id, String newStatus) =>
      updateStatusWithLocation(id, newStatus);

  Future<void> updateJourneyProgress(
    String id, {
    String? stage,
    String? travelerNote,
    String? travelerPhotoUrl,
    int? etaDays,
  }) async {
    if (stage == null &&
        travelerNote == null &&
        travelerPhotoUrl == null &&
        etaDays == null) {
      return;
    }

    await _call('managePostcard', {
      'id': id,
      'action': 'progress',
      'stage': ?stage,
      'travelerNote': ?travelerNote,
      'travelerPhotoUrl': ?travelerPhotoUrl,
      'etaDays': ?etaDays,
    });
  }

  Future<String> confirmPostcard(String token) async {
    final result = await _call('confirmPostcard', {'token': token});
    return (result as Map)['feedbackToken'] as String;
  }

  Future<void> updateReceiptFeedback(
    String token, {
    required String reaction,
    required String message,
    required bool showOnWall,
  }) async {
    await _call('submitPostcardFeedback', {
      'token': token,
      'reaction': reaction,
      'message': message,
      'showOnWall': showOnWall,
    });
  }

  Future<Map<String, int>> getTopicStats() async {
    final snapshot = await _db.collection('postcardTracking').get();
    final result = <String, int>{};
    for (final doc in snapshot.docs) {
      final topic = (doc.data()['topic'] as String?) ?? 'General';
      result[topic] = (result[topic] ?? 0) + 1;
    }
    return result;
  }
}
