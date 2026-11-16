'use strict';

const { FieldValue, Timestamp } = require('firebase-admin/firestore');

const topics = new Set([
  'Inspiration (勇氣與啟發)',
  'Comfort (溫暖與安慰)',
  'Travel Story (旅行故事)',
  'Daily Life (生活雜記)',
  'Random Surprise (隨機驚喜)',
  'Birthday Blessing (生日祝福)',
  'Heartbreak Healing (失戀療癒)',
  'New Adventure (冒險啟程)',
]);

const campaigns = new Set([
  'Open Journey (Any City)',
  'Spring Japan Trip',
  'Taiwan Cafe Week',
  'Seaside Story Series',
]);

const stages = new Set(['requested', 'writing', 'packed', 'sent', 'received']);
const statuses = new Set(['pending', 'sent', 'received']);
const reactions = new Set(['❤️', '😊', '🥹', '🌟']);

function publicText(value, maxLength) {
  if (typeof value !== 'string') return '';
  return value.trim().slice(0, maxLength);
}

function coarseCoordinate(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return Math.round(value * 4) / 4 || 0;
}

function publicCity(value) {
  const city = publicText(value, 120);
  // The old geocoder fallback stored an exact coordinate pair as the label.
  if (/^[+-]?\d+(?:\.\d+)?\s*,\s*[+-]?\d+(?:\.\d+)?$/u.test(city)) {
    return '';
  }
  return city;
}

function publicPhoto(value) {
  const photo = publicText(value, 2048);
  if (!photo) return '';
  try {
    const url = new URL(photo);
    if (url.protocol === 'https:' && !url.username && !url.password) {
      return url.href;
    }
  } catch {
    return '';
  }
  return '';
}

function projectPostcard(data) {
  const status = statuses.has(data.status) ? data.status : 'pending';
  const projection = {
    status,
    stage: status === 'received' || status === 'sent'
      ? status
      : stages.has(data.stage) ? data.stage : 'requested',
    topic: topics.has(data.topic) ? data.topic : 'General',
  };

  if (typeof data.trackingCode === 'string' && /^[A-Z0-9]{1,4}$/u.test(data.trackingCode)) {
    projection.trackingCode = data.trackingCode;
  }
  for (const field of ['requestDate', 'sentDate']) {
    const value = data[field];
    if (value instanceof Timestamp || value instanceof FieldValue) {
      projection[field] = value;
    }
  }
  if (campaigns.has(data.campaign)) projection.campaign = data.campaign;
  const city = publicCity(data.sentCity);
  if (city) projection.sentCity = city;
  if (
    Number.isFinite(data.lat) && Math.abs(data.lat) <= 90 &&
    Number.isFinite(data.lng) && Math.abs(data.lng) <= 180
  ) {
    projection.lat = coarseCoordinate(data.lat);
    projection.lng = coarseCoordinate(data.lng);
  }

  const note = publicText(data.travelerNote, 600);
  if (note) projection.travelerNote = note;
  const photo = publicPhoto(data.travelerPhotoUrl);
  if (photo) projection.travelerPhotoUrl = photo;
  if (Number.isInteger(data.etaDays) && data.etaDays >= 0 && data.etaDays <= 365) {
    projection.etaDays = data.etaDays;
  }

  const message = publicText(data.recipientMessage, 500);
  if (
    status === 'received' && data.showOnWall === true &&
    reactions.has(data.recipientReaction) && message
  ) {
    projection.showOnWall = true;
    projection.recipientReaction = data.recipientReaction;
    projection.recipientMessage = message;
  }
  return projection;
}

module.exports = { campaigns, coarseCoordinate, projectPostcard, topics };
