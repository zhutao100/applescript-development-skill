#!/usr/bin/env bash

# Default policy for `scripts/policy_scan.sh`.
#
# This file is intentionally Bash-only (it is sourced). Keep it declarative.

# If 1, fail when `do shell script` is detected.
POLICY_FORBID_DO_SHELL_SCRIPT=1

# If 1, fail when `System Events` UI scripting is detected.
POLICY_FORBID_SYSTEM_EVENTS=1

# If 1 and POLICY_ALLOW_TELL_APPS is non-empty, fail when a script sends Apple Events
# to a target application not listed in POLICY_ALLOW_TELL_APPS.
POLICY_REQUIRE_TELL_ALLOWLIST=0

# Allowed target applications for `tell application ...` / `tell app ...`.
#
# Notes:
# - Values should match what appears in script source: app name, or bundle ID if using
#   `tell application id "com.example"`.
# - Leave empty to allow any target app (the scanner will still report what it finds).
POLICY_ALLOW_TELL_APPS=(
  # "Mail"
  # "Safari"
  # "com.apple.mail"
)

# Extended regex patterns that always fail if matched.
# Keep patterns conservative to avoid false positives from comments.
POLICY_DENY_REGEX=(
  # Add project-specific deny patterns here.
)
