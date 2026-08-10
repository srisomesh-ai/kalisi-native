#!/usr/bin/env python3
"""Wire the Google Services plugin into the generated Android gradle files."""
import sys, re, os

# 1. app-level build.gradle.kts — apply the plugin
app = "android/app/build.gradle.kts"
s = open(app).read()
if "com.google.gms.google-services" not in s:
    # add to plugins { } block
    s = re.sub(r'(plugins\s*\{)', r'\1\n    id("com.google.gms.google-services")', s, count=1)
    open(app, "w").write(s)
    print("app plugin added")
else:
    print("app plugin already present")

# 2. settings.gradle.kts — declare the plugin version
settings = "android/settings.gradle.kts"
if os.path.exists(settings):
    s = open(settings).read()
    if "com.google.gms.google-services" not in s:
        # add into the plugins block that has flutter/android plugins
        s = re.sub(r'(id\("com\.android\.application"\)[^\n]*\n)',
                   r'\1    id("com.google.gms.google-services") version "4.4.2" apply false\n',
                   s, count=1)
        open(settings, "w").write(s)
        print("settings plugin declared")
    else:
        print("settings plugin already present")
else:
    print("no settings.gradle.kts")
