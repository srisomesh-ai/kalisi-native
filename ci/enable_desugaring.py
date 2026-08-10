#!/usr/bin/env python3
"""Enable Java 8+ core library desugaring (needed by flutter_local_notifications)
and add the google-services plugin, in the Flutter-generated Android gradle files."""
import re, sys, os

app = "android/app/build.gradle.kts"
if not os.path.exists(app):
    print("no build.gradle.kts, skipping"); sys.exit(0)

s = open(app).read()

# 1) isCoreLibraryDesugaringEnabled inside compileOptions
if "isCoreLibraryDesugaringEnabled" not in s:
    if re.search(r"compileOptions\s*\{", s):
        s = re.sub(r"(compileOptions\s*\{)",
                   r"\1\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
    else:
        # add a compileOptions block right after "android {"
        s = re.sub(r"(android\s*\{\s*\n)",
                   r"\1    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n"
                   r"        sourceCompatibility = JavaVersion.VERSION_1_8\n"
                   r"        targetCompatibility = JavaVersion.VERSION_1_8\n    }\n",
                   s, count=1)

# 2) the desugaring dependency
if "desugar_jdk_libs" not in s:
    if re.search(r"\ndependencies\s*\{", s):
        s = re.sub(r"(\ndependencies\s*\{)",
                   r'\1\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',
                   s, count=1)
    else:
        s += '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'

# 3) google-services plugin (Firebase)
if "com.google.gms.google-services" not in s:
    s = re.sub(r'(plugins\s*\{)',
               r'\1\n    id("com.google.gms.google-services")', s, count=1)

# 4) applicationId + namespace must match the Firebase config
s = re.sub(r'applicationId\s*=\s*"[^"]*"', 'applicationId = "com.messenger.app"', s)
s = re.sub(r'namespace\s*=\s*"[^"]*"', 'namespace = "com.messenger.app"', s)

open(app, "w").write(s)
print("patched", app)

# 4) settings.gradle.kts needs the google-services classpath plugin declared
settings = "android/settings.gradle.kts"
if os.path.exists(settings):
    t = open(settings).read()
    if "com.google.gms.google-services" not in t:
        t = re.sub(r'(plugins\s*\{)',
                   r'\1\n    id("com.google.gms.google-services") version "4.4.2" apply false',
                   t, count=1)
        open(settings, "w").write(t)
        print("patched", settings)

# 5) Move MainActivity to the new package so it matches applicationId
import glob, shutil
srcs = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True)
if srcs:
    target_dir = "android/app/src/main/kotlin/com/messenger/app"
    os.makedirs(target_dir, exist_ok=True)
    body = open(srcs[0]).read()
    body = re.sub(r"^package .*$", "package com.messenger.app", body, count=1, flags=re.M)
    open(os.path.join(target_dir, "MainActivity.kt"), "w").write(body)
    # remove the old copy if it's in a different folder
    if os.path.dirname(srcs[0]).rstrip("/") != target_dir:
        try:
            os.remove(srcs[0])
        except OSError:
            pass
    print("MainActivity moved to com.messenger.app")
