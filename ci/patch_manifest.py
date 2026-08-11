#!/usr/bin/env python3
"""Patch the generated AndroidManifest.xml.

- adds the permissions the app needs
- disables Impeller (its renderer can leave blank/ghost screens when the
  app is resumed from the background on some Android devices)
"""
import sys, re

path = sys.argv[1] if len(sys.argv) > 1 else "android/app/src/main/AndroidManifest.xml"
s = open(path).read()

PERMS = [
    "android.permission.INTERNET",
    "android.permission.RECORD_AUDIO",
    "android.permission.CAMERA",
    "android.permission.VIBRATE",
    "android.permission.POST_NOTIFICATIONS",
]

# 1) permissions, right after the <manifest ...> tag
missing = [p for p in PERMS if p not in s]
if missing:
    block = "".join(
        '\n    <uses-permission android:name="%s"/>' % p for p in missing
    )
    s = re.sub(r"(<manifest[^>]*>)", r"\1" + block, s, count=1)

# 2) disable Impeller — must sit inside <application>
if "EnableImpeller" not in s:
    meta = (
        '\n        <meta-data\n'
        '            android:name="io.flutter.embedding.android.EnableImpeller"\n'
        '            android:value="false" />'
    )
    s = re.sub(r"(<application[^>]*>)", r"\1" + meta, s, count=1)

# 3) app label
s = s.replace('android:label="kalisi"', 'android:label="Kalisi"')

open(path, "w").write(s)
print("manifest patched")
for p in PERMS:
    print("  perm:", p, "ok" if p in s else "MISSING")
print("  impeller disabled:", "EnableImpeller" in s)
