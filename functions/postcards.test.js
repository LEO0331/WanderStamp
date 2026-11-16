const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {test} = require('node:test');
const {deleteApp, initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {createPostcardHandlers} = require('./postcards');
const {createRateLimiter} = require('./rateLimit');
const {requestInput} = require('./validation');

const fakeInput = {
  name: 'Test name',
  address: 'Test-only placeholder',
  topic: 'Inspiration (勇氣與啟發)',
};
const auth = {token: {admin: true}};
const emulator = /^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST ?? '');

test('request validation rejects extra fields and out-of-bounds values', () => {
  for (const extra of [{status: 'sent'}, {address: 'x'.repeat(601)},
    {campaign: 'Unknown'}, {giftMessage: 'Unexpected'}]) {
    assert.throws(() => requestInput({...fakeInput, ...extra}), {code: 'invalid-argument'});
  }
});

test('transactions keep tracking, confirmation, and private feedback separated', {
  skip: !emulator,
}, async (t) => {
  const app = initializeApp({projectId: 'demo-wanderstamp-handler-tests'},
    'postcards-' + randomUUID());
  t.after(() => deleteApp(app));
  const db = getFirestore(app);
  const handlers = createPostcardHandlers(db, async () => {});
  const {publicId} = await handlers.submitPostcard({data: fakeInput});
  const snapshot = await db.collection('postcards').where('publicId', '==', publicId).get();
  assert.equal(snapshot.size, 1);
  const postcard = snapshot.docs[0];
  const publicRef = db.collection('postcardTracking').doc(publicId);
  const initial = (await publicRef.get()).data();
  assert.equal(initial.status, 'pending');
  for (const field of ['address', 'receiverName', 'receiptToken', 'publicId']) {
    assert.equal(Object.hasOwn(initial, field), false);
  }
  assert.notEqual(postcard.id, publicId);

  const data = {id: postcard.id, action: 'status', status: 'sent',
    lat: 23.487257, lng: 120.384176};
  await assert.rejects(handlers.managePostcard({data, auth: {token: {}}}),
    {code: 'permission-denied'});
  const token = postcard.get('receiptToken');
  await assert.rejects(handlers.confirmPostcard({data: {token}}),
    {code: 'failed-precondition'});
  await handlers.managePostcard({data, auth});
  const sent = (await publicRef.get()).data();
  assert.equal(sent.status, 'sent');
  assert.equal(sent.lat, 23.5);
  assert.equal(sent.lng, 120.5);

  const attempts = await Promise.allSettled([
    handlers.confirmPostcard({data: {token}}),
    handlers.confirmPostcard({data: {token}}),
  ]);
  const success = attempts.find((result) => result.status === 'fulfilled');
  assert.equal(attempts.filter((result) => result.status === 'fulfilled').length, 1);
  assert.equal(attempts.find((result) => result.status === 'rejected').reason.code,
    'failed-precondition');
  const {feedbackToken} = success.value;
  const received = (await publicRef.get()).data();
  assert.equal(received.status, 'received');
  assert.ok(received.sentDate.isEqual(sent.sentDate));

  const feedback = {data: {token: feedbackToken, reaction: '❤️',
    message: 'Test feedback', showOnWall: false}};
  await handlers.submitPostcardFeedback(feedback);
  await assert.rejects(handlers.submitPostcardFeedback(feedback),
    {code: 'failed-precondition'});
  assert.equal((await postcard.ref.get()).get('recipientMessage'), 'Test feedback');
  assert.equal((await publicRef.get()).get('recipientMessage'), undefined);

  await handlers.managePostcard({data: {id: postcard.id, action: 'delete'}, auth});
  assert.equal((await postcard.ref.get()).exists, false);
  assert.equal((await publicRef.get()).exists, false);
});

test('rate limits group requests by the trusted proxy suffix within a fixed window', {
  skip: !emulator,
}, async (t) => {
  const app = initializeApp({projectId: 'demo-wanderstamp-handler-tests'},
    'quota-' + randomUUID());
  t.after(() => deleteApp(app));
  const db = getFirestore(app);
  let now = Date.now();
  const secret = 'example-only-test-key-for-synthetic-emulator-traffic';
  const limit = createRateLimiter(db, () => secret, () => now);
  const scope = 'test-' + randomUUID();
  const request = (prefix) => ({rawRequest: {ips: [prefix, '198.51.100.25', '203.0.113.49']}});
  await limit(scope, request('192.0.2.12'), 1);
  await assert.rejects(limit(scope, request('192.0.2.13'), 1), {code: 'resource-exhausted'});
  now += 60 * 60 * 1000;
  await limit(scope, request('192.0.2.13'), 1);
});
