#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Define Flutter version
FLUTTER_VERSION="3.22.1" # You can change this to your desired version

# Define installation directory
INSTALL_DIR="$HOME/flutter"

# Clean up any previous installation
if [ -d "$INSTALL_DIR" ]; then
  echo "Removing previous Flutter installation..."
  rm -rf "$INSTALL_DIR"
fi

# Create installation directory
mkdir -p "$HOME/sdk" # Create sdk directory if it doesn't exist
cd "$HOME/sdk"

# Download Flutter SDK
echo "Downloading Flutter SDK version $FLUTTER_VERSION..."
git clone https://github.com/flutter/flutter.git --branch $FLUTTER_VERSION $INSTALL_DIR

# Add Flutter to PATH
echo "Adding Flutter to PATH..."
export PATH="$INSTALL_DIR/bin:$PATH"

# Pre-download development binaries and agree to licenses
echo "Running flutter doctor..."
flutter doctor -v

# Enable web support
echo "Enabling Flutter web support..."
flutter config --enable-web

# Verify Flutter configuration
echo "Verifying Flutter configuration..."
flutter doctor -v

echo "Flutter installation and web configuration complete."
echo "To use Flutter in this session, run: export PATH=\"\$HOME/flutter/bin:\$PATH\""
echo "For permanent use, add this line to your shell configuration file (e.g., ~/.bashrc, ~/.zshrc)."
