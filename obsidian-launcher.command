#!/bin/bash
# Obsidian Launcher - One-click Mac installer for Obsidian vaults
# https://github.com/bentonp/crossvine
set -eo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

SCRIPT_VERSION="1.0.1"
SCRIPT_NAME="Obsidian Launcher"
UPDATE_URL="https://github.com/benton-pgcis/obsidian-setup/releases/latest/download/obsidian-launcher.command"
INSTALL_PATH="$HOME/obsidian-vaults"
OBSIDIAN_SUPPORT="$HOME/Library/Application Support/obsidian"
OBSIDIAN_JSON="$OBSIDIAN_SUPPORT/obsidian.json"
BRANCH="main"
AUTO_PULL_INTERVAL=30
AUTO_PUSH_INTERVAL=60
AUTO_SAVE_INTERVAL=5

# Vault Registry: "local_name|github_account|repo_name|display_name"
VAULTS=(
  "pgcis|benton-pgcis|pgcis|PGCIS Company Vault"
  "pgcis-finance|benton-pgcis|pgcis-finance|PGCIS Finance"
  "pgcis-hr|benton-pgcis|pgcis-hr|PGCIS HR"
  "pgcis-exec|benton-pgcis|pgcis-exec|PGCIS Executive"
  # "crossvine|bentonp|crossvine|Crossvine AI/IP"
  # "Salesvine-Vault|bentonperet|Salesvine-Vault1|SalesVine Operations"
  # "Bentons-Brain|bentonperet|Benton-s-Brain|Personal Vault"
)

# ── Utility Functions ──────────────────────────────────────────────────────────

# Colors (fall back to plain text if terminal doesn't support colors)
if [[ -t 1 ]] && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
  BOLD="\033[1m"
  CYAN="\033[36m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  RED="\033[31m"
  DIM="\033[2m"
  RESET="\033[0m"
else
  BOLD="" CYAN="" GREEN="" YELLOW="" RED="" DIM="" RESET=""
fi

print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}╔═════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║       ${SCRIPT_NAME} v${SCRIPT_VERSION}         ║${RESET}"
  echo -e "${BOLD}${CYAN}╚═════════════════════════════════════════╝${RESET}"
  echo ""
}

print_step() {
  local num="$1" msg="$2"
  echo ""
  echo -e "${BOLD}${CYAN}[ ${num}/9 ] ${msg}${RESET}"
}

print_ok() {
  echo -e "  ${GREEN}✓${RESET} $1"
}

print_skip() {
  echo -e "  ${YELLOW}-${RESET} $1 ${DIM}(already done)${RESET}"
}

print_fail() {
  echo -e "  ${RED}✗${RESET} $1"
}

print_warn() {
  echo -e "  ${YELLOW}!${RESET} $1"
}

print_info() {
  echo -e "  ${DIM}$1${RESET}"
}

command_exists() {
  command -v "$1" &>/dev/null
}

ensure_brew_in_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

show_error_dialog() {
  local msg="$1"
  osascript -e "display dialog \"$msg\" buttons {\"OK\"} default button \"OK\" with icon stop with title \"$SCRIPT_NAME\"" &>/dev/null || true
}

print_usage() {
  echo "Usage: obsidian-launcher.command [OPTIONS]"
  echo ""
  echo "One-click installer for Obsidian vaults from GitHub."
  echo ""
  echo "Options:"
  echo "  --help       Show this help message"
  echo "  --version    Show version number"
  echo ""
  echo "What this script does:"
  echo "  1. Installs Homebrew, Obsidian, and GitHub CLI"
  echo "  2. Authenticates with GitHub (browser-based)"
  echo "  3. Shows a vault picker (only repos you have access to)"
  echo "  4. Clones selected vaults to ~/obsidian-vaults/"
  echo "  5. Configures auto-sync and opens Obsidian"
  echo ""
  echo "Safe to re-run - repairs existing vaults without data loss."
  echo ""
  echo "Contact: benton@pgcis.com"
}

# ── Step 0: Preflight ─────────────────────────────────────────────────────────

step_0_preflight() {
  # Strip macOS quarantine attribute (prevents Gatekeeper warning on re-run)
  xattr -d com.apple.quarantine "$0" 2>/dev/null || true

  # Self-update check (skip if no URL configured)
  if [[ -n "$UPDATE_URL" ]]; then
    local remote_hash local_hash
    remote_hash=$(curl -sfL "$UPDATE_URL" | shasum -a 256 | cut -d' ' -f1) || true
    local_hash=$(shasum -a 256 "$0" | cut -d' ' -f1)
    if [[ -n "$remote_hash" && "$remote_hash" != "$local_hash" ]]; then
      local response
      response=$(osascript -e "display dialog \"A newer version of $SCRIPT_NAME is available. Update now?\" buttons {\"Skip\", \"Update\"} default button \"Update\" with title \"$SCRIPT_NAME\"" 2>/dev/null || echo "button returned:Skip")
      if [[ "$response" == *"Update"* ]]; then
        print_info "Downloading update..."
        curl -sfL "$UPDATE_URL" -o "$0"
        chmod +x "$0"
        exec "$0" "$@"
      fi
    fi
  fi
}

# ── Step 1: Homebrew ──────────────────────────────────────────────────────────

step_1_homebrew() {
  print_step 1 "Homebrew"

  ensure_brew_in_path

  if command_exists brew; then
    print_skip "Homebrew installed"
    return 0
  fi

  print_info "Installing Homebrew (you may need to enter your Mac password)..."
  print_info "This also installs Xcode Command Line Tools - may take a few minutes."
  echo ""

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  ensure_brew_in_path

  if command_exists brew; then
    print_ok "Homebrew installed"
  else
    print_fail "Homebrew installation failed"
    show_error_dialog "Homebrew installation failed. Please try again or contact benton@pgcis.com for help."
    return 1
  fi
}

# ── Step 2: Obsidian ──────────────────────────────────────────────────────────

step_2_obsidian() {
  print_step 2 "Obsidian"

  if [[ -d "/Applications/Obsidian.app" ]]; then
    print_skip "Obsidian installed"
    return 0
  fi

  print_info "Installing Obsidian..."
  brew install --cask obsidian

  if [[ -d "/Applications/Obsidian.app" ]]; then
    print_ok "Obsidian installed"
  else
    print_fail "Obsidian installation failed"
    show_error_dialog "Obsidian installation failed. Please try again or contact benton@pgcis.com for help."
    return 1
  fi
}

# ── Step 3: GitHub CLI + Node.js ─────────────────────────────────────────────

step_3_cli_tools() {
  print_step 3 "CLI Tools"

  # GitHub CLI
  if command_exists gh; then
    print_skip "GitHub CLI installed"
  else
    print_info "Installing GitHub CLI..."
    brew install gh
    if command_exists gh; then
      print_ok "GitHub CLI installed"
    else
      print_fail "GitHub CLI installation failed"
      show_error_dialog "GitHub CLI installation failed. Please try again or contact benton@pgcis.com for help."
      return 1
    fi
  fi

  # Node.js (required for Google Docs Publisher)
  if command_exists node; then
    print_skip "Node.js installed"
  else
    print_info "Installing Node.js..."
    brew install node
    if command_exists node; then
      print_ok "Node.js installed"
    else
      print_warn "Node.js installation failed - Google Docs Publisher will not work"
    fi
  fi
}

# ── Step 4: GitHub Authentication ─────────────────────────────────────────────

step_4_auth() {
  print_step 4 "GitHub Authentication"

  if gh auth status &>/dev/null; then
    local account
    account=$(gh auth status 2>&1 | grep -o "account .*" | head -1 | awk '{print $2}') || true
    print_skip "Authenticated${account:+ as $account}"
  else
    print_info "A browser window will open for GitHub login."
    print_info "Sign in with your GitHub account, then return here."
    echo ""

    if ! gh auth login --web --git-protocol https; then
      print_fail "GitHub authentication failed"
      print_info "You can retry by running: gh auth login"
      show_error_dialog "GitHub authentication failed. Re-run this installer to try again."
      return 1
    fi
    print_ok "Authenticated with GitHub"
  fi

  # Configure system git to use GitHub CLI credentials
  # Critical: without this, Obsidian Git plugin can't pull from private repos
  gh auth setup-git
  print_ok "Git credential helper configured"
}

# ── Step 5: Vault Picker ──────────────────────────────────────────────────────

# Global array populated by step_5, consumed by step_6+
SELECTED_VAULTS=()

step_5_vault_picker() {
  print_step 5 "Vault Access"

  local accessible_entries=()
  local accessible_display=()

  for vault_entry in "${VAULTS[@]}"; do
    IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"

    print_info "Checking $display_name..."

    if gh repo view "$gh_account/$repo_name" --json name &>/dev/null; then
      accessible_entries+=("$vault_entry")

      if [[ -d "$INSTALL_PATH/$local_name/.git" ]]; then
        accessible_display+=("${display_name} (installed)")
      else
        accessible_display+=("$display_name")
      fi
    fi
  done

  if [[ ${#accessible_entries[@]} -eq 0 ]]; then
    print_fail "You don't have access to any vaults"
    print_info "Contact your admin to get invited to the GitHub repositories."
    show_error_dialog "No accessible vaults found. Contact your admin to get GitHub repository access."
    return 1
  fi

  print_ok "Found ${#accessible_entries[@]} accessible vault(s)"

  # Build AppleScript list string: "item1", "item2", "item3"
  local as_list=""
  for d in "${accessible_display[@]}"; do
    if [[ -n "$as_list" ]]; then
      as_list+=", "
    fi
    as_list+="\"$d\""
  done

  # Show native macOS picker
  local selection
  selection=$(osascript -e "choose from list {${as_list}} with title \"$SCRIPT_NAME\" with prompt \"Select vaults to install or repair:\" & return & \"(Hold ⌘ to select multiple)\" with multiple selections allowed" 2>/dev/null) || true

  if [[ "$selection" == "false" || -z "$selection" ]]; then
    print_info "No vaults selected. Exiting."
    return 1
  fi

  # Parse comma-separated selection back to vault entries
  # osascript returns: "Item One, Item Two, Item Three"
  SELECTED_VAULTS=()
  while IFS=',' read -ra selected_names; do
    for sel in "${selected_names[@]}"; do
      # Trim whitespace and remove "(installed)" suffix
      sel=$(echo "$sel" | sed 's/^ *//;s/ *$//;s/ (installed)$//')

      for vault_entry in "${accessible_entries[@]}"; do
        IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"
        if [[ "$display_name" == "$sel" ]]; then
          SELECTED_VAULTS+=("$vault_entry")
          break
        fi
      done
    done
  done <<< "$selection"

  if [[ ${#SELECTED_VAULTS[@]} -eq 0 ]]; then
    print_warn "Could not match selection to vaults"
    return 1
  fi

  print_ok "Selected ${#SELECTED_VAULTS[@]} vault(s)"
}

# ── Step 6: Clone or Repair ───────────────────────────────────────────────────

# Plugin Registry: "plugin_id|github_owner|github_repo|display_name"
PLUGINS=(
  "obsidian-git|Vinzent03|obsidian-git|Git"
  "dataview|blacksmithgu|obsidian-dataview|Dataview"
  "obsidian-shellcommands|Taitava|obsidian-shellcommands|Shell Commands"
)

download_plugin() {
  local plugin_id="$1" gh_owner="$2" gh_repo="$3" display_name="$4" plugin_dir="$5"
  local release_base="https://github.com/$gh_owner/$gh_repo/releases/latest/download"

  mkdir -p "$plugin_dir"

  if [[ -s "$plugin_dir/main.js" ]]; then
    return 0  # Already installed
  fi

  print_info "  Downloading $display_name plugin..."
  curl -sfL "$release_base/main.js" -o "$plugin_dir/main.js" || true
  curl -sfL "$release_base/manifest.json" -o "$plugin_dir/manifest.json" || true
  curl -sfL "$release_base/styles.css" -o "$plugin_dir/styles.css" 2>/dev/null || true

  if [[ ! -s "$plugin_dir/main.js" ]]; then
    print_warn "  Could not download $display_name - install it manually from Obsidian"
    return 1
  fi
  print_ok "  $display_name plugin installed"
  return 0
}

install_plugins() {
  local vault_path="$1"
  local obsidian_dir="$vault_path/.obsidian"
  local community_file="$obsidian_dir/community-plugins.json"

  # Download each plugin
  local installed_ids=()
  for plugin_entry in "${PLUGINS[@]}"; do
    IFS='|' read -r plugin_id gh_owner gh_repo display_name <<< "$plugin_entry"
    local plugin_dir="$obsidian_dir/plugins/$plugin_id"
    if download_plugin "$plugin_id" "$gh_owner" "$gh_repo" "$display_name" "$plugin_dir"; then
      installed_ids+=("$plugin_id")
    fi
  done

  # Register all installed plugins in community-plugins.json
  /usr/bin/python3 -c "
import json, sys
cp_file = sys.argv[1]
plugin_ids = sys.argv[2:]
try:
    with open(cp_file) as f:
        plugins = json.load(f)
except (IOError, ValueError):
    plugins = []
for pid in plugin_ids:
    if pid not in plugins:
        plugins.append(pid)
with open(cp_file, 'w') as f:
    json.dump(plugins, f, indent=2)
    f.write('\n')
" "$community_file" "${installed_ids[@]}"

  # Configure Obsidian Git sync settings
  local git_data="$obsidian_dir/plugins/obsidian-git/data.json"
  if [[ -d "$obsidian_dir/plugins/obsidian-git" ]]; then
    /usr/bin/python3 -c "
import json, sys
data_file = sys.argv[1]
try:
    with open(data_file) as f:
        data = json.load(f)
except (IOError, ValueError):
    data = {}
data['disablePush'] = False
data['autoPullInterval'] = int(sys.argv[2])
data['autoPullOnBoot'] = True
data['autoPushInterval'] = int(sys.argv[3])
data['autoSaveInterval'] = int(sys.argv[4])
data['pullBeforePush'] = True
data['syncMethod'] = 'merge'
with open(data_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$git_data" "$AUTO_PULL_INTERVAL" "$AUTO_PUSH_INTERVAL" "$AUTO_SAVE_INTERVAL"
  fi
}

step_6_clone_repair() {
  print_step 6 "Installing Vaults"

  mkdir -p "$INSTALL_PATH"

  local failures=()
  local successes=()

  for vault_entry in "${SELECTED_VAULTS[@]}"; do
    IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"
    local vault_path="$INSTALL_PATH/$local_name"

    # Clean up incomplete clones (dir exists but no .git)
    if [[ -d "$vault_path" && ! -d "$vault_path/.git" ]]; then
      print_warn "Removing incomplete clone: $local_name"
      rm -rf "$vault_path"
    fi

    if [[ -d "$vault_path/.git" ]]; then
      # Repair mode
      print_info "Repairing $display_name..."
      if (cd "$vault_path" && git fetch origin && git reset --hard "origin/$BRANCH") &>/dev/null; then
        install_plugins "$vault_path"
        print_ok "$display_name (repaired)"
        successes+=("$vault_entry")
      else
        print_fail "Failed to repair $display_name"
        failures+=("$display_name")
      fi
    else
      # Fresh clone
      print_info "Cloning $display_name..."
      local clone_cmd="gh repo clone $gh_account/$repo_name $vault_path -- --branch $BRANCH"

      if eval "$clone_cmd" 2>/dev/null; then
        install_plugins "$vault_path"
        print_ok "$display_name (installed)"
        successes+=("$vault_entry")
      else
        print_fail "Failed to clone $display_name"
        failures+=("$display_name")
      fi
    fi
  done

  if [[ ${#failures[@]} -gt 0 ]]; then
    print_warn "Failed: ${failures[*]}"
  fi

  if [[ ${#successes[@]} -eq 0 ]]; then
    print_fail "No vaults were installed successfully"
    show_error_dialog "All vault installations failed. Check your internet connection and try again."
    return 1
  fi

  # Update SELECTED_VAULTS to only include successes for steps 7-8
  SELECTED_VAULTS=("${successes[@]}")
}

# ── Step 7: Vault Tools (npm, Shell Commands, hotkeys) ───────────────────────

setup_vault_tools() {
  local vault_path="$1" local_name="$2"
  local publisher_dir="$vault_path/_Tools/Google Docs Publisher"

  # Skip if vault doesn't have the publisher
  if [[ ! -f "$publisher_dir/package.json" ]]; then
    return 0
  fi

  # npm install (node_modules is gitignored, must install per clone)
  if [[ ! -d "$publisher_dir/node_modules" ]] && command_exists node; then
    print_info "  Installing Google Docs Publisher dependencies..."
    (cd "$publisher_dir" && npm install --silent 2>/dev/null) && \
      print_ok "  Google Docs Publisher dependencies installed" || \
      print_warn "  npm install failed - run manually: cd \"$publisher_dir\" && npm install"
  fi

  # TODO: client_secret.json distribution
  # Currently this file must be committed to the repo or manually placed.
  # Long-term plan: download from a secure location (e.g., private GitHub Release
  # asset, S3 presigned URL, or 1Password CLI). The OAuth client_secret.json
  # identifies the GCP project and is not a user secret, but should still be
  # distributed securely rather than committed to the vault repo.

  # Configure Shell Commands plugin with Publish to Google Docs command
  local sc_data="$vault_path/.obsidian/plugins/obsidian-shellcommands/data.json"
  if [[ -d "$vault_path/.obsidian/plugins/obsidian-shellcommands" ]]; then
    /usr/bin/python3 -c "
import json, sys

data_file = sys.argv[1]
vault_path = sys.argv[2]

try:
    with open(data_file) as f:
        data = json.load(f)
except (IOError, ValueError):
    data = {}

# Ensure required top-level keys
data.setdefault('settings_version', '0.23.0')
data.setdefault('debug', False)
data.setdefault('enable_events', True)
data.setdefault('show_autocomplete_menu', True)
data.setdefault('preview_variables_in_command_palette', True)
data.setdefault('approve_modals_by_pressing_enter_key', True)

cmds = data.setdefault('shell_commands', [])

# Check if publish command already exists
cmd_id = 'gdocs-publish'
exists = any(c.get('id') == cmd_id for c in cmds)
if not exists:
    cmds.append({
        'id': cmd_id,
        'platform_specific_commands': {
            'darwin': '\"{{vault_path}}/_Tools/Google Docs Publisher/publish-active.sh\" \"{{file_path:absolute}}\"',
            'windows': '\"{{vault_path}}\\\\_Tools\\\\Google Docs Publisher\\\\publish-file.bat\" \"{{file_path:absolute}}\"'
        },
        'shells': {},
        'alias': 'Publish to Google Docs',
        'icon': None,
        'confirm_execution': False,
        'ignore_error_codes': [],
        'input_contents': {'stdin': None},
        'output_handlers': {
            'stdout': {'handler': 'modal', 'convert_ansi_code': True},
            'stderr': {'handler': 'notification', 'convert_ansi_code': True}
        },
        'output_wrappers': {'stdout': None, 'stderr': None},
        'output_channel_order': 'stdout-first',
        'output_handling_mode': 'buffered',
        'execution_notification_mode': 'permanent',
        'events': {},
        'debounce': None,
        'command_palette_availability': 'enabled',
        'preactions': [],
        'variable_default_values': {}
    })

data.setdefault('prompts', [])
data.setdefault('builtin_variables', {})
data.setdefault('custom_variables', [])
data.setdefault('custom_shells', [])
data.setdefault('output_wrappers', [])

with open(data_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$sc_data" "$vault_path"
    print_ok "  Shell Commands configured (Publish to Google Docs)"
  fi

  # Configure hotkey: Alt+Shift+P for Publish to Google Docs
  local hotkeys_file="$vault_path/.obsidian/hotkeys.json"
  /usr/bin/python3 -c "
import json, sys

hotkeys_file = sys.argv[1]
try:
    with open(hotkeys_file) as f:
        data = json.load(f)
except (IOError, ValueError):
    data = {}

key = 'obsidian-shellcommands:shell-command-gdocs-publish'
if key not in data:
    data[key] = [{'modifiers': ['Alt', 'Shift'], 'key': 'P'}]

with open(hotkeys_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$hotkeys_file"
  print_ok "  Hotkey configured (Alt+Shift+P = Publish to Google Docs)"
}

step_7_vault_tools() {
  print_step 7 "Vault Tools"

  for vault_entry in "${SELECTED_VAULTS[@]}"; do
    IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"
    local vault_path="$INSTALL_PATH/$local_name"
    setup_vault_tools "$vault_path" "$local_name"
  done
}

# ── Step 8: Register Vaults in Obsidian ───────────────────────────────────────

step_8_register() {
  print_step 8 "Registering Vaults"

  # Check if Obsidian is running
  if pgrep -x "Obsidian" &>/dev/null; then
    print_warn "Obsidian is currently running"
    osascript -e "display dialog \"Please quit Obsidian before continuing.\" & return & return & \"The installer needs to register your vaults.\" buttons {\"Cancel\", \"OK, I closed it\"} default button 2 with icon caution with title \"$SCRIPT_NAME\"" &>/dev/null || true

    # Wait up to 10 seconds for Obsidian to close
    local wait_count=0
    while pgrep -x "Obsidian" &>/dev/null && [[ $wait_count -lt 10 ]]; do
      sleep 1
      wait_count=$((wait_count + 1))
    done

    if pgrep -x "Obsidian" &>/dev/null; then
      print_warn "Obsidian is still running - vault registration may not take effect until restart"
    fi
  fi

  # Ensure Obsidian support directory exists
  mkdir -p "$OBSIDIAN_SUPPORT"

  # Collect vault paths to register
  local vault_paths=()
  for vault_entry in "${SELECTED_VAULTS[@]}"; do
    IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"
    local vault_path="$INSTALL_PATH/$local_name"
    if [[ -d "$vault_path/.obsidian" ]] || [[ -d "$vault_path" ]]; then
      vault_paths+=("$vault_path")
    fi
  done

  if [[ ${#vault_paths[@]} -eq 0 ]]; then
    print_warn "No vaults to register"
    return 0
  fi

  # Use python3 for safe JSON manipulation
  /usr/bin/python3 -c "
import json, os, sys, time, hashlib

obsidian_json = sys.argv[1]
vault_paths = sys.argv[2:]

# Load existing or create new
try:
    with open(obsidian_json) as f:
        data = json.load(f)
except (IOError, ValueError):
    data = {}

if 'vaults' not in data:
    data['vaults'] = {}

# Index existing vaults by path
existing_paths = {}
for vid, vdata in data['vaults'].items():
    p = vdata.get('path', '')
    existing_paths[p] = vid

for vp in vault_paths:
    abs_path = os.path.abspath(vp)

    if abs_path in existing_paths:
        # Already registered - update timestamp
        vault_id = existing_paths[abs_path]
        data['vaults'][vault_id]['ts'] = int(time.time() * 1000)
        data['vaults'][vault_id]['open'] = True
    else:
        # Generate deterministic 16-char hex ID from path
        vault_id = hashlib.md5(abs_path.encode()).hexdigest()[:16]
        while vault_id in data['vaults']:
            vault_id = os.urandom(8).hex()[:16]

        data['vaults'][vault_id] = {
            'path': abs_path,
            'ts': int(time.time() * 1000),
            'open': True
        }

with open(obsidian_json, 'w') as f:
    json.dump(data, f)
" "$OBSIDIAN_JSON" "${vault_paths[@]}"

  print_ok "Registered ${#vault_paths[@]} vault(s) in Obsidian"
}

# ── Step 9: Open Obsidian ─────────────────────────────────────────────────────

step_9_open() {
  print_step 9 "Opening Obsidian"

  local count=${#SELECTED_VAULTS[@]}

  # Open each vault via obsidian:// URI
  for vault_entry in "${SELECTED_VAULTS[@]}"; do
    IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"
    local vault_path="$INSTALL_PATH/$local_name"

    if [[ -d "$vault_path" ]]; then
      local encoded_path
      encoded_path=$(/usr/bin/python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$vault_path")
      open "obsidian://open?path=$encoded_path"
      print_ok "Opened $display_name"
      sleep 3  # Give Obsidian time to process each vault
    fi
  done

  # Instructional pop-up 1: Turn on community plugins
  osascript -e "
    display dialog \"Step 1 of 2: Enable Community Plugins\" & return & return & \"In Obsidian, you should see a 'Restricted mode' notice at the top.\" & return & return & \"→ Click 'Turn on community plugins'\" & return & \"→ Click 'Turn on community plugins' again to confirm\" & return & return & \"Do this for each vault that was installed.\" & return & \"(The Git sync plugin has been pre-installed by this installer.)\" & return & return & \"Click Continue when done.\" buttons {\"Continue\"} default button \"Continue\" with icon note with title \"$SCRIPT_NAME\"
  " &>/dev/null || true

  # Instructional pop-up 2: Restart Obsidian to activate sync
  osascript -e "
    display dialog \"Step 2 of 3: Restart Obsidian\" & return & return & \"Now restart Obsidian so the sync plugin activates:\" & return & return & \"→ Quit Obsidian completely (⌘Q)\" & return & \"→ Reopen Obsidian from your Applications folder or Dock\" & return & return & \"After restart, your vaults will automatically:\" & return & \"  • Pull changes from GitHub every ${AUTO_PULL_INTERVAL} minutes\" & return & \"  • Push your changes every ${AUTO_PUSH_INTERVAL} minutes\" & return & \"  • Auto-save your edits every ${AUTO_SAVE_INTERVAL} minutes\" buttons {\"Continue\"} default button \"Continue\" with icon note with title \"$SCRIPT_NAME\"
  " &>/dev/null || true

  # Instructional pop-up 3: Google Docs Publisher auth (only if publisher exists in any vault)
  local has_publisher=false
  for vault_entry in "${SELECTED_VAULTS[@]}"; do
    IFS='|' read -r local_name gh_account repo_name display_name <<< "$vault_entry"
    if [[ -f "$INSTALL_PATH/$local_name/_Tools/Google Docs Publisher/index.js" ]]; then
      has_publisher=true
      break
    fi
  done

  if $has_publisher; then
    osascript -e "
      display dialog \"Step 3 of 3: Google Docs Publisher\" & return & return & \"A 'Publish to Google Docs' command has been installed.\" & return & \"Hotkey: Alt + Shift + P\" & return & return & \"The first time you use it, you'll need to sign into Google:\" & return & \"  1. Open any note and press Alt+Shift+P\" & return & \"  2. A browser window will open for Google sign-in\" & return & \"  3. Grant permission, then copy the code shown\" & return & \"  4. Paste the code back into the Terminal window\" & return & return & \"After that, publishing works with one keypress.\" buttons {\"Done!\"} default button \"Done!\" with icon note with title \"$SCRIPT_NAME\"
    " &>/dev/null || true
  fi

  echo ""
  echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${GREEN}  Setup complete!${RESET}"
  echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
  echo ""
  print_info "Installed $count vault(s) to $INSTALL_PATH/"
  print_info "Sync: pull every ${AUTO_PULL_INTERVAL}min, push every ${AUTO_PUSH_INTERVAL}min, auto-save every ${AUTO_SAVE_INTERVAL}min"
  if $has_publisher; then
    print_info "Publish to Google Docs: Alt+Shift+P (first use requires Google sign-in)"
  fi
  echo ""
  print_info "To re-run this installer (repair or add vaults):"
  print_info "  Double-click obsidian-launcher.command"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  # Parse flags before header (--version should be clean output)
  case "${1:-}" in
    --help)    print_header; print_usage; exit 0 ;;
    --version) echo "$SCRIPT_NAME v$SCRIPT_VERSION"; exit 0 ;;
  esac

  print_header

  step_0_preflight "$@"

  step_1_homebrew     || exit 1
  step_2_obsidian     || exit 1
  step_3_cli_tools    || exit 1
  step_4_auth         || exit 1
  step_5_vault_picker || exit 0
  step_6_clone_repair
  step_7_vault_tools
  step_8_register
  step_9_open
}

main "$@"
