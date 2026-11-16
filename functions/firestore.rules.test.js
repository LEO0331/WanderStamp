'use strict';

const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');
const { deleteApp, initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { migrate } = require('./migrate.js');

const emulatorAddress = process.env.FIRESTORE_EMULATOR_HOST;
const skip = emulatorAddress ? false : 'Set FIRESTORE_EMULATOR_HOST to run Firestore tests';

test('Firestore migration and client permissions', { skip }, async (t) => {
  const address = /^127\.0\.0\.1:(\d+)$/u.exec(emulatorAddress);
  assert.ok(address, 'Use a local Firestore emulator at 127.0.0.1');
  const port = Number(address[1]);
  const projectId = 'demo-wanderstamp-rules';
  const { assertFails, assertSucceeds, initializeTestEnvironment } =
    require('@firebase/rules-unit-testing');
  const { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } =
    require('firebase/firestore');
  const environment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port,
      rules: readFileSync(join(__dirname, '..', 'firestore.rules'), 'utf8'),
    },
  });
  t.after(() => environment.cleanup());
  await environment.clearFirestore();
  const app = initializeApp({ projectId }, 'wanderstamp-rules');
  t.after(() => deleteApp(app));
  const db = getFirestore(app);

  const legacyRef = db.collection('postcards').doc('legacy-AB12');
  await legacyRef.set({
    address: 'private',
    requestDate: Timestamp.fromMillis(100),
    status: 'sent',
    lat: 11.138,
    lng: 20.638,
    sentCity: '11.14, 20.64',
    publicId: 'untrusted-public-id',
    feedbackTokenHash: 'untrusted-feedback-index',
  });
  await t.test('migration dry run leaves legacy data alone', async () => {
    assert.deepEqual(await migrate(db, { apply: false }), { scanned: 1, migrated: 0 });
    assert.equal((await db.collection('postcardTracking').count().get()).data().count, 0);
  });

  let publicId;
  let receiptHash;
  await t.test('migration is idempotent and uses an independent public ID', async () => {
    assert.deepEqual(await migrate(db, { apply: true }), { scanned: 1, migrated: 1 });
    const source = (await legacyRef.get()).data();
    const marker = await db.collection('postcardProjection').doc(legacyRef.id).get();
    publicId = marker.data().publicId;
    assert.notEqual(publicId, legacyRef.id);
    assert.notEqual(publicId, 'untrusted-public-id');
    assert.equal(source.publicId, publicId);
    assert.equal(source.trackingCode, 'AB12');
    assert.equal(source.address, 'private');
    assert.equal(source.lat, 11.25);
    assert.equal(source.lng, 20.75);
    assert.equal(source.sentCity, undefined);
    assert.equal(source.feedbackTokenHash, undefined);
    assert.match(source.receiptToken, /^[A-Za-z0-9_-]{43}$/u);
    receiptHash = createHash('sha256').update(source.receiptToken).digest('hex');
    assert.deepEqual(
      (await db.collection('postcardReceipts').doc(receiptHash).get()).data(),
      { postcardId: legacyRef.id },
    );
    assert.deepEqual(await migrate(db, { apply: true }), { scanned: 1, migrated: 0 });
    assert.deepEqual((await legacyRef.get()).data(), source);
  });

  await t.test('only the trusted backend can write or see receipt metadata', async () => {
    const anonymous = environment.unauthenticatedContext().firestore();
    const member = environment.authenticatedContext('member').firestore();
    const admin = environment.authenticatedContext('admin-user', { admin: true }).firestore();
    const tracking = (client) => doc(client, 'postcardTracking', publicId);
    const privateCard = (client) => doc(client, 'postcards', legacyRef.id);
    const publicCard = await assertSucceeds(getDoc(tracking(anonymous)));
    assert.deepEqual(publicCard.data(), {
      trackingCode: 'AB12',
      requestDate: publicCard.data().requestDate,
      status: 'sent',
      stage: 'sent',
      topic: 'General',
      lat: 11.25,
      lng: 20.75,
    });
    await assertSucceeds(getDocs(collection(anonymous, 'postcardTracking')));
    await assertSucceeds(getDoc(privateCard(admin)));
    await assertSucceeds(getDocs(collection(admin, 'postcards')));
    await assertFails(getDoc(privateCard(anonymous)));
    await assertFails(getDocs(collection(anonymous, 'postcards')));
    await assertFails(getDoc(privateCard(member)));
    await assertFails(getDocs(collection(member, 'postcards')));
    await assertFails(setDoc(doc(anonymous, 'postcards', 'new-doc'), { status: 'pending' }));
    for (const client of [anonymous, member, admin]) {
      await assertFails(updateDoc(tracking(client), { status: 'received' }));
      await assertFails(deleteDoc(privateCard(client)));
      await assertFails(getDoc(doc(client, 'postcardReceipts', receiptHash)));
      await assertFails(getDoc(doc(client, 'postcardProjection', legacyRef.id)));
    }
  });
});
