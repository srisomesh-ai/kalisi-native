# Kalisi — Native Flutter App

A real native Flutter messenger (not a WebView). Private, no phone number, E2E encrypted.
The website (kalisi.app) is separate — promotion only. This app talks to the PHP API directly.

See ARCHITECTURE.md for the full design.

## Status: Foundation + Onboarding + Chats list (in progress)
Building screen by screen:
- [x] Theme (light/dark, gold/navy, Inter + Bricolage)
- [x] SQLite database (Drift): personas, contacts, messages
- [x] Crypto (ECDH P-256 / AES-GCM / SHA-256) matching the web
- [x] API client (dio → kalisi.app/api)
- [x] Onboarding (create @username identity)
- [x] Home shell (4-tab nav)
- [x] Chats list
- [ ] Chat view (send/receive, bubbles, reactions)
- [ ] Connect (QR, add friend)
- [ ] Status
- [ ] Privacy/settings
- [ ] Push, backup

## Build
CI (GitHub Actions) generates the Drift code and builds the APK on every push.
