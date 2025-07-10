#!/bin/bash
#
# Script to set up the Flutter SDK environment for Jules (AI Agent)
# This script is intended to be run in a Linux-based sandbox environment.
# It will download the Flutter SDK if not already present, set PATH,
# configure for Web and Linux Desktop ONLY, and run flutter doctor.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
FLUTTER_SDK_DIR="$HOME/flutter_sdk"
FLUTTER_CHANNEL="stable" # Specify channel: stable, beta, master
FLUTTER_VERSION="latest" # Specify version, e.g., "3.19.0" or "latest" for channel
# FLUTTER_SDK_URL_BASE="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux" # Kept for reference, but git clone is preferred

# --- Helper Functions ---
log_info() {
    echo "INFO: $1"
}

log_warn() {
    echo "WARN: $1" >&2
}

log_error() {
    echo "ERROR: $1" >&2
}

# --- Prerequisite Checks ---
# For Jules Agent: These dependencies are crucial for web and Linux desktop development.
# The script attempts to install them using apt-get if available.
# If apt-get is not available or fails, the environment must have these pre-installed.
log_info "Ensuring prerequisites for web and Linux desktop development are installed..."
if command -v apt-get >/dev/null; then
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null; then
        SUDO_CMD="sudo"
    elif [ "$(id -u)" -ne 0 ]; then
        log_error "Not root and sudo not found. Cannot install dependencies. Please ensure they are pre-installed."
        # Allow to continue, flutter doctor will report missing deps.
    fi

    log_info "Updating package lists (requires sudo if not root)..."
    $SUDO_CMD apt-get update -y

    log_info "Installing dependencies: curl, git, tar, xz-utils, unzip, libglu1-mesa, libgtk-3-dev, pkg-config, clang, cmake, ninja-build, chromium-browser, mesa-utils (requires sudo if not root)"
    # Using chromium-browser as it's generally available in default repos.
    # mesa-utils for eglinfo (graphics info, useful for Linux desktop)
    if ! $SUDO_CMD apt-get install -y curl git tar xz-utils unzip libglu1-mesa libgtk-3-dev pkg-config clang cmake ninja-build chromium-browser mesa-utils; then
        log_error "Failed to install some or all system dependencies. Flutter Doctor may report issues."
    else
        log_info "System dependencies installation attempt complete."
    fi

    # Set CHROME_EXECUTABLE based on common browser commands
    if command -v chromium-browser >/dev/null; then
        export CHROME_EXECUTABLE="chromium-browser"
        log_info "CHROME_EXECUTABLE set to chromium-browser"
    elif command -v google-chrome >/dev/null; then # Fallback to google-chrome
        export CHROME_EXECUTABLE="google-chrome"
        log_info "CHROME_EXECUTABLE set to google-chrome"
    elif command -v chromium >/dev/null; then # Fallback to chromium (e.g. snap package)
        export CHROME_EXECUTABLE="chromium"
        log_info "CHROME_EXECUTABLE set to chromium"
    else
        log_warn "Neither chromium-browser, google-chrome, nor chromium found after attempting install. Web support may fail or require manual CHROME_EXECUTABLE setup."
    fi
else
    log_warn "apt-get not found. Assuming essential dependencies (curl, git, tar, xz-utils, unzip, libglu1-mesa, libgtk-3-dev, pkg-config, clang, cmake, ninja-build, a Chrome/Chromium browser, mesa-utils) are already installed."
fi

# Check for DISPLAY variable, important for Linux desktop UI.
# For Jules Agent: If Linux desktop apps with UI are tested, DISPLAY needs to be correctly configured in the VM.
# If DISPLAY is not set, and we are not already inside an xvfb-run session (indicated by XVFB_RUN_PID),
# re-execute the script under xvfb-run.
if [ -z "$DISPLAY" ] && [ -z "$XVFB_RUN_PID" ]; then
    log_info "DISPLAY not set and not in Xvfb. Re-executing script with xvfb-run..."
    # Construct the command to re-execute the script with all original arguments
    # Using the absolute path of the script and "$@" for all arguments
    script_path=$(readlink -f "$0")
    exec xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" "$script_path" "$@"
fi

# If DISPLAY is set (either by user or by xvfb-run), log it.
if [ -n "$DISPLAY" ]; then
    log_info "DISPLAY environment variable is set to: $DISPLAY"
else
    # This case should ideally not be reached if xvfb-run is working correctly.
    log_warn "DISPLAY environment variable is not set, and xvfb-run did not set it. UI operations may fail."
fi


# --- Main Setup Logic ---

# 1. Determine Flutter SDK source
# For Jules Agent: Using git clone is preferred for flexibility with channels/versions.
if [ "$FLUTTER_VERSION" == "latest" ]; then
    log_info "Using git to clone the latest from Flutter channel: $FLUTTER_CHANNEL."
else
    log_info "Specific version requested: $FLUTTER_VERSION. Will use git clone and checkout."
fi

# 2. Install or Update Flutter SDK
if [ -d "$FLUTTER_SDK_DIR/bin/flutter" ]; then
    log_info "Flutter SDK already found at $FLUTTER_SDK_DIR."
    # Basic check: if directory exists, assume it's managed or will be updated by flutter commands.
else
    log_info "Flutter SDK not found. Cloning from GitHub (channel: $FLUTTER_CHANNEL)..."
    if ! git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"; then
        log_error "Failed to clone Flutter SDK. Please check network connection and git installation."
        exit 1
    fi
    log_info "Flutter SDK cloned successfully to $FLUTTER_SDK_DIR."
fi

# If a specific version (tag) was requested, try to check it out.
if [ "$FLUTTER_VERSION" != "latest" ]; then
    log_info "Attempting to checkout Flutter version: $FLUTTER_VERSION..."
    cd "$FLUTTER_SDK_DIR"
    # Fetch tags first to ensure the version tag is available, especially if the repo was cloned shallowly or is old.
    log_info "Fetching all tags to ensure version $FLUTTER_VERSION is available..."
    if ! git fetch --all --tags; then
        log_warn "git fetch --all --tags failed. Version checkout might fail if $FLUTTER_VERSION is a new tag not present in the initial shallow clone."
    fi
    if ! git checkout "$FLUTTER_VERSION"; then
        log_error "Failed to checkout Flutter version $FLUTTER_VERSION. It might not exist on channel $FLUTTER_CHANNEL or was not fetched successfully."
        cd - > /dev/null # Go back to previous directory
        exit 1
    fi
    log_info "Successfully checked out Flutter version $FLUTTER_VERSION."
    cd - > /dev/null # Go back to previous directory
fi


# 3. Set Environment Variables for the current script execution
export FLUTTER_HOME="$FLUTTER_SDK_DIR"
export PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"
log_info "Flutter PATH set for this session: $PATH"
log_info "Dart SDK (bundled with Flutter) also added to PATH."


# 4. Configure Flutter: Disable Mobile Platforms (Android & iOS)
# For Jules Agent: This is critical to ensure no mobile SDK components are downloaded or expected.
log_info "Disabling mobile platforms (Android, iOS) for Flutter..."
FLUTTER_CONFIG_SUCCESS=true

if ! flutter config --no-enable-android; then
    log_warn "Could not disable Android platform. Android components might still be downloaded or checked."
    FLUTTER_CONFIG_SUCCESS=false
else
    log_info "Android platform disabled for Flutter."
fi

if ! flutter config --no-enable-ios; then
    log_warn "Could not disable iOS platform. iOS components might still be checked (less likely on Linux, but good for explicitness and future-proofing)."
    FLUTTER_CONFIG_SUCCESS=false
else
    log_info "iOS platform disabled for Flutter."
fi

if [ "$FLUTTER_CONFIG_SUCCESS" = true ]; then
    log_info "Mobile platforms successfully configured to be disabled."
fi

# 5. Configure Flutter: Enable Web and Linux Desktop
# For Jules Agent: These are the target platforms.
log_info "Enabling web and Linux desktop platforms explicitly..."
if ! flutter config --enable-web --enable-linux-desktop; then
    log_warn "Could not explicitly enable web and/or linux desktop platforms. Precache and doctor might show issues."
else
    log_info "Web and Linux desktop platforms enabled."
fi

# 6. Run Flutter Precache
# For Jules Agent: Downloads binaries for the enabled platforms (Web, Linux Desktop).
log_info "Running 'flutter precache' to download development binaries for enabled platforms..."
if ! flutter precache; then
    log_error "flutter precache command failed. There might be issues with the network or SDK download."
    # Attempt to run doctor anyway, it might provide more clues.
else
    log_info "flutter precache completed successfully."
fi

# 7. Run Flutter Doctor
# For Jules Agent: Verify that Web and Linux Desktop are set up. Android/iOS should be shown as unavailable/unconfigured.
log_info "Running 'flutter doctor -v' to check the setup."
log_info "For the Jules Agent VM, expect to see 'Linux desktop' and 'Chrome' (for web) as available and configured."
log_info "Android and iOS sections should indicate they are not enabled or not fully configured, which is intended."
if ! flutter doctor -v; then
    log_error "flutter doctor reported issues. Please review the output above. Check if Linux desktop and Web (Chrome) are correctly set up."
    # The script will still exit with 0 here, as the SDK is "set up" but may have issues.
    # The calling agent (Jules) should inspect the doctor output to decide on further actions.
else
    log_info "flutter doctor check completed. Please verify Linux desktop and Web (Chrome) readiness in the output above."
fi

# 8. Final Confirmation
log_info "Flutter SDK setup script for Jules Agent finished."
log_info "Flutter is installed at: $FLUTTER_HOME"
log_info "Target platforms: Web, Linux Desktop."
log_info "Mobile platforms (Android, iOS) have been explicitly disabled."
log_info "Make sure to use the updated PATH in subsequent commands in this session."
echo ""
echo "To use this flutter environment in subsequent bash operations within the same 'run_in_bash_session' call, the PATH is already set."
echo "If running in a new 'run_in_bash_session', you may need to re-export the PATH or re-source parts of this script."
echo "Example: export PATH=\"$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:\$PATH\""

exit 0
