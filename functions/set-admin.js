'use strict';

const { applicationDefault, initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

async function main(args) {
  const [projectFlag, projectId, uidFlag, uid, action] = args;
  if (args.length !== 5 || projectFlag !== '--project' || uidFlag !== '--uid' ||
      !/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(projectId) ||
      !uid || uid.length > 128 || !['--grant', '--revoke'].includes(action)) {
    throw new Error('Invalid arguments');
  }

  initializeApp({ projectId, credential: applicationDefault() });
  const auth = getAuth();
  const user = await auth.getUser(uid);
  const claims = { ...user.customClaims };
  if (action === '--grant') {
    claims.admin = true;
  } else {
    delete claims.admin;
  }
  await auth.setCustomUserClaims(uid, claims);
  await auth.revokeRefreshTokens(uid);
  console.log(action === '--grant' ? 'Admin access granted.' : 'Admin access revoked.');
}

main(process.argv.slice(2)).catch(() => {
  console.error('Admin access update failed. Use --project <project-id> --uid <uid> --grant or --revoke and verify your Application Default Credentials.');
  process.exitCode = 1;
});
