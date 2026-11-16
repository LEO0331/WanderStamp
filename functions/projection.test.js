'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { FieldValue, Timestamp } = require('firebase-admin/firestore');
const { parseOptions } = require('./migrate.js');
const { projectPostcard } = require('./projection.js');

test('tracking projection exposes only allowed fields and coarse coordinates', () => {
  const requestDate = Timestamp.fromMillis(100);
  const sentDate = FieldValue.serverTimestamp();
  const projection = projectPostcard({
    trackingCode: 'A2B3',
    status: 'sent',
    requestDate,
    sentDate,
    lat: 15.412,
    lng: -20.318,
    sentCity: '15.41, -20.32',
    topic: 'untrusted free text',
    campaign: 'untrusted free text',
    receiverName: 'private',
    address: 'private',
    giftFromName: 'private',
    giftMessage: 'private',
    receiptToken: 'private',
    recipientMessage: 'private',
    recipientReaction: '❤️',
    showOnWall: false,
  });
  assert.deepEqual(projection, {
    trackingCode: 'A2B3',
    status: 'sent',
    stage: 'sent',
    topic: 'General',
    requestDate,
    sentDate,
    lat: 15.5,
    lng: -20.25,
  });
});

test('wall projection requires explicit consent and receipt', () => {
  const feedback = {
    recipientMessage: ' A public note ',
    recipientReaction: '❤️',
  };
  assert.equal(projectPostcard({ ...feedback, status: 'received' }).showOnWall, undefined);
  assert.equal(projectPostcard({ ...feedback, status: 'sent', showOnWall: true }).showOnWall, undefined);
  assert.deepEqual(
    projectPostcard({ ...feedback, status: 'received', showOnWall: true }),
    {
      status: 'received',
      stage: 'received',
      topic: 'General',
      showOnWall: true,
      recipientMessage: 'A public note',
      recipientReaction: '❤️',
    },
  );
});

test('projection rejects malformed legacy fields', () => {
  assert.deepEqual(projectPostcard({
    trackingCode: ['AB12'],
    status: 'unexpected',
    stage: 'unexpected',
    travelerPhotoUrl: 'https://username:password@example.test/image',
    lat: 1,
    lng: 190,
    requestDate: { arbitrary: 'value' },
  }), { status: 'pending', stage: 'requested', topic: 'General' });
});

test('migration requires an explicit project and write flag', () => {
  assert.throws(() => parseOptions(['--apply']));
  assert.throws(() => parseOptions(['--project', 'demo-wanderstamp', '--unknown']));
  assert.deepEqual(parseOptions(['--project', 'demo-wanderstamp']), {
    projectId: 'demo-wanderstamp',
    apply: false,
  });
  assert.deepEqual(parseOptions(['--project', 'demo-wanderstamp', '--apply']), {
    projectId: 'demo-wanderstamp',
    apply: true,
  });
});
