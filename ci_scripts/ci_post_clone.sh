#!/usr/bin/env bash
set -euo pipefail

# Xcode Cloud can't show the "Trust & Enable" prompt for package plugins or macros.
# Note: "Validatation" is Apple's typo, and it's required.
defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
