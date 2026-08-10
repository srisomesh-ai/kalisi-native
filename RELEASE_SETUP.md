# Kalisi — Play Store Release Setup

The CI already builds a release AAB, but it is **unsigned**. Google Play requires a
signed AAB with a key that stays the SAME for every future update. Do this once.

## Step 1 — Create your keystore (on your computer, keep it SAFE forever)

You need Java installed (or use Android Studio). Run:

```
keytool -genkey -v -keystore kalisi-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias kalisi
```

It will ask for:
- a keystore password (remember it)
- a key password (can be same)
- your name / org (any values)

⚠️ BACK UP `kalisi-release.jks` AND THE PASSWORDS. If you lose them you can never
update the app on Play again — you'd have to publish a new app.

## Step 2 — Turn the keystore into text (base64)

```
base64 kalisi-release.jks > kalisi-release.txt      # Mac/Linux
# Windows PowerShell:
[Convert]::ToBase64String([IO.File]::ReadAllBytes("kalisi-release.jks")) > kalisi-release.txt
```

## Step 3 — Add 4 secrets to GitHub

Go to: github.com/srisomesh-ai/kalisi-native → Settings → Secrets and variables →
Actions → "New repository secret". Add these four:

| Secret name         | Value                                    |
|---------------------|------------------------------------------|
| KEYSTORE_BASE64     | (paste the whole contents of kalisi-release.txt) |
| KEYSTORE_PASSWORD   | your keystore password                   |
| KEY_ALIAS           | kalisi                                   |
| KEY_PASSWORD        | your key password                        |

## Step 4 — Re-run the build

Push anything (or re-run the latest Action). The CI will detect the secrets and
produce a **signed** `kalisi-release-aab`. That .aab is what you upload to the
Play Console.

## Step 5 — Play Console

1. Create a Google Play Developer account ($25 one-time): play.google.com/console
2. Create app → fill store listing (name: Kalisi, description, screenshots, icon)
3. Upload the signed .aab under a Production (or Internal testing) release
4. Complete the content rating, privacy policy, data safety form
5. Submit for review

Note: for an E2E messenger, the Data Safety form should state that messages are
encrypted in transit and not readable by the server.
