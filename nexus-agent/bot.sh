#!/bin/bash
#
# Gemini CLI Telegram Bot — process manager
# Usage: ./bot.sh {start|stop|restart|status|logs}
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/.bot.pid"
LOG_FILE="$SCRIPT_DIR/bot.log"

start() {
  if is_running; then
    echo "⚠️  Bot is already running (PID $(cat "$PID_FILE"))"
    return 1
  fi

  echo "🚀 Starting Gemini CLI Telegram Bot..."
  cd "$SCRIPT_DIR"
  nohup node src/bot.js >> "$LOG_FILE" 2>&1 &
  local pid=$!
  echo $pid > "$PID_FILE"
  sleep 1

  if kill -0 $pid 2>/dev/null; then
    echo "✅ Bot started (PID $pid)"
    echo "📋 Logs: tail -f $LOG_FILE"
  else
    echo "❌ Bot failed to start. Check logs: cat $LOG_FILE"
    rm -f "$PID_FILE"
    return 1
  fi
}

stop() {
  if ! is_running; then
    echo "⚠️  Bot is not running"
    # Clean up any orphans anyway
    pkill -f "node src/bot.js" 2>/dev/null
    rm -f "$PID_FILE"
    return 0
  fi

  local pid=$(cat "$PID_FILE")
  echo "🛑 Stopping bot (PID $pid)..."

  # Send SIGTERM for graceful shutdown
  kill "$pid" 2>/dev/null
  
  # Wait up to 5 seconds for graceful shutdown
  local count=0
  while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
    sleep 0.5
    count=$((count + 1))
  done

  # Force kill if still running
  if kill -0 "$pid" 2>/dev/null; then
    echo "⚠️  Force killing..."
    kill -9 "$pid" 2>/dev/null
  fi

  # Also kill any orphan node processes running bot.js
  pkill -f "node src/bot.js" 2>/dev/null

  rm -f "$PID_FILE"
  echo "✅ Bot stopped"
}

restart() {
  echo "🔄 Restarting bot..."
  stop
  sleep 1
  start
}

status() {
  if is_running; then
    local pid=$(cat "$PID_FILE")
    echo "✅ Bot is running (PID $pid)"
    echo "📋 Last 5 log lines:"
    tail -5 "$LOG_FILE" 2>/dev/null
  else
    echo "❌ Bot is not running"
    # Check for orphan processes
    local orphans=$(pgrep -f "node src/bot.js" 2>/dev/null)
    if [ -n "$orphans" ]; then
      echo "⚠️  Found orphan processes: $orphans"
      echo "   Run './bot.sh stop' to clean them up"
    fi
  fi
}

logs() {
  if [ ! -f "$LOG_FILE" ]; then
    echo "No log file found."
    return 1
  fi
  echo "📋 Following bot logs (Ctrl+C to exit)..."
  tail -f "$LOG_FILE"
}

is_running() {
  [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null
}

# ─── Main ─────────────────────────────────────────────────────────────────────

case "${1:-}" in
  start)   start ;;
  stop)    stop ;;
  restart) restart ;;
  status)  status ;;
  logs)    logs ;;
  *)
    echo "Usage: ./bot.sh {start|stop|restart|status|logs}"
    echo ""
    echo "  start    Start the bot in the background"
    echo "  stop     Stop the bot gracefully"
    echo "  restart  Stop and start the bot"
    echo "  status   Check if the bot is running"
    echo "  logs     Tail the bot log file"
    ;;
esac
