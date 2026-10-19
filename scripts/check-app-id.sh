#!/usr/bin/env bash
# Fails if the Android applicationId or iOS bundle identifier is not com.tursinalabs.dailylah.
# The ID is permanent once published on Google Play / App Store, so CI guards it.
# Usage: ./scripts/check-app-id.sh   (run from repo root)
set -euo pipefail

APP_ID="com.tursinalabs.dailylah"
fail=0

gradle=""
for f in app/android/app/build.gradle.kts app/android/app/build.gradle; do
  [[ -f "$f" ]] && gradle="$f" && break
done

if [[ -n "$gradle" ]]; then
  for field in applicationId namespace; do
    if ! grep -Eq "${field}[[:space:]=]+\"${APP_ID}\"" "$gradle"; then
      echo "ERROR: ${gradle}: ${field} must be \"${APP_ID}\""
      fail=1
    fi
  done
else
  echo "skip: no Android project yet (run flutter create in app/)"
fi

pbx="app/ios/Runner.xcodeproj/project.pbxproj"
if [[ -f "$pbx" ]]; then
  if ! grep -q "PRODUCT_BUNDLE_IDENTIFIER = ${APP_ID};" "$pbx"; then
    echo "ERROR: ${pbx}: PRODUCT_BUNDLE_IDENTIFIER must be ${APP_ID}"
    fail=1
  fi
else
  echo "skip: no iOS project yet"
fi

[[ $fail -eq 0 ]] && echo "OK: app id is ${APP_ID}"
exit $fail
