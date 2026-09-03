# Shared Homebrew environment for this plugin.
# Sourced by brew-status, brew-upgrade, and the post-boot hook.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$PLUGIN_DIR/scripts"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
STATE_FILE="$STATE_DIR/brew-update.json"
LOCK_FILE="$STATE_DIR/brew-update.lock"

# Never prompt. Prefix ownership is the privilege boundary; sudo is denied.
export HOMEBREW_NO_ANALYTICS="${HOMEBREW_NO_ANALYTICS:-1}"
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_EMOJI=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ASK=1
export HOMEBREW_NO_INSTALL_FROM_API="${HOMEBREW_NO_INSTALL_FROM_API:-}"
export NONINTERACTIVE=1
export CI=1
export SUDO_ASKPASS="$SCRIPTS_DIR/deny-sudo-askpass"
export SUDO_NONINTERACTIVE=1

if [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
  BREW=/home/linuxbrew/.linuxbrew/bin/brew
  export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:${PATH:-/usr/bin}"
elif command -v brew >/dev/null 2>&1; then
  BREW="$(command -v brew)"
else
  BREW=""
fi

mkdir -p "$STATE_DIR"

now_unix() {
  date +%s
}

empty_state() {
  jq -nc --argjson checkedAt "$(now_unix)" '{
    ok: true,
    checkedAt: $checkedAt,
    checking: false,
    updating: false,
    error: "",
    brewPrefix: "",
    formulae: [],
    casks: [],
    installed: []
  }'
}

read_state() {
  if [[ -f $STATE_FILE ]]; then
    cat "$STATE_FILE"
  else
    empty_state
  fi
}

write_state_file() {
  local json=$1
  local tmp
  tmp="$(mktemp "$STATE_DIR/brew-update.XXXXXX")"
  printf '%s\n' "$json" >"$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

merge_state() {
  local patch=$1
  write_state_file "$(jq -c --argjson patch "$patch" '. * $patch' <<<"$(read_state)")"
}

brew_prefix() {
  if [[ -n $BREW ]]; then
    "$BREW" --prefix 2>/dev/null || true
  fi
}

brew_ready() {
  [[ -n $BREW && -x $BREW ]]
}

brew_writable() {
  local prefix
  prefix="$(brew_prefix)"
  [[ -n $prefix && -w $prefix ]]
}

fail_state() {
  local message=$1
  merge_state "$(jq -nc --arg error "$message" --argjson checkedAt "$(now_unix)" '{
    ok: false,
    checkedAt: $checkedAt,
    checking: false,
    updating: false,
    error: $error
  }')"
  cat "$STATE_FILE"
}

parse_outdated() {
  local raw=$1
  local include_casks=${2:-1}
  local prefix
  prefix="$(brew_prefix)"
  jq -c \
    --argjson checkedAt "$(now_unix)" \
    --arg prefix "$prefix" \
    --argjson includeCasks "$include_casks" '
      {
        ok: true,
        checkedAt: $checkedAt,
        checking: false,
        updating: false,
        error: "",
        brewPrefix: $prefix,
        formulae: ((.formulae // []) | map({
          name: .name,
          installed: ((.installed_versions // []) | join(", ")),
          current: (.current_version // ""),
          pinned: (.pinned == true)
        })),
        casks: (if $includeCasks == 1 then ((.casks // []) | map({
          name: .name,
          installed: ((.installed_versions // []) | join(", ")),
          current: (.current_version // ""),
          pinned: false
        })) else [] end)
      }
    ' <<<"$raw"
}

package_count() {
  jq -r '((.formulae // []) + (.casks // [])) | length' <<<"$(read_state)"
}

# Non-blocking lock for the bar poll. Returns 1 if another brew job owns it.
try_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9
}

# Blocking lock for upgrades. Waits up to 10 minutes.
wait_lock() {
  exec 9>"$LOCK_FILE"
  flock -w 600 9
}
