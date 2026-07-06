# Shared receipt-cached dependency installers for Claude Code Web sessions.
# Sourced (not executed) by bin/claude-code-web-setup (the Edit/Write
# PreToolUse hook) and bin/test (JIT setup for the bare `bundle exec rake`
# bash-run path, which Bash-only tool calls don't otherwise trigger a hook
# for). Both callers set CLAUDE_CODE_REMOTE-gating themselves before sourcing.

RECEIPTS_DIR="tmp/claude-web-receipts"
mkdir -p "$RECEIPTS_DIR"

install_gems() {
  local lock_hash receipt
  lock_hash=$(sha256sum Gemfile.lock 2>/dev/null | cut -c1-8 || echo "no-lock")
  receipt="$RECEIPTS_DIR/gems-$lock_hash"

  [ -f "$receipt" ] && return 0

  bundle install
  touch "$receipt"
}
