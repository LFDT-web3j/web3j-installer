#!/bin/sh

# URL to the checksum file
CHECKSUM_URL="https://raw.githubusercontent.com/LFDT-web3j/web3j-installer/603023bc4f9f6784f67f94b404ea1fa6e2634585/checksum-linux.txt"

# Every request, including redirects, must remain HTTPS and fail on HTTP errors.
fetch_https() {
    curl --disable --proto '=https' --proto-redir '=https' \
        --fail --show-error --silent --location "$@"
}

fetch_checksum() {
    fetch_https "$CHECKSUM_URL"
}

# Legacy piped invocations first download a complete file, then verify that file.
# Never hash a second download while executing a different stream.
if [ ! -f "$0" ]; then
    installer_file=$(mktemp) || exit 1
    if ! fetch_https https://get.web3j.io --output "$installer_file"; then
        rm -f "$installer_file"
        exit 1
    fi
    sh "$installer_file"
    installer_status=$?
    rm -f "$installer_file"
    exit "$installer_status"
fi

# Function to calculate the checksum of the script file
calculate_file_checksum() {
  if [ "$(uname)" = "Darwin" ]; then
    sed '/^CHECKSUM_URL=/d' "$0" | shasum -a 256 | awk '{print $1}'
  else
    sed '/^CHECKSUM_URL=/d' "$0" | sha256sum | awk '{print $1}'
  fi
}

# Verify the bytes of the file that is actually being executed.
verify_checksum() {
  if ! FETCHED_CHECKSUM=$(fetch_checksum); then
    echo "Could not download the installer checksum." >&2
    exit 1
  fi
  if ! printf '%s\n' "$FETCHED_CHECKSUM" | LC_ALL=C grep -Eq '^[[:xdigit:]]{64}$'; then
    echo "Invalid installer checksum." >&2
    exit 1
  fi
  CURRENT_CHECKSUM=$(calculate_file_checksum)
  if [ "$CURRENT_CHECKSUM" != "$FETCHED_CHECKSUM" ]; then
    echo "Script verification failed!" >&2
    exit 1
  fi
  echo "Checksum verification passed!"
}

# Run checksum verification
verify_checksum

if ! release_metadata=$(fetch_https "https://api.github.com/repos/LFDT-web3j/web3j-cli/releases/latest"); then
  echo "Could not download release metadata." >&2
  exit 1
fi
if ! tag_name=$(printf '%s' "$release_metadata" | jq -er '.tag_name'); then
  echo "Invalid release metadata." >&2
  exit 1
fi
if ! printf '%s\n' "$tag_name" | LC_ALL=C grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'; then
  echo "Invalid release tag." >&2
  exit 1
fi
web3j_version=${tag_name#v}
installed_flag=0
installed_version=""

check_if_installed() {
  if [ -x "$(command -v web3j)" ] >/dev/null 2>&1; then
    printf 'An Web3j installation exists on your system.\n'
    installed_flag=1
  fi
}

setup_color() {
  # Only use colors if connected to a terminal
  if [ -t 1 ]; then
    RED=$(printf '\033[31m')
    GREEN=$(printf '\033[32m')
    YELLOW=$(printf '\033[33m')
    BLUE=$(printf '\033[34m')
    BOLD=$(printf '\033[1m')
    RESET=$(printf '\033[m')
  else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
  fi
}

install_web3j() {
  echo "Downloading Web3j ..."
  mkdir -p "$HOME/.web3j" || return 1
  archive=$(mktemp "$HOME/.web3j/download.XXXXXX") || return 1
  archive_url="https://github.com/LFDT-web3j/web3j-cli/releases/download/v${web3j_version}/web3j-shadow-${web3j_version}.tar"
  if ! fetch_https "$archive_url" --output "$archive"; then
    rm -f "$archive"
    echo "Could not download Web3j; the existing installation was preserved." >&2
    return 1
  fi
  echo "Installing Web3j..."
  if ! tar -xf "$archive" -C "$HOME/.web3j"; then
    rm -f "$archive"
    echo "Could not extract Web3j." >&2
    return 1
  fi
  rm -f "$archive"
  if [ "$installed_flag" -eq 1 ]; then
    clean_up
  fi
  echo "export PATH=\$PATH:$HOME/.web3j" >"$HOME/.web3j/source.sh"
  chmod +x "$HOME/.web3j/source.sh"
}
get_user_input() {
  while echo "Would you like to update Web3j [Y/n]" && read -r user_input </dev/tty ; do
    case $user_input in
    n)
      echo "Aborting installation ..."
      exit 0
      ;;
    *)
       echo "Updating Web3j ..."
       break
       ;;
    esac
  done
}

check_version() {
  installed_version=$(web3j --version | grep Version | awk -F" " '{print $NF}')
  if [ "$installed_version" = "$web3j_version" ]; then
      echo "You have the latest version of Web3j (${installed_version}). Exiting."
      exit 0
    else
      echo "Your Web3j version is not up to date."
      get_user_input
  fi
}

source_web3j() {
  SOURCE_Web3j="\n[ -s \"$HOME/.web3j/source.sh\" ] && source \"$HOME/.web3j/source.sh\""
  if [ -f "$HOME/.bashrc" ]; then
    bash_rc="$HOME/.bashrc"
    touch "${bash_rc}"
    if ! grep -qc '.web3j/source.sh' "${bash_rc}"; then
      echo "Adding source string to ${bash_rc}"
      printf "${SOURCE_Web3j}\n" >>"${bash_rc}"
    else
      echo "Skipped update of ${bash_rc} (source string already present)"
    fi
  fi
  if [ -f "$HOME/.bash_profile" ]; then
    bash_profile="${HOME}/.bash_profile"
    touch "${bash_profile}"
    if ! grep -qc '.web3j/source.sh' "${bash_profile}"; then
      echo "Adding source string to ${bash_profile}"
      printf "${SOURCE_Web3j}\n" >>"${bash_profile}"
    else
      echo "Skipped update of ${bash_profile} (source string already present)"
    fi
  fi
  if [ -f "$HOME/.bash_login" ]; then
    bash_login="$HOME/.bash_login"
    touch "${bash_login}"
    if ! grep -qc '.web3j/source.sh' "${bash_login}"; then
      echo "Adding source string to ${bash_login}"
      printf "${SOURCE_Web3j}\n" >>"${bash_login}"
    else
      echo "Skipped update of ${bash_login} (source string already present)"
    fi
  fi
  if [ -f "$HOME/.profile" ]; then
    profile="$HOME/.profile"
    touch "${profile}"
    if ! grep -qc '.web3j/source.sh' "${profile}"; then
      echo "Adding source string to ${profile}"
      printf "$SOURCE_Web3j\n" >>"${profile}"
    else
      echo "Skipped update of ${profile} (source string already present)"
    fi
  fi

  if [ -f "$(command -v zsh 2>/dev/null)" ]; then
    file="$HOME/.zshrc"
    touch "${file}"
    if ! grep -qc '.web3j/source.sh' "${file}"; then
      echo "Adding source string to ${file}"
      printf "$SOURCE_Web3j\n" >>"${file}"
    else
      echo "Skipped update of ${file} (source string already present)"
    fi
  fi
}

check_if_web3j_homebrew() {
  if (command -v brew && ! (brew info web3j 2>&1 | grep -e "Not installed\|No available formula") >/dev/null 2>&1); then
    echo "Looks like Web3j is installed with Homebrew. Please use Homebrew to update. Exiting."
    exit 0
  fi
}

clean_up() {
  if [ -d "$HOME/.web3j" ]; then
    rm -f "$HOME/.web3j/source.sh"
    rm -rf "$HOME/.web3j/web3j-shadow-$installed_version" >/dev/null 2>&1
    echo "Deleting older installation ..."
  fi
}

completed() {
  cd "$HOME/.web3j"
  ln -sf "web3j-shadow-$web3j_version/bin/web3j" web3j
  printf '\n'
  printf "$GREEN"
  echo "Web3j was successfully installed."
  echo "To use web3j in your current shell run:"
  echo "source \$HOME/.web3j/source.sh"
  echo "When you open a new shell this will be performed automatically."
  echo "To see what Web3j's CLI can do you can check the documentation bellow."
  echo "https://docs.web3j.io/latest/command_line_tools/"
  printf "$RESET"
  exit 0
}

check_java_version() {
  java_version=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
  echo "Your current java version is ${java_version}"
  # Split the Java version string into parts based on the '.' delimiter
  major_version=$(echo "$java_version" | cut -d'.' -f1)
  if [ "$major_version" -ge 21 ]; then
    echo "Your Java version is compatible with Web3j CLI."
  else
    echo "The Web3j CLI requires a Java version equals with 21 or higher. Please ensure you have a compatible Java version before installing Web3j for full functionality."
    printf 'Press Enter to continue, or Ctrl+C to cancel the installation: '
    read -r java_confirmation </dev/tty || exit 1
  fi
}

main() {
  setup_color
  check_java_version
  check_if_installed
  if [ $installed_flag -eq 1 ]; then
    check_if_web3j_homebrew
    check_version
    install_web3j || exit 1
    source_web3j
    completed
  else
    install_web3j || exit 1
    source_web3j
    completed
  fi
}

main
