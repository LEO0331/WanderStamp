const {HttpsError} = require('firebase-functions/v2/https');
const {coarseCoordinate, topics, campaigns} = require('./projection');

const stages = new Set(['requested', 'writing', 'packed', 'sent', 'received']);
const statuses = new Set(['sent', 'received']);
const reactions = new Set(['❤️', '😊', '🥹', '🌟']);
const tokenPattern = /^[A-Za-z0-9_-]{43}$/;

function invalid() {
  throw new HttpsError('invalid-argument', 'Please check the submitted fields.');
}

function fields(data, allowed) {
  if (!data || typeof data !== 'object' || Array.isArray(data) ||
      Object.keys(data).some((key) => !allowed.includes(key))) {
    invalid();
  }
}

function boundedText(value, maxLength, {required = false} = {}) {
  if (value == null && !required) return null;
  if (typeof value !== 'string' || value.length > maxLength) invalid();
  const trimmed = value.trim();
  if (required && !trimmed) invalid();
  return trimmed;
}

function requestInput(data) {
  fields(data, ['name', 'address', 'topic', 'requestType', 'giftFromName',
    'giftMessage', 'campaign']);
  const requestType = data.requestType ?? 'self';
  if (!['self', 'gift'].includes(requestType) ||
      !topics.has(data.topic) ||
      (data.campaign != null && !campaigns.has(data.campaign))) {
    invalid();
  }
  const gift = requestType === 'gift';
  if (!gift && (data.giftFromName != null || data.giftMessage != null)) invalid();

  return {
    receiverName: boundedText(data.name, 120, {required: true}),
    address: boundedText(data.address, 600, {required: true}),
    topic: data.topic,
    requestType,
    giftFromName: boundedText(data.giftFromName, 120, {required: gift}),
    giftMessage: boundedText(data.giftMessage, 600),
    campaign: data.campaign ?? null,
  };
}

function requireToken(token) {
  if (typeof token !== 'string' || !tokenPattern.test(token)) invalid();
  return token;
}

function receiptInput(data) {
  fields(data, ['token']);
  return requireToken(data.token);
}

function feedbackInput(data) {
  fields(data, ['token', 'reaction', 'message', 'showOnWall']);
  if (!reactions.has(data.reaction) || typeof data.showOnWall !== 'boolean') invalid();
  return {
    token: requireToken(data.token),
    feedback: {
      recipientReaction: data.reaction,
      recipientMessage: boundedText(data.message, 500) ?? '',
      showOnWall: data.showOnWall,
    },
  };
}

function locationInput(data) {
  const {lat, lng, city} = data;
  if (lat == null && lng == null && city == null) return {};
  if (!Number.isFinite(lat) || Math.abs(lat) > 90 ||
      !Number.isFinite(lng) || Math.abs(lng) > 180) invalid();
  return {
    lat: coarseCoordinate(lat),
    lng: coarseCoordinate(lng),
    sentCity: boundedText(city, 120),
  };
}

function photoInput(value) {
  const trimmed = boundedText(value, 2048);
  if (!trimmed) return '';
  let url;
  try {
    url = new URL(trimmed);
  } catch {
    invalid();
  }
  if (url.protocol !== 'https:' || url.username || url.password) invalid();
  return url.href;
}

function managementInput(data) {
  if (typeof data?.id !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(data.id)) {
    invalid();
  }
  const {id, action} = data;
  if (action === 'delete') {
    fields(data, ['id', 'action']);
    return {id, action};
  }
  if (action === 'status') {
    fields(data, ['id', 'action', 'status', 'lat', 'lng', 'city']);
    if (!statuses.has(data.status)) invalid();
    return {id, action, updates: {
      status: data.status,
      stage: data.status,
      ...locationInput(data),
    }};
  }
  if (action !== 'progress') invalid();
  fields(data, ['id', 'action', 'stage', 'travelerNote', 'travelerPhotoUrl', 'etaDays']);
  const updates = {};
  if (data.stage != null) {
    if (!stages.has(data.stage)) invalid();
    updates.stage = data.stage;
    if (statuses.has(data.stage)) updates.status = data.stage;
  }
  if (data.travelerNote != null) updates.travelerNote = boundedText(data.travelerNote, 600);
  if (data.travelerPhotoUrl != null) updates.travelerPhotoUrl = photoInput(data.travelerPhotoUrl);
  if (data.etaDays != null) {
    if (!Number.isInteger(data.etaDays) || data.etaDays < 0 || data.etaDays > 365) invalid();
    updates.etaDays = data.etaDays;
  }
  return {id, action, updates};
}

module.exports = {
  requestInput,
  receiptInput,
  feedbackInput,
  managementInput,
  tokenPattern,
};
