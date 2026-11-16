# Session Handoff

Security hardening is implemented on `codex/security-hardening`. The public tracker reads `postcardTracking`. Private records are admin-only and all application writes go through callable Functions.

- Verified `flutter pub get`, `flutter analyze --no-pub`, all 66 Flutter tests, the Web release build, all 11 local Firestore Emulator tests, and `actionlint`.
- Production configuration, data migration, and live browser/device smoke tests remain pending.
- Follow [the Firebase rollout runbook](docs/security-rollout.md) before merging into `main`. The existing `W-XXXX` IDs still track postcards. Recipients who have only an old code need a private confirmation link from the operator.
