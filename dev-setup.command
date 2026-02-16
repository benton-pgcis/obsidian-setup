#!/bin/bash
# Dev Setup - One-click Mac installer for Claude Code + MCP servers
# https://github.com/benton-pgcis/obsidian-setup
set -eo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Dev Setup"
UPDATE_URL="https://github.com/benton-pgcis/obsidian-setup/releases/latest/download/dev-setup.command"
MCP_DIR="$HOME/.local/share/pgcis-mcp"
MCP_REPO="benton-pgcis/pgcis-mcp-servers"
CONFIG_REPO="benton-pgcis/pgcis-claude-config"
OAUTH_1P_ITEM="PGCIS - GCP OAuth Credentials"
OAUTH_CREDS_DIR="$HOME/.config/google-calendar-mcp"
OAUTH_CREDS_FILE="$OAUTH_CREDS_DIR/gcp-oauth.keys.json"
TOTAL_STEPS=9

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
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║         ${SCRIPT_NAME} v${SCRIPT_VERSION}         ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════╝${RESET}"
  echo ""
}

print_step() {
  local num="$1" msg="$2"
  echo ""
  echo -e "${BOLD}${CYAN}[ ${num}/${TOTAL_STEPS} ] ${msg}${RESET}"
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
  echo "Usage: dev-setup.command [OPTIONS]"
  echo ""
  echo "One-click dev environment installer for Claude Code + MCP servers."
  echo ""
  echo "Options:"
  echo "  --help       Show this help message"
  echo "  --version    Show version number"
  echo ""
  echo "What this script does:"
  echo "  1. Installs Homebrew, GitHub CLI, Node.js, Claude Code, 1Password CLI"
  echo "  2. Authenticates with GitHub (browser-based)"
  echo "  3. Authenticates Claude Code"
  echo "  4. Clones and installs MCP servers (Gmail, Calendar, Google Docs)"
  echo "  5. Configures Claude Code with MCP server entries"
  echo "  6. Installs team skills and CLAUDE.md"
  echo ""
  echo "Safe to re-run - updates existing installs without data loss."
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

# ── Step 2: GitHub CLI + Auth ─────────────────────────────────────────────────

step_2_github() {
  print_step 2 "GitHub CLI + Authentication"

  # Install GitHub CLI
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

  # Authenticate
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
  gh auth setup-git
  print_ok "Git credential helper configured"
}

# ── Step 3: Core Tools ────────────────────────────────────────────────────────

step_3_core_tools() {
  print_step 3 "Core Tools"

  # Node.js (required for Calendar MCP via npx)
  if command_exists node; then
    local node_ver
    node_ver=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [[ "$node_ver" -ge 18 ]]; then
      print_skip "Node.js installed (v$(node --version 2>/dev/null | sed 's/v//'))"
    else
      print_warn "Node.js $(node --version) is too old (need >= 18), upgrading..."
      brew install node
      print_ok "Node.js upgraded"
    fi
  else
    print_info "Installing Node.js..."
    brew install node
    if command_exists node; then
      print_ok "Node.js installed"
    else
      print_fail "Node.js installation failed"
      show_error_dialog "Node.js installation failed. MCP servers require Node >= 18."
      return 1
    fi
  fi

  # Claude Code
  if command_exists claude; then
    print_skip "Claude Code installed"
  else
    print_info "Installing Claude Code..."
    brew install --cask claude-code
    if command_exists claude; then
      print_ok "Claude Code installed"
    else
      # Try npm fallback
      print_warn "Homebrew cask failed, trying npm..."
      npm install -g @anthropic-ai/claude-code 2>/dev/null || true
      if command_exists claude; then
        print_ok "Claude Code installed (via npm)"
      else
        print_fail "Claude Code installation failed"
        show_error_dialog "Claude Code installation failed. Install manually: brew install --cask claude-code"
        return 1
      fi
    fi
  fi

  # 1Password CLI
  if command_exists op; then
    print_skip "1Password CLI installed"
  else
    print_info "Installing 1Password CLI..."
    brew install --cask 1password-cli
    if command_exists op; then
      print_ok "1Password CLI installed"
    else
      print_warn "1Password CLI installation failed - OAuth credentials must be placed manually"
    fi
  fi
}

# ── Step 4: Optional Tools Picker ─────────────────────────────────────────────

step_4_optional_tools() {
  print_step 4 "Optional Tools"

  local tools_list='"Supabase CLI", "OrbStack (Docker)", "Chezmoi (dotfiles)"'

  local selection
  selection=$(osascript -e "choose from list {${tools_list}} with title \"$SCRIPT_NAME\" with prompt \"Select optional tools to install:\" & return & \"(Hold ⌘ to select multiple, or Cancel to skip)\" with multiple selections allowed" 2>/dev/null) || true

  if [[ "$selection" == "false" || -z "$selection" ]]; then
    print_info "No optional tools selected"
    return 0
  fi

  if [[ "$selection" == *"Supabase"* ]]; then
    if command_exists supabase; then
      print_skip "Supabase CLI installed"
    else
      print_info "Installing Supabase CLI..."
      brew install supabase/tap/supabase && print_ok "Supabase CLI installed" || print_warn "Supabase CLI failed"
    fi
  fi

  if [[ "$selection" == *"OrbStack"* ]]; then
    if [[ -d "/Applications/OrbStack.app" ]]; then
      print_skip "OrbStack installed"
    else
      print_info "Installing OrbStack..."
      brew install --cask orbstack && print_ok "OrbStack installed" || print_warn "OrbStack failed"
    fi
  fi

  if [[ "$selection" == *"Chezmoi"* ]]; then
    if command_exists chezmoi; then
      print_skip "Chezmoi installed"
    else
      print_info "Installing Chezmoi..."
      brew install chezmoi && print_ok "Chezmoi installed" || print_warn "Chezmoi failed"
    fi
  fi
}

# ── Step 5: Claude Code Auth ──────────────────────────────────────────────────

step_5_claude_auth() {
  print_step 5 "Claude Code Authentication"

  # Check if Claude Code is already authenticated
  # Claude stores auth in ~/.claude/ - check for config indicators
  if claude --version &>/dev/null && [[ -d "$HOME/.claude" ]]; then
    # Try a quick auth check - claude config outputs error if not authed
    if claude config list &>/dev/null 2>&1; then
      print_skip "Claude Code authenticated"
    else
      print_info "Authenticating Claude Code..."
      print_info "A browser window will open. Sign in with your Anthropic account."
      echo ""
      claude login || print_warn "Claude Code auth failed - run 'claude login' manually"
    fi
  else
    print_info "Authenticating Claude Code..."
    print_info "A browser window will open. Sign in with your Anthropic account."
    echo ""
    claude login || print_warn "Claude Code auth failed - run 'claude login' manually"
  fi

  # 1Password CLI integration reminder
  if command_exists op; then
    osascript -e "
      display dialog \"1Password CLI Integration\" & return & return & \"For credential access in Claude Code:\" & return & return & \"1. Open 1Password app\" & return & \"2. Go to Settings > Developer\" & return & \"3. Enable 'Integrate with 1Password CLI'\" & return & return & \"This lets Claude Code access secrets securely via 'op' commands.\" buttons {\"Got it\"} default button \"Got it\" with icon note with title \"$SCRIPT_NAME\"
    " &>/dev/null || true
    print_ok "1Password CLI integration reminder shown"
  fi
}

# ── Step 6: MCP Server Setup ─────────────────────────────────────────────────

step_6_mcp_servers() {
  print_step 6 "MCP Servers"

  # ── 6a: Clone or update MCP server code ──

  mkdir -p "$MCP_DIR"

  if [[ -d "$MCP_DIR/servers/.git" ]]; then
    # Existing install: pull updates
    print_info "Updating MCP server code..."
    if git -C "$MCP_DIR/servers" pull origin main &>/dev/null; then
      print_ok "MCP server code updated"
    else
      print_warn "MCP server pull failed - using existing code"
    fi
  else
    # Fresh install: clone
    print_info "Cloning MCP server code..."
    if gh repo clone "$MCP_REPO" "$MCP_DIR/servers" 2>/dev/null; then
      print_ok "MCP server code cloned"
    else
      print_fail "Failed to clone MCP servers"
      print_info "Ensure you have access to $MCP_REPO"
      show_error_dialog "Cannot access MCP server repository. Contact benton@pgcis.com for access."
      return 1
    fi
  fi

  # ── Create/update Python venv ──

  if [[ ! -d "$MCP_DIR/servers/.venv" ]]; then
    print_info "Creating Python virtual environment..."
    if /usr/bin/python3 -m venv "$MCP_DIR/servers/.venv"; then
      print_ok "Python venv created"
    else
      # Fallback: try without pip and bootstrap
      print_warn "Retrying venv creation..."
      /usr/bin/python3 -m venv --without-pip "$MCP_DIR/servers/.venv"
      curl -sfL https://bootstrap.pypa.io/get-pip.py | "$MCP_DIR/servers/.venv/bin/python" 2>/dev/null
      print_ok "Python venv created (bootstrapped pip)"
    fi
  else
    print_skip "Python venv exists"
  fi

  # Install/update MCP server packages
  local pip="$MCP_DIR/servers/.venv/bin/pip"
  print_info "Installing MCP server packages..."
  "$pip" install -q -e "$MCP_DIR/servers/gmail-mcp" 2>/dev/null && \
    print_ok "Gmail MCP installed" || print_fail "Gmail MCP install failed"
  "$pip" install -q -e "$MCP_DIR/servers/gdocs-mcp" 2>/dev/null && \
    print_ok "Google Docs MCP installed" || print_fail "Google Docs MCP install failed"
  print_info "Calendar MCP uses npx (no install needed)"

  # ── 6b: OAuth Credentials ──

  if [[ -f "$OAUTH_CREDS_FILE" ]]; then
    print_skip "OAuth credentials present"
  else
    mkdir -p "$OAUTH_CREDS_DIR"
    local creds_placed=false

    # Try 1Password first
    if command_exists op; then
      print_info "Fetching OAuth credentials from 1Password..."
      if op document get "$OAUTH_1P_ITEM" --out-file "$OAUTH_CREDS_FILE" 2>/dev/null; then
        print_ok "OAuth credentials restored from 1Password"
        creds_placed=true
      else
        print_warn "1Password fetch failed (check vault access or item name)"
      fi
    fi

    if ! $creds_placed; then
      # Show instructions for manual placement
      osascript -e "
        display dialog \"OAuth Credentials Needed\" & return & return & \"MCP servers need Google OAuth credentials to connect.\" & return & return & \"Contact benton@pgcis.com for the credentials file, then place it at:\" & return & \"$OAUTH_CREDS_FILE\" & return & return & \"After placing the file, re-run this installer.\" buttons {\"OK\"} default button \"OK\" with icon caution with title \"$SCRIPT_NAME\"
      " &>/dev/null || true
      print_warn "OAuth credentials not found - MCP auth will be skipped"
      print_info "Place credentials at: $OAUTH_CREDS_FILE"
      print_info "Then re-run this installer to complete MCP setup"
    fi
  fi

  # Copy OAuth credentials to Gmail and GDocs config dirs too
  if [[ -f "$OAUTH_CREDS_FILE" ]]; then
    local gmail_creds_dir="$HOME/.config/gmail-mcp"
    local gdocs_creds_dir="$HOME/.config/gdocs-mcp"
    mkdir -p "$gmail_creds_dir" "$gdocs_creds_dir"
    cp -n "$OAUTH_CREDS_FILE" "$gmail_creds_dir/gcp-oauth.keys.json" 2>/dev/null || true
    cp -n "$OAUTH_CREDS_FILE" "$gdocs_creds_dir/gcp-oauth.keys.json" 2>/dev/null || true
  fi

  # ── 6c: Token Generation (browser-based OAuth) ──

  if [[ ! -f "$OAUTH_CREDS_FILE" ]]; then
    print_warn "Skipping token generation (no OAuth credentials)"
    return 0
  fi

  # Check if tokens already exist
  local cal_token="$OAUTH_CREDS_DIR/token.json"
  local gmail_tokens="$HOME/.config/gmail-mcp/tokens"
  local gdocs_tokens="$HOME/.config/gdocs-mcp/tokens"
  local needs_auth=false

  if [[ ! -f "$cal_token" ]]; then needs_auth=true; fi
  if [[ ! -d "$gmail_tokens" ]] || [[ -z "$(ls -A "$gmail_tokens" 2>/dev/null)" ]]; then needs_auth=true; fi
  if [[ ! -d "$gdocs_tokens" ]] || [[ -z "$(ls -A "$gdocs_tokens" 2>/dev/null)" ]]; then needs_auth=true; fi

  if $needs_auth; then
    osascript -e "
      display dialog \"Google Account Sign-In\" & return & return & \"You'll sign in with your Google account up to 3 times.\" & return & \"Browsers will open automatically.\" & return & return & \"Sign in with your @pgcis.com account when prompted.\" buttons {\"Ready\"} default button \"Ready\" with icon note with title \"$SCRIPT_NAME\"
    " &>/dev/null || true

    # Calendar MCP auth
    if [[ ! -f "$cal_token" ]]; then
      print_info "Authenticating Calendar MCP..."
      if npx @cocal/google-calendar-mcp auth 2>/dev/null; then
        print_ok "Calendar MCP authenticated"
      else
        print_warn "Calendar MCP auth failed - run: npx @cocal/google-calendar-mcp auth"
      fi
    else
      print_skip "Calendar MCP token exists"
    fi

    # Gmail MCP auth
    if [[ ! -d "$gmail_tokens" ]] || [[ -z "$(ls -A "$gmail_tokens" 2>/dev/null)" ]]; then
      print_info "Authenticating Gmail MCP..."
      if "$MCP_DIR/servers/.venv/bin/python" -m gmail_mcp.auth add pgcis 2>/dev/null; then
        print_ok "Gmail MCP authenticated"
      else
        print_warn "Gmail MCP auth failed - run: $MCP_DIR/servers/.venv/bin/python -m gmail_mcp.auth add pgcis"
      fi
    else
      print_skip "Gmail MCP token exists"
    fi

    # Google Docs MCP auth
    if [[ ! -d "$gdocs_tokens" ]] || [[ -z "$(ls -A "$gdocs_tokens" 2>/dev/null)" ]]; then
      print_info "Authenticating Google Docs MCP..."
      if "$MCP_DIR/servers/.venv/bin/python" -m gdocs_mcp.auth add pgcis 2>/dev/null; then
        print_ok "Google Docs MCP authenticated"
      else
        print_warn "Google Docs MCP auth failed - run: $MCP_DIR/servers/.venv/bin/python -m gdocs_mcp.auth add pgcis"
      fi
    else
      print_skip "Google Docs MCP token exists"
    fi
  else
    print_skip "All MCP tokens present"
  fi
}

# ── Step 7: Claude Config ─────────────────────────────────────────────────────

step_7_claude_config() {
  print_step 7 "Claude Code Configuration"

  local claude_json="$HOME/.claude.json"
  local venv_python="$MCP_DIR/servers/.venv/bin/python"

  # Back up existing config
  if [[ -f "$claude_json" ]]; then
    cp "$claude_json" "${claude_json}.bak.$(date +%Y%m%d%H%M%S)"
    print_info "Backed up existing ~/.claude.json"
  fi

  # Merge MCP server entries into claude.json
  /usr/bin/python3 -c "
import json, os, sys

config_file = sys.argv[1]
venv_python = sys.argv[2]
oauth_creds = sys.argv[3]

# Load existing or create new
try:
    with open(config_file) as f:
        config = json.load(f)
except (IOError, ValueError):
    config = {}

servers = config.setdefault('mcpServers', {})
added = []

# Google Calendar MCP (npx-based)
if 'google-calendar' not in servers:
    servers['google-calendar'] = {
        'type': 'stdio',
        'command': 'npx',
        'args': ['@cocal/google-calendar-mcp'],
        'env': {'GOOGLE_OAUTH_CREDENTIALS': oauth_creds}
    }
    added.append('google-calendar')

# Gmail MCP (Python venv)
if 'gmail' not in servers:
    servers['gmail'] = {
        'type': 'stdio',
        'command': venv_python,
        'args': ['-m', 'gmail_mcp.server']
    }
    added.append('gmail')

# Google Docs MCP (Python venv)
if 'gdocs' not in servers:
    servers['gdocs'] = {
        'type': 'stdio',
        'command': venv_python,
        'args': ['-m', 'gdocs_mcp.server']
    }
    added.append('gdocs')

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
    f.write('\n')

if added:
    print('ADDED:' + ','.join(added))
else:
    print('NONE')
" "$claude_json" "$venv_python" "$OAUTH_CREDS_FILE"

  local result
  result=$(/usr/bin/python3 -c "
import json
try:
    with open('$claude_json') as f:
        config = json.load(f)
    servers = list(config.get('mcpServers', {}).keys())
    print(','.join(servers))
except:
    print('ERROR')
")

  if [[ "$result" == "ERROR" ]]; then
    print_fail "Failed to update ~/.claude.json"
    show_error_dialog "Could not configure Claude Code. The config file may be malformed."
    return 1
  fi

  print_ok "MCP servers configured in ~/.claude.json"
  print_info "Active servers: $result"
}

# ── Step 8: Team Skills ───────────────────────────────────────────────────────

step_8_team_skills() {
  print_step 8 "Team Skills"

  local claude_dir="$HOME/.claude"
  local skills_dir="$claude_dir/skills"
  mkdir -p "$skills_dir"

  # Try to clone team config repo
  local tmp_config
  tmp_config=$(mktemp -d)

  if gh repo clone "$CONFIG_REPO" "$tmp_config" 2>/dev/null; then
    # Copy CLAUDE.md (only if user doesn't have one)
    if [[ -f "$tmp_config/CLAUDE.md" ]] && [[ ! -f "$claude_dir/CLAUDE.md" ]]; then
      cp "$tmp_config/CLAUDE.md" "$claude_dir/CLAUDE.md"
      print_ok "Team CLAUDE.md installed"
    else
      print_skip "CLAUDE.md already exists (preserved)"
    fi

    # Copy skills (only new ones)
    if [[ -d "$tmp_config/skills" ]]; then
      local new_count=0
      for skill_dir in "$tmp_config/skills"/*/; do
        local skill_name
        skill_name=$(basename "$skill_dir")
        if [[ ! -d "$skills_dir/$skill_name" ]]; then
          cp -r "$skill_dir" "$skills_dir/$skill_name"
          new_count=$((new_count + 1))
        fi
      done
      if [[ $new_count -gt 0 ]]; then
        print_ok "Installed $new_count new skill(s)"
      else
        print_skip "All team skills already installed"
      fi
    fi
  else
    print_info "Team config repo not accessible - skipping"
    print_info "Skills can be added later by re-running this installer"
  fi

  rm -rf "$tmp_config"
}

# ── Step 9: Completion ────────────────────────────────────────────────────────

step_9_completion() {
  print_step 9 "Complete"

  echo ""
  echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${GREEN}  Dev environment ready!${RESET}"
  echo -e "${BOLD}${GREEN}════════════════════════════════════════${RESET}"
  echo ""
  print_info "Key commands:"
  print_info "  claude            Start Claude Code"
  print_info "  claude /mcp       Verify MCP server connections"
  print_info "  claude login      Re-authenticate Claude Code"
  echo ""
  print_info "MCP servers installed:"
  print_info "  google-calendar   Google Calendar (read/write)"
  print_info "  gmail             Gmail (read/write)"
  print_info "  gdocs             Google Docs (read/write)"
  echo ""
  print_info "MCP server code: $MCP_DIR/servers/"
  print_info "Claude config:   ~/.claude.json"
  echo ""
  print_info "To update: re-run dev-setup.command"
  echo ""

  osascript -e "
    display dialog \"Dev environment is ready!\" & return & return & \"Start Claude Code by running:\" & return & \"  claude\" & return & return & \"Verify MCP servers:\" & return & \"  Type /mcp after starting Claude Code\" buttons {\"Done\"} default button \"Done\" with icon note with title \"$SCRIPT_NAME\"
  " &>/dev/null || true
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

  step_1_homebrew       || exit 1
  step_2_github         || exit 1
  step_3_core_tools     || exit 1
  step_4_optional_tools
  step_5_claude_auth
  step_6_mcp_servers
  step_7_claude_config  || exit 1
  step_8_team_skills
  step_9_completion
}

main "$@"
