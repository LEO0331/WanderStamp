# Deploying the Firestore security changes

The Pages workflow deploys the web build on a push to `main`. Keep the branch unmerged until the Firebase cutover is ready. The old web build reads and writes the legacy collection directly, so allow a short maintenance window between applying the restrictive rules and publishing the new build.

## Prepare

1. Verify the target Firebase project, review its current Rules, and preserve an access-controlled backup before migration. Review legacy traveler notes, photo URLs and previously opted-in wall feedback for personal data. Confirm the new tracking and internal collections do not contain unexpected documents.
2. Install Node.js 22, the Firebase CLI, and the Functions dependencies with `npm --prefix functions ci`. Set up Application Default Credentials with permission to manage the target project's Firebase Auth claim and migrate Firestore. Use the credential locally and keep it out of Git.
3. Grant the `admin` claim only to the existing operator's Firebase Auth UID. Sign out and sign in again after granting access.

   ```sh
   node functions/set-admin.js --project <project-id> --uid <admin-uid> --grant
   ```

4. On a Firebase project with Cloud Functions billing enabled, create an independent random secret of at least 32 characters when prompted.

   ```sh
   firebase functions:secrets:set POSTCARD_RATE_LIMIT_KEY --project <project-id>
   ```

5. Optional before launch: register the Web app for Firebase App Check with reCAPTCHA v3 for the Pages domain, and set the public site key in GitHub Actions repository variable `APP_CHECK_SITE_KEY`. Enforcement starts disabled so you can check valid traffic before requiring a token.

## Cut over

1. Apply the restrictive Firestore rules before running the migration or deploying the Functions. Wait for the rules to take effect and close legacy browser sessions.

   ```sh
   firebase deploy --only firestore:rules --project <project-id>
   ```

2. Run the dry run, then apply the backfill. It reports counts, writes the independent public documents and generates new private receipt credentials. It can be rerun safely.

   ```sh
   node functions/migrate.js --project <project-id>
   node functions/migrate.js --project <project-id> --apply
   ```

3. Deploy the callable Functions.

   ```sh
   firebase deploy --only functions --project <project-id>
   ```

4. Enable a Firestore TTL policy on `expiresAt` for both `postcardRateLimits` and `postcardFeedbackTokens`. The Functions enforce expiration independently of background cleanup.
5. Merge or fast-forward the reviewed branch to `main` and check the Pages workflow. Reload existing browser/PWA tabs. Check public tracking and your admin login. Use an explicitly synthetic request when verifying the request, send, private receipt, and feedback flow in a staging project.

Existing `W-XXXX` codes still work for public tracking. Public cards display the tracking code instead of the recipient's name. For a postcard already in transit, use **Copy Recipient Confirmation Link** on that card in the dashboard and send the link directly to the recipient. It is a bearer credential until consumed. After receipt, feedback uses a separate credential valid for one hour and one submission.

If the Pages release must be rolled back, keep the restrictive rules in place. Rolling back to the legacy browser build requires a maintenance window until a compatible build is available. Do not re-enable public access to the private collection.

After observing valid traffic across the clients you support, set `ENFORCE_APP_CHECK=true` in the Functions environment and redeploy to enforce App Check for the callables. The current App Check client setup is Web-only, so keep enforcement off if you still serve native builds without an App Check provider.

## Local verification

With Node.js 22, the Firebase CLI, and a Java runtime supported by the Firestore emulator, run:

```sh
npm --prefix functions ci
firebase emulators:exec --project demo-wanderstamp --only firestore "npm --prefix functions test"
```
