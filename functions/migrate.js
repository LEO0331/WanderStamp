'use strict';

const { createHash, randomBytes } = require('node:crypto');
const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { FieldPath, FieldValue, getFirestore, Timestamp } = require('firebase-admin/firestore');
const { projectPostcard } = require('./projection.js');

function parseOptions(args) {
  let projectId;
  let apply = false;
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--project' && projectId === undefined) {
      projectId = args[++index];
    } else if (args[index] === '--apply' && !apply) {
      apply = true;
    } else {
      throw new Error('Invalid migration arguments');
    }
  }
  if (!projectId || !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/u.test(projectId)) {
    throw new Error('Specify the exact Firebase project ID');
  }
  return { projectId, apply };
}

async function migratePostcard(db, ref) {
  const marker = db.collection('postcardProjection').doc(ref.id);
  return db.runTransaction(async (transaction) => {
    const [source, checkpoint] = await transaction.getAll(ref, marker);
    if (!source.exists || checkpoint.exists) return false;

    const data = source.data();
    const publicRef = db.collection('postcardTracking').doc();
    const oldCode = ref.id.slice(-4).toUpperCase();
    const trackingCode = /^[A-Z0-9]{1,4}$/u.test(oldCode)
      ? oldCode
      : publicRef.id.slice(-4).toUpperCase();
    const requestDate = data.requestDate instanceof Timestamp
      ? data.requestDate
      : source.createTime;
    const projection = projectPostcard({ ...data, trackingCode, requestDate });

    const updates = { publicId: publicRef.id, trackingCode, requestDate };
    if (projection.status !== 'received') {
      const receiptToken = randomBytes(32).toString('base64url');
      const receiptHash = createHash('sha256').update(receiptToken).digest('hex');
      updates.receiptToken = receiptToken;
      transaction.create(db.collection('postcardReceipts').doc(receiptHash), {
        postcardId: ref.id,
      });
    } else if ('receiptToken' in data) {
      updates.receiptToken = FieldValue.delete();
    }
    if ('feedbackTokenHash' in data) updates.feedbackTokenHash = FieldValue.delete();

    for (const field of ['lat', 'lng', 'sentCity']) {
      if (field in data) updates[field] = projection[field] ?? FieldValue.delete();
    }
    transaction.create(publicRef, projection);
    transaction.create(marker, { publicId: publicRef.id });
    transaction.update(ref, updates);
    return true;
  });
}

async function migrate(db, { apply }) {
  const postcards = db.collection('postcards');
  if (!apply) {
    const count = await postcards.count().get();
    return { scanned: count.data().count, migrated: 0 };
  }

  const query = postcards.orderBy(FieldPath.documentId()).select().limit(100);
  let page = await query.get();
  let scanned = 0;
  let migrated = 0;
  while (!page.empty) {
    for (const doc of page.docs) {
      scanned++;
      if (await migratePostcard(db, doc.ref)) migrated++;
    }
    page = await query.startAfter(page.docs.at(-1)).get();
  }
  return { scanned, migrated };
}

async function main() {
  const options = parseOptions(process.argv.slice(2));
  initializeApp({
    projectId: options.projectId,
    credential: applicationDefault(),
  });
  const { scanned, migrated } = await migrate(getFirestore(), options);
  if (options.apply) {
    console.log('Migration complete. Scanned %d records, migrated %d.', scanned, migrated);
  } else {
    console.log('Dry run complete. Found %d records, wrote 0.', scanned);
  }
}

if (require.main === module) {
  main().catch(() => {
    console.error('Migration failed. Run with --project <project-id> [--apply]. Verify Application Default Credentials and project access, then retry.');
    process.exitCode = 1;
  });
}

module.exports = { migrate, migratePostcard, parseOptions };
