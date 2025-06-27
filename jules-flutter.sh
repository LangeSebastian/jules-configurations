#!/bin/bash
#
# Script to set up the Flutter SDK environment for Jules (AI Agent)
# This script is intended to be run in a Linux-based sandbox environment.
# It will download the Flutter SDK if not already present, set PATH,
# and run flutter doctor.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration ---
FLUTTER_SDK_DIR="$HOME/flutter_sdk"
FLUTTER_CHANNEL="stable" # Specify channel: stable, beta, master
FLUTTER_VERSION="latest" # Specify version, e.g., "3.19.0" or "latest" for channel
FLUTTER_SDK_URL_BASE="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux"
# Example URL: https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.19.0-stable.tar.xz

# --- Helper Functions ---
log_info() {
    echo "INFO: $1"
}

log_error() {
    echo "ERROR: $1" >&2
}

# --- Prerequisite Checks ---
# We'll assume basic tools like git, curl, tar, xz are available in Jules's environment.
# If not, these would need to be installed by the environment's provisioning.
log_info "Ensuring prerequisites for web and Linux desktop development are installed..."
# For web (Chrome/Chromium) and Linux (GTK, Clang, CMake, Ninja, pkg-config, mesa-utils)
# Note: This script assumes it can run apt-get. If not, these dependencies must be pre-installed.
if command -v apt-get >/dev/null; then
    # Check if running as root, if not, prepend sudo if available
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null; then
        SUDO_CMD="sudo"
    elif [ "$(id -u)" -ne 0 ]; then
        log_error "Not root and sudo not found. Cannot install dependencies. Please ensure they are pre-installed."
        # Allow to continue, flutter doctor will report missing deps.
    fi

    log_info "Updating package lists..."
    $SUDO_CMD apt-get update -y

    log_info "Installing dependencies: curl, git, tar, xz-utils, unzip, libglu1-mesa, libgtk-3-dev, pkg-config, clang, cmake, ninja-build, chromium-browser (or google-chrome-stable if preferred and repo added)"
    # Using chromium-browser as it's generally available in default repos.
    # mesa-utils for eglinfo
    if ! $SUDO_CMD apt-get install -y curl git tar xz-utils unzip libglu1-mesa libgtk-3-dev pkg-config clang cmake ninja-build chromium-browser mesa-utils; then
        log_error "Failed to install some or all system dependencies. Flutter Doctor may report issues."
    else
        log_info "System dependencies installation attempt complete."
    fi
    # Set CHROME_EXECUTABLE if chromium-browser was installed
    if command -v chromium-browser >/dev/null; then
        export CHROME_EXECUTABLE="chromium-browser"
        log_info "CHROME_EXECUTABLE set to chromium-browser"
    elif command -v google-chrome >/dev/null; then
        export CHROME_EXECUTABLE="google-chrome"
        log_info "CHROME_EXECUTABLE set to google-chrome"
    else
        log_warn "Neither chromium-browser nor google-chrome found after attempting install. Web support may fail."
    fi
else
    log_warn "apt-get not found. Assuming dependencies (curl, git, tar, xz-utils, unzip, libglu1-mesa, libgtk-3-dev, pkg-config, clang, cmake, ninja-build, chromium-browser/google-chrome, mesa-utils) are already installed."
fi


# --- Main Setup Logic ---

# 1. Determine Flutter SDK Download URL
# This logic is simplified; a more robust version would query for the exact latest version if "latest" is specified.
# For now, we'll construct a common URL pattern.
# A more robust way would be to use `git clone --depth 1 --branch $FLUTTER_CHANNEL https://github.com/flutter/flutter.git $FLUTTER_SDK_DIR`
# but cloning can be slower than downloading a tarball for a specific version.
# We will prefer git clone for simplicity and to easily switch channels/versions if needed by the agent later.

if [ "$FLUTTER_VERSION" == "latest" ]; then
    # For "latest" on a channel, git clone is the most straightforward.
    log_info "Using git to clone the latest from Flutter channel: $FLUTTER_CHANNEL."
else
    # This part is tricky as direct tarball URLs for specific versions change.
    # The SDK archive page is the best source: https://docs.flutter.dev/development/tools/sdk/archive?tab=linux
    # For a script, `git clone` and then `git checkout <version_tag>` is more reliable.
    log_info "Specific version requested: $FLUTTER_VERSION. Will use git clone and checkout."
fi

# 2. Install or Update Flutter SDK
if [ -d "$FLUTTER_SDK_DIR/bin/flutter" ]; then
    log_info "Flutter SDK already found at $FLUTTER_SDK_DIR."
    # Optionally, add logic here to check if it's the correct channel/version and update if necessary.
    # For now, we assume if it exists, it's usable or will be managed by subsequent flutter commands.
    # cd "$FLUTTER_SDK_DIR"
    # log_info "Attempting to update Flutter SDK..."
    # git pull
    # flutter upgrade # if needed
    # cd - > /dev/null
else
    log_info "Flutter SDK not found. Cloning from GitHub..."
    if ! git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"; then
        log_error "Failed to clone Flutter SDK. Please check network connection and git installation."
        exit 1
    fi
    log_info "Flutter SDK cloned successfully to $FLUTTER_SDK_DIR."
fi

# If a specific version (tag) was requested, try to check it out.
if [ "$FLUTTER_VERSION" != "latest" ]; then
    log_info "Checking out Flutter version: $FLUTTER_VERSION..."
    cd "$FLUTTER_SDK_DIR"
    if ! git checkout "$FLUTTER_VERSION"; then
        log_error "Failed to checkout Flutter version $FLUTTER_VERSION. It might not exist on channel $FLUTTER_CHANNEL."
        # Attempt to fetch tags and retry, in case the local repo doesn't have it yet
        git fetch --all --tags
        if ! git checkout "$FLUTTER_VERSION"; then
             log_error "Still failed to checkout Flutter version $FLUTTER_VERSION after fetching tags."
             cd - > /dev/null
             exit 1
        fi
    fi
    log_info "Successfully checked out Flutter version $FLUTTER_VERSION."
    cd - > /dev/null
fi


# 3. Set Environment Variables for the current script execution
export FLUTTER_HOME="$FLUTTER_SDK_DIR"
export PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"

log_info "Flutter PATH set for this session: $PATH"

# Check if FLUTTER_GIT_URL is set by the user.
if [ -z "$FLUTTER_GIT_URL" ]; then
    log_info "FLUTTER_GIT_URL is not set."
    log_info "If you encounter an error from 'flutter doctor' like 'Upstream repository ... is not a standard remote',"
    log_info "consider setting FLUTTER_GIT_URL to your specific repository URL before running this script."
    log_info "Example: export FLUTTER_GIT_URL=\"https://your_username:your_token@github.com/your_fork/flutter.git\""
else
    log_info "FLUTTER_GIT_URL is already set to: $FLUTTER_GIT_URL"
    # Export it again just to be absolutely sure it's available for subsequent commands in this script session,
    # in case it was only set in the parent environment and not exported.
    export FLUTTER_GIT_URL
fi

# 4. Configure Flutter to disable Android
log_info "Disabling Android for Flutter to avoid downloading Android SDK/tools..."
if ! flutter config --no-enable-android; then
    log_warn "Could not disable Android platform. Continuing, but Android components might still be downloaded or checked."
else
    log_info "Android platform disabled for Flutter."
fi

# 5. Run Flutter Precache
log_info "Running 'flutter precache' to download development binaries (Android should be skipped)..."
# We will specify platforms to be absolutely sure, if possible.
# However, `flutter precache` doesn't have direct flags to include/exclude specific platforms like android.
# `flutter config --no-enable-android` is the primary way.
# Let's also enable web and linux explicitly to guide precache.
log_info "Enabling web and linux platforms explicitly..."
if ! flutter config --enable-web --enable-linux-desktop; then
    log_warn "Could not explicitly enable web/linux platforms. Precache might not be optimal."
else
    log_info "Web and Linux desktop platforms enabled."
fi

if ! flutter precache; then
    log_error "flutter precache command failed. There might be issues with the network or SDK download."
    # Attempt to run doctor anyway, it might provide more clues.
else
    log_info "flutter precache completed successfully."
fi

# 6. Run Flutter Doctor
log_info "Running 'flutter doctor -v' to check setup..."
if ! flutter doctor -v; then
    log_error "flutter doctor reported issues. Please review the output above."
    # The script will still exit with 0 here, as the SDK is "set up" but may have issues.
    # The calling agent should inspect the doctor output.
else
    log_info "flutter doctor check completed."
fi

# 7. Final Confirmation
log_info "Flutter SDK setup script finished."
log_info "Flutter is installed at: $FLUTTER_HOME"
log_info "Make sure to use the updated PATH in subsequent commands in this session."
echo ""
echo "To use this flutter environment in subsequent bash operations within the same 'run_in_bash_session' call, the PATH is already set."
echo "If running in a new 'run_in_bash_session', you may need to re-export the PATH or re-source parts of this script."
echo "Example: export PATH=\"$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:\$PATH\""

exit 0
