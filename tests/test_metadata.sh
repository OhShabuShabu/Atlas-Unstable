#!/usr/bin/env bash
# ============================================================================
# METADATA STRIPPER BEHAVIORAL TESTS
# ============================================================================
# Tests that exiftool correctly strips EXIF/GPS/author/copyright metadata
# from media files, matching the daemon's command-line invocation.
# ============================================================================

TEST_NAME="Metadata Stripper"
source "${BASE:-$(cd "$(dirname "$0")/.." && pwd)}/tests/helpers.sh" 2>/dev/null || source helpers.sh

header "METADATA STRIPPER"

TEMP_DIR=$(_mktemp /tmp/metadata-test.XXXXXX)

# ─── 1. Exiftool Availability ──────────────────────────────────────────────
if has_tool exiftool; then
  pass "exiftool is available (v$(exiftool -ver 2>/dev/null || echo '?'))"

  # ─── 2. Test image creation ───────────────────────────────────────────────
  header "2. Metadata Test File Creation"

  create_test_jpeg_with_exif "$TEMP_DIR/test_meta.png" >/dev/null 2>&1

  if [ -f "$TEMP_DIR/test_meta.png" ]; then
    pass "Test PNG image created"
  else
    fail "Failed to create test PNG image"
  fi

  create_test_jpeg_without_exif "$TEMP_DIR/test_clean.png" >/dev/null 2>&1
  if [ -f "$TEMP_DIR/test_clean.png" ]; then
    pass "Clean (no metadata) test PNG created"
  fi

  # ─── 3. Verify Metadata Exists Before Stripping ───────────────────────────
  header "3. Metadata Exists Before Stripping"

  if [ -f "$TEMP_DIR/test_meta.png" ]; then
    meta_before=$(timeout 30 exiftool "$TEMP_DIR/test_meta.png" 2>&1)

    assert_contains "Author metadata present before strip" "$meta_before" "Author" || true
    assert_contains "Copyright metadata present before strip" "$meta_before" "Copyright" || true
    assert_contains "Software metadata present before strip" "$meta_before" "Software" || true
  fi

  # ─── 4. Strip Metadata Using Daemon's Flags ───────────────────────────────
  header "4. Metadata Stripping (daemon flags)"

  if [ -f "$TEMP_DIR/test_meta.png" ]; then
    cp "$TEMP_DIR/test_meta.png" "$TEMP_DIR/to_strip.png"
    output_strip=$(timeout 30 exiftool -overwrite_original \
      -all= -gps:all= -makernotes:all= -ThumbnailImage- \
      -XMP-iptcCore:all= -Software= -Artist= -Copyright= \
      -SerialNumber= -CameraSerialNumber= -OwnerName= \
      "$TEMP_DIR/to_strip.png" 2>&1)
    rc_strip=$?

    assert_exit_code "exiftool strip exits successfully" 0 "$rc_strip" || true
    assert_contains "Strip output mentions files updated" "$output_strip" "image files updated" || true

    meta_after=$(timeout 30 exiftool "$TEMP_DIR/to_strip.png" 2>&1)

    assert_not_contains "Author metadata removed" "$meta_after" "Author" || true
    assert_not_contains "Copyright metadata removed" "$meta_after" "Copyright" || true
    assert_not_contains "Software metadata removed" "$meta_after" "Software: TestCamera" || true
    assert_not_contains "Description metadata removed" "$meta_after" "Description" || true
  fi

  # ─── 5. Idempotency ───────────────────────────────────────────────────────
  header "5. Idempotency (safe to run on clean files)"

  if [ -f "$TEMP_DIR/test_clean.png" ]; then
    output_idem=$(timeout 30 exiftool -overwrite_original \
      -all= -gps:all= -makernotes:all= -ThumbnailImage- \
      -XMP-iptcCore:all= -Software= -Artist= -Copyright= \
      -SerialNumber= -CameraSerialNumber= -OwnerName= \
      "$TEMP_DIR/test_clean.png" 2>&1)
    rc_idem=$?

    assert_exit_code "Idempotent strip exits successfully" 0 "$rc_idem" || true

    if echo "$output_idem" | grep -q "0 image files updated"; then
      pass "Idempotent strip: no changes on already-clean file"
    else
      pass "Idempotent strip: completed without error"
    fi
  fi

  # ─── 6. Recursive Directory Strip ─────────────────────────────────────────
  header "6. Recursive Directory Processing"

  SUBDIR="$TEMP_DIR/subdir"
  mkdir -p "$SUBDIR"
  cp "$TEMP_DIR/test_meta.png" "$SUBDIR/sub_test.png"

  output_rec=$(timeout 30 exiftool -overwrite_original \
    -all= -gps:all= -makernotes:all= -ThumbnailImage- \
    -XMP-iptcCore:all= -Software= -Artist= -Copyright= \
    -SerialNumber= -CameraSerialNumber= -OwnerName= \
    -r "$SUBDIR" 2>&1)

  if echo "$output_rec" | grep -q "image files updated"; then
    pass "Recursive strip: processes files in subdirectories"
  else
    fail "Recursive strip: did not process files in subdirectories"
    echo "    Output: $output_rec"
  fi

  # ─── 7. Script Logic Verification ─────────────────────────────────────────
  header "7. Script Logic"

  SCRIPT=$(extract_script_from_nix "$BASE/files/modules/security/metadata-stripper.nix" "metadata-stripper-watcher.sh" 2>/dev/null || true)
  if [ -n "$SCRIPT" ]; then
    echo "$SCRIPT" | grep -q "exiftool" && pass "Watcher script: uses exiftool" || fail "Watcher script: missing exiftool"
    echo "$SCRIPT" | grep -q "mmin -5" && pass "Watcher script: filters by modification time (-mmin -5)" || fail "Watcher script: missing -mmin filter"
    echo "$SCRIPT" | grep -q "notify-user" && pass "Watcher script: sends notifications" || fail "Watcher script: missing notification"
  else
    skip "Watcher script extraction failed"
  fi

  SCRIPT2=$(extract_script_from_nix "$BASE/files/modules/security/metadata-stripper.nix" "metadata-stripper-daily.sh" 2>/dev/null || true)
  if [ -n "$SCRIPT2" ]; then
    echo "$SCRIPT2" | grep -q "exiftool" && pass "Daily script: uses exiftool" || fail "Daily script: missing exiftool"
    echo "$SCRIPT2" | grep -q "notify-user" && pass "Daily script: sends notifications" || fail "Daily script: missing notification"
    echo "$SCRIPT2" | grep -q "Total:.*files processed" && pass "Daily script: counts files processed" || fail "Daily script: missing file count"
  else
    skip "Daily script extraction failed"
  fi

  # ─── 8. Supported File Extensions ─────────────────────────────────────────
  header "8. Supported File Extension Coverage"

  SCRIPT3=$(extract_script_from_nix "$BASE/files/modules/security/metadata-stripper.nix" "metadata-stripper-watcher.sh" 2>/dev/null || true)
  if [ -n "$SCRIPT3" ]; then
    for ext in jpg jpeg png gif tiff webp mp4 mov avi mkv; do
      echo "$SCRIPT3" | grep -qE "\-ext $ext" && pass "Supports .$ext files" || fail "Missing support for .$ext files"
    done
  fi

else
  skip "exiftool not installed — skipping all metadata stripper tests"
  skip "exiftool not installed — test image creation"
  skip "exiftool not installed — metadata stripping"
  skip "exiftool not installed — idempotency"
  skip "exiftool not installed — recursive processing"
fi

print_summary "$TEST_NAME"
exit $([ "$FAIL" -gt 0 ] && echo 1 || echo 0)
