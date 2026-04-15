#!/usr/bin/env bash

# Project-local policy for `./scripts/policy_scan.sh`.
#
# Use this file to decide which automation surfaces are allowed in this repo.

# Fail on `do shell script` by default.
POLICY_FORBID_DO_SHELL_SCRIPT=1

# Fail on UI scripting via System Events by default.
POLICY_FORBID_SYSTEM_EVENTS=1

# If you want to restrict target apps, add them to POLICY_ALLOW_TELL_APPS and set
# POLICY_REQUIRE_TELL_ALLOWLIST=1.
POLICY_REQUIRE_TELL_ALLOWLIST=0
POLICY_ALLOW_TELL_APPS=(
  # "Mail"
  # "Safari"
)

POLICY_DENY_REGEX=(
  # Add project-specific deny patterns here.
)
