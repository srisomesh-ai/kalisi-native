#!/usr/bin/env python3
"""Wire release signing into the generated android/app/build.gradle.kts."""
import sys, re

path = sys.argv[1] if len(sys.argv) > 1 else "android/app/build.gradle.kts"
s = open(path).read()

if "key.properties" in s:
    print("signing already wired")
    sys.exit(0)

header = '''import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

'''
s = header + s

sign_block = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
'''
s = re.sub(r'(android\s*\{\s*\n)', r'\1' + sign_block, s, count=1)
s = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
           'signingConfig = signingConfigs.getByName("release")', s)

open(path, "w").write(s)
print("signing wired into", path)
