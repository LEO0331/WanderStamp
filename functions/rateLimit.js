const {createHmac} = require('node:crypto');
const {isIP} = require('node:net');
const {Timestamp} = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');

const hourMs = 60 * 60 * 1000;

function clientAddress(request) {
  // The default Google load balancer appends the connecting IP and its own IP.
  // Use the trusted suffix of the forwarded chain, ignoring client-supplied entries.
  const forwarded = request.ips ?? [];
  const address = forwarded.at(-2) ?? forwarded.at(-1) ?? request.socket?.remoteAddress;
  if (!address || !isIP(address)) return 'unidentified';
  if (isIP(address) === 4) return address;
  return new URL('http://[' + address + ']').hostname;
}

function createRateLimiter(db, getKey, now = Date.now) {
  return async (scope, request, max) => {
    const secret = getKey();
    if (typeof secret !== 'string' || secret.length < 32) {
      throw new HttpsError('unavailable', 'The service is temporarily unavailable.');
    }
    const hour = Math.floor(now() / hourMs);
    const bucket = createHmac('sha256', secret)
      .update(JSON.stringify([scope, hour, clientAddress(request.rawRequest)]))
      .digest('hex');
    const ref = db.collection('postcardRateLimits').doc(bucket);
    await db.runTransaction(async (tx) => {
      const current = await tx.get(ref);
      const count = current.get('count') ?? 0;
      if (count >= max) {
        throw new HttpsError('resource-exhausted', 'Too many attempts. Please try again later.');
      }
      tx.set(ref, {count: count + 1, expiresAt: Timestamp.fromMillis((hour + 1) * hourMs)});
    });
  };
}

module.exports = {createRateLimiter};
