const {createHash, randomBytes, timingSafeEqual} = require('node:crypto');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');
const {projectPostcard} = require('./projection');
const {
  requestInput, receiptInput, feedbackInput, managementInput, tokenPattern,
} = require('./validation');

const hourMs = 60 * 60 * 1000;
const hashToken = (token) => createHash('sha256').update(token).digest('hex');
const newToken = () => randomBytes(32).toString('base64url');

function tokenMatches(expected, actual) {
  return typeof expected === 'string' && tokenPattern.test(expected) &&
    timingSafeEqual(Buffer.from(expected, 'ascii'), Buffer.from(actual, 'ascii'));
}

function unavailableReceipt() {
  return new HttpsError('failed-precondition', 'This receipt code is unavailable.');
}

function createPostcardHandlers(db, limitTraffic, now = Date.now) {
  const postcards = db.collection('postcards');
  const tracking = db.collection('postcardTracking');
  const projections = db.collection('postcardProjection');
  const receipts = db.collection('postcardReceipts');
  const feedbackTokens = db.collection('postcardFeedbackTokens');

  async function readPair(tx, id) {
    const privateRef = postcards.doc(id);
    const [postcard, mapping] = await Promise.all([
      tx.get(privateRef),
      tx.get(projections.doc(id)),
    ]);
    if (!postcard.exists || !mapping.exists) return null;
    return {
      privateRef,
      publicRef: tracking.doc(mapping.get('publicId')),
      data: postcard.data(),
    };
  }

  function writePair(tx, pair, updates) {
    const data = {...pair.data, ...updates};
    tx.update(pair.privateRef, updates);
    tx.set(pair.publicRef, projectPostcard(data));
  }

  async function submitPostcard(request) {
    const input = requestInput(request.data);
    await limitTraffic('request', request, 12);
    const privateRef = postcards.doc();
    const publicRef = tracking.doc();
    const publicId = publicRef.id;
    const receiptToken = newToken();
    const data = {
      ...input,
      publicId,
      trackingCode: publicId.slice(-4).toUpperCase(),
      receiptToken,
      status: 'pending',
      stage: 'requested',
      requestDate: FieldValue.serverTimestamp(),
    };

    const batch = db.batch();
    batch.create(privateRef, data);
    batch.create(publicRef, projectPostcard(data));
    batch.create(projections.doc(privateRef.id), {publicId});
    batch.create(receipts.doc(hashToken(receiptToken)), {postcardId: privateRef.id});
    await batch.commit();
    return {publicId};
  }

  async function confirmPostcard(request) {
    const token = receiptInput(request.data);
    await limitTraffic('receipt', request, 60);
    const receiptRef = receipts.doc(hashToken(token));
    const feedbackToken = newToken();
    const feedbackHash = hashToken(feedbackToken);

    await db.runTransaction(async (tx) => {
      const receipt = await tx.get(receiptRef);
      if (!receipt.exists) throw unavailableReceipt();
      const id = receipt.get('postcardId');
      const pair = await readPair(tx, id);
      if (pair?.data.status !== 'sent' || !tokenMatches(pair.data.receiptToken, token)) {
        throw unavailableReceipt();
      }
      writePair(tx, pair, {
        status: 'received',
        stage: 'received',
        receiptToken: FieldValue.delete(),
        feedbackTokenHash: feedbackHash,
      });
      tx.delete(receiptRef);
      tx.create(feedbackTokens.doc(feedbackHash), {
        postcardId: id,
        expiresAt: Timestamp.fromMillis(now() + hourMs),
      });
    });
    return {feedbackToken};
  }

  async function submitPostcardFeedback(request) {
    const {token, feedback} = feedbackInput(request.data);
    await limitTraffic('feedback', request, 60);
    const tokenHash = hashToken(token);
    const tokenRef = feedbackTokens.doc(tokenHash);
    await db.runTransaction(async (tx) => {
      const feedbackDoc = await tx.get(tokenRef);
      if (!feedbackDoc.exists || feedbackDoc.get('expiresAt').toMillis() <= now()) {
        throw unavailableReceipt();
      }
      const pair = await readPair(tx, feedbackDoc.get('postcardId'));
      if (pair?.data.status !== 'received' || pair.data.feedbackTokenHash !== tokenHash) {
        throw unavailableReceipt();
      }
      writePair(tx, pair, {...feedback, feedbackTokenHash: FieldValue.delete()});
      tx.delete(tokenRef);
    });
    return {ok: true};
  }

  async function managePostcard(request) {
    if (request.auth?.token?.admin !== true) {
      throw new HttpsError('permission-denied', 'Administrator access is required.');
    }
    const {id, action, updates: requestedUpdates} = managementInput(request.data);

    await db.runTransaction(async (tx) => {
      const pair = await readPair(tx, id);
      if (!pair) throw new HttpsError('not-found', 'This postcard is unavailable.');
      const {data, privateRef, publicRef} = pair;
      const updates = {...requestedUpdates};

      if (action === 'delete') {
        if (data.receiptToken) tx.delete(receipts.doc(hashToken(data.receiptToken)));
        if (data.feedbackTokenHash) tx.delete(feedbackTokens.doc(data.feedbackTokenHash));
        tx.delete(publicRef);
        tx.delete(projections.doc(id));
        tx.delete(privateRef);
        return;
      }
      if (updates.status === 'sent' && data.status !== 'sent') {
        if (data.sentDate == null) updates.sentDate = FieldValue.serverTimestamp();
        if (!data.receiptToken) {
          const receiptToken = newToken();
          updates.receiptToken = receiptToken;
          tx.create(receipts.doc(hashToken(receiptToken)), {postcardId: id});
        }
      }
      if (updates.status === 'received' && data.receiptToken) {
        tx.delete(receipts.doc(hashToken(data.receiptToken)));
        updates.receiptToken = FieldValue.delete();
      }
      if (updates.status && updates.status !== 'received' && data.feedbackTokenHash) {
        tx.delete(feedbackTokens.doc(data.feedbackTokenHash));
        updates.feedbackTokenHash = FieldValue.delete();
      }
      if (Object.keys(updates).length) writePair(tx, pair, updates);
    });
    return {ok: true};
  }

  return {submitPostcard, confirmPostcard, submitPostcardFeedback, managePostcard};
}

module.exports = {createPostcardHandlers};
