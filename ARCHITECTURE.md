# Kalisi — Native Flutter App Architecture

## Principle
A real native Flutter app (like WhatsApp/Telegram). No WebView. Pure Dart + Flutter widgets.
The website (kalisi.app) is separate — promotion only. This app talks to the PHP API directly.

## Stack
- Flutter (stable), Dart
- State: Riverpod (clean, testable, industry standard)
- Local DB: Drift (SQLite) — messages, contacts, personas, status
- Crypto: `cryptography` package — ECDH P-256, AES-GCM, SHA-256 (matches web)
- HTTP: `dio` — talks to https://kalisi.app/api/index.php
- Push: firebase_messaging + flutter_local_notifications
- Secure storage: flutter_secure_storage — private keys
- Routing: go_router

## Layers
lib/
  main.dart                  App entry, theme, providers
  theme/
    colors.dart              Gold/navy palette (light + dark)
    typography.dart          Inter + display font
  data/
    db/                      Drift database (tables, DAOs)
    api/                     API client (dio) — register, send, fetch, etc.
    crypto/                  ECDH/AES-GCM/SHA-256 (Dart)
    models/                  Contact, Message, Persona, Status
    repositories/            Business logic: MessageRepo, ContactRepo, AuthRepo
  features/
    onboarding/              Create @username, identity
    chats/                   Chat list + chat view
    status/                  Status/stories
    connect/                 QR, add friend, invite
    privacy/                 Settings, backup, keys
  widgets/                   Shared: avatar, bubble, dialogs

## API (unchanged — existing PHP server)
Base: https://kalisi.app/api/index.php
Actions: register, lookup, send, fetch, presence, req_send, req_list, req_act,
         status_post, status_feed, fcm_register, change_username, block, etc.

## Crypto compatibility
Must match the web app's format so messages interoperate:
- ECDH P-256 keypair per persona
- Derive shared secret → AES-GCM 256
- SHA-256 deletion receipts
- Public keys shared as JWK

## Build order (screen by screen)
1. Foundation: theme, DB schema, API client, crypto, models  ← START HERE
2. Onboarding (create identity)
3. Chat list
4. Chat view (send/receive, bubbles, reactions)
5. Connect (QR, add friend)
6. Status
7. Privacy/settings
8. Push, backup, polish
