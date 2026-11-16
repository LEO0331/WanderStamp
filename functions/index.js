const {initializeApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {defineBoolean, defineSecret} = require('firebase-functions/params');
const {HttpsError, onCall} = require('firebase-functions/v2/https');
const {createPostcardHandlers} = require('./postcards');
const {createRateLimiter} = require('./rateLimit');

initializeApp();
const db = getFirestore();
const rateLimitKey = defineSecret('POSTCARD_RATE_LIMIT_KEY');
const enforceAppCheck = defineBoolean('ENFORCE_APP_CHECK', {default: false});
const handlers = createPostcardHandlers(
  db,
  createRateLimiter(db, () => rateLimitKey.value()),
);

function callable(handler, secrets = []) {
  return onCall({region: 'us-central1', maxInstances: 4, secrets}, (request) => {
    if (enforceAppCheck.value() && !request.app) {
      throw new HttpsError('unauthenticated', 'Please reload and try again.');
    }
    return handler(request);
  });
}

exports.submitPostcard = callable(handlers.submitPostcard, [rateLimitKey]);
exports.confirmPostcard = callable(handlers.confirmPostcard, [rateLimitKey]);
exports.submitPostcardFeedback = callable(handlers.submitPostcardFeedback, [rateLimitKey]);
exports.managePostcard = callable(handlers.managePostcard);
