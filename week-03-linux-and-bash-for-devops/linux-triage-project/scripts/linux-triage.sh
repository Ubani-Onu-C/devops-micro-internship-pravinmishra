#!/usr/bin/env bash
#
# linux-triage.sh — read-only Linux/Nginx health triage
#
# Author of engagement : Ubani Onu Chukwu
# Project              : DMI Cohort 3, Week 3 — Linux/Nginx Health Triage
#
# This script is STRICTLY READ-ONLY. It only inspects and reports. It never
# restarts services, modifies files, or deletes anything. Any recovery action
# is left to a human operator.
#
# Exit codes: 0 = HEALTHY, 1 = WARN, 2 = FAIL (worst check wins).

set -o pipefail
# Intentionally NOT using `set -e`: a failing read-only probe is a FAIL result
# to report, not a reason to abort the whole triage run.

# ---------------------------------------------------------------------------
# Variables and thresholds
# ---------------------------------------------------------------------------
OPERATOR_NAME="Ubani Onu Chukwu"

HTTP_URL="http://127.0.0.1/"
HTTP_SLOW_SECONDS="1.0"          # WARN if a 2xx/3xx response is slower than this

WEB_PORT="80"                    # port Nginx should be listening on
SSH_PORT="22"                    # WARN if this disappears (lockout risk)

DISK_MOUNT="/"
DISK_WARN_PCT=80                 # >= WARN
DISK_FAIL_PCT=90                 # >= FAIL (applies to space and inodes)

MEM_WARN_PCT=15                  # available memory < this % => WARN
MEM_FAIL_PCT=10                  # available memory < this % => FAIL

# Exit-code / severity levels.
LEVEL_HEALTHY=0
LEVEL_WARN=1
LEVEL_FAIL=2

# Ordered list of checks. Each entry is "function_label:function_name".
CHECKS=(
  "Nginx service state:check_nginx_service"
  "Nginx config validity:check_nginx_config"
  "HTTP endpoint response:check_http_endpoint"
  "Listening ports:check_listening_ports"
  "Disk & memory capacity:check_disk_memory"
)

# ---------------------------------------------------------------------------
# Global state accumulated as checks run
# ---------------------------------------------------------------------------
OVERALL_LEVEL=$LEVEL_HEALTHY     # tracks the worst level seen
declare -a RESULT_LINES=()       # one formatted summary line per check

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# level_word LEVEL -> HEALTHY|WARN|FAIL
level_word() {
  case "$1" in
    "$LEVEL_HEALTHY") echo "HEALTHY" ;;
    "$LEVEL_WARN")    echo "WARN"    ;;
    *)                echo "FAIL"    ;;
  esac
}

# record LABEL LEVEL DETAIL
# Prints the per-check result and folds the level into OVERALL_LEVEL.
record() {
  local label="$1" level="$2" detail="$3"
  local word
  word="$(level_word "$level")"

  printf '  [%-7s] %s\n' "$word" "$label"
  [ -n "$detail" ] && printf '            %s\n' "$detail"

  RESULT_LINES+=("$(printf '[%-7s] %s' "$word" "$label")")
  [ "$level" -gt "$OVERALL_LEVEL" ] && OVERALL_LEVEL="$level"
}

# have CMD -> true if command exists
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Check 1 — Nginx service state (read-only)
# ---------------------------------------------------------------------------
check_nginx_service() {
  local label="Nginx service state"
  local state restarts changed=""

  state="$(systemctl is-active nginx 2>/dev/null)"
  restarts="$(systemctl show -p NRestarts --value nginx 2>/dev/null)"
  # Detect the "unit file changed on disk, run daemon-reload" advisory.
  if systemctl status nginx --no-pager 2>&1 | grep -qi "changed on disk"; then
    changed="unit file changed on disk (daemon-reload advised)"
  fi
  [ -z "$restarts" ] && restarts=0

  if [ "$state" != "active" ]; then
    record "$label" "$LEVEL_FAIL" "systemctl reports state='$state' (expected 'active')"
  elif [ "$restarts" -gt 0 ] || [ -n "$changed" ]; then
    local d="active; NRestarts=$restarts"
    [ -n "$changed" ] && d="$d; $changed"
    record "$label" "$LEVEL_WARN" "$d"
  else
    record "$label" "$LEVEL_HEALTHY" "active; NRestarts=0"
  fi
}

# ---------------------------------------------------------------------------
# Check 2 — Nginx config validity (read-only: `nginx -t` does not reload)
# ---------------------------------------------------------------------------
check_nginx_config() {
  local label="Nginx config validity"
  local out rc

  # `nginx -t` only tests config; it never applies or reloads it.
  if sudo -n true 2>/dev/null; then
    out="$(sudo -n nginx -t 2>&1)"; rc=$?
  else
    out="$(nginx -t 2>&1)"; rc=$?
  fi

  if [ "$rc" -ne 0 ]; then
    record "$label" "$LEVEL_FAIL" "$(echo "$out" | tail -n 1)"
  elif echo "$out" | grep -qi "warn"; then
    record "$label" "$LEVEL_WARN" "$(echo "$out" | grep -i warn | head -n 1)"
  else
    record "$label" "$LEVEL_HEALTHY" "syntax ok; test successful"
  fi
}

# ---------------------------------------------------------------------------
# Check 3 — HTTP endpoint response (read-only GET)
# ---------------------------------------------------------------------------
check_http_endpoint() {
  local label="HTTP endpoint response"
  local resp code time

  if ! have curl; then
    record "$label" "$LEVEL_WARN" "curl not available; cannot probe $HTTP_URL"
    return
  fi

  # -s silent, no body written anywhere; purely a read.
  resp="$(curl -s -o /dev/null -w '%{http_code} %{time_total}' \
              --max-time 5 "$HTTP_URL" 2>/dev/null)"
  code="${resp%% *}"
  time="${resp##* }"
  [ -z "$code" ] && code="000"
  [ -z "$time" ] && time="0"

  # awk used only for a float comparison; it changes nothing.
  local slow
  slow="$(awk -v t="$time" -v lim="$HTTP_SLOW_SECONDS" \
              'BEGIN{print (t+0 >= lim+0) ? "1" : "0"}')"

  case "$code" in
    2??|3??)
      if [ "$slow" = "1" ]; then
        record "$label" "$LEVEL_WARN" "HTTP $code from $HTTP_URL but slow (${time}s)"
      else
        record "$label" "$LEVEL_HEALTHY" "HTTP $code from $HTTP_URL in ${time}s"
      fi
      ;;
    4??)
      record "$label" "$LEVEL_WARN" "HTTP $code from $HTTP_URL (client error)"
      ;;
    000)
      record "$label" "$LEVEL_FAIL" "no response from $HTTP_URL (connection refused/timeout)"
      ;;
    *)
      record "$label" "$LEVEL_FAIL" "HTTP $code from $HTTP_URL (server error)"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Check 4 — Listening ports (read-only socket inspection)
# ---------------------------------------------------------------------------
check_listening_ports() {
  local label="Listening ports"
  local listing web_ok ssh_ok

  if have ss; then
    listing="$(ss -tlnH 2>/dev/null)"
  elif have netstat; then
    listing="$(netstat -tln 2>/dev/null)"
  else
    record "$label" "$LEVEL_WARN" "neither ss nor netstat available"
    return
  fi

  # Match ":PORT" as the local end of a LISTEN socket.
  echo "$listing" | grep -Eq "[:.]${WEB_PORT}[[:space:]]" && web_ok=1 || web_ok=0
  echo "$listing" | grep -Eq "[:.]${SSH_PORT}[[:space:]]" && ssh_ok=1 || ssh_ok=0

  if [ "$web_ok" -ne 1 ]; then
    record "$label" "$LEVEL_FAIL" "web port :$WEB_PORT is NOT listening"
  elif [ "$ssh_ok" -ne 1 ]; then
    record "$label" "$LEVEL_WARN" "web port :$WEB_PORT ok, but ssh :$SSH_PORT not listening (lockout risk)"
  else
    record "$label" "$LEVEL_HEALTHY" "ports :$WEB_PORT and :$SSH_PORT listening"
  fi
}

# ---------------------------------------------------------------------------
# Check 5 — Disk & memory capacity (read-only)
# ---------------------------------------------------------------------------
check_disk_memory() {
  local label="Disk & memory capacity"
  local disk_pct inode_pct mem_total mem_avail mem_pct
  local level=$LEVEL_HEALTHY
  local -a notes=()

  # Disk space and inode usage for the target mount.
  disk_pct="$(df -hP "$DISK_MOUNT" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
  inode_pct="$(df -iP "$DISK_MOUNT" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
  [ -z "$disk_pct" ]  && disk_pct=0
  [ -z "$inode_pct" ] && inode_pct=0

  # Memory: use the "available" column, the honest headroom figure.
  mem_total="$(free -m 2>/dev/null | awk '/^Mem:/{print $2}')"
  mem_avail="$(free -m 2>/dev/null | awk '/^Mem:/{print $7}')"
  [ -z "$mem_total" ] && mem_total=0
  [ -z "$mem_avail" ] && mem_avail=0
  if [ "$mem_total" -gt 0 ]; then
    mem_pct=$(( mem_avail * 100 / mem_total ))
  else
    mem_pct=0
  fi

  # Disk space thresholds.
  if [ "$disk_pct" -ge "$DISK_FAIL_PCT" ]; then
    level=$LEVEL_FAIL;  notes+=("disk ${disk_pct}% used on ${DISK_MOUNT} (>=${DISK_FAIL_PCT}%)")
  elif [ "$disk_pct" -ge "$DISK_WARN_PCT" ]; then
    [ "$level" -lt "$LEVEL_WARN" ] && level=$LEVEL_WARN
    notes+=("disk ${disk_pct}% used on ${DISK_MOUNT} (>=${DISK_WARN_PCT}%)")
  fi

  # Inode thresholds (reuse the same limits).
  if [ "$inode_pct" -ge "$DISK_FAIL_PCT" ]; then
    level=$LEVEL_FAIL;  notes+=("inodes ${inode_pct}% used (>=${DISK_FAIL_PCT}%)")
  elif [ "$inode_pct" -ge "$DISK_WARN_PCT" ]; then
    [ "$level" -lt "$LEVEL_WARN" ] && level=$LEVEL_WARN
    notes+=("inodes ${inode_pct}% used (>=${DISK_WARN_PCT}%)")
  fi

  # Memory thresholds (lower available % is worse).
  if [ "$mem_pct" -lt "$MEM_FAIL_PCT" ]; then
    level=$LEVEL_FAIL;  notes+=("mem ${mem_pct}% available (<${MEM_FAIL_PCT}%)")
  elif [ "$mem_pct" -lt "$MEM_WARN_PCT" ]; then
    [ "$level" -lt "$LEVEL_WARN" ] && level=$LEVEL_WARN
    notes+=("mem ${mem_pct}% available (<${MEM_WARN_PCT}%)")
  fi

  if [ "$level" -eq "$LEVEL_HEALTHY" ]; then
    record "$label" "$LEVEL_HEALTHY" \
      "disk ${disk_pct}% used, inodes ${inode_pct}% used, mem ${mem_pct}% available"
  else
    local IFS='; '
    record "$label" "$level" "${notes[*]}"
  fi
}

# ---------------------------------------------------------------------------
# Header / summary
# ---------------------------------------------------------------------------
print_header() {
  echo "==========================================================="
  echo " Linux / Nginx Health Triage  (READ-ONLY)"
  echo " Operator : $OPERATOR_NAME"
  echo " Host     : $(hostname 2>/dev/null)"
  echo " Date     : $(date 2>/dev/null)"
  echo " Project  : DMI Cohort 3, Week 3"
  echo "==========================================================="
  echo
  echo "Running ${#CHECKS[@]} read-only health checks:"
  echo
}

print_summary() {
  local word
  word="$(level_word "$OVERALL_LEVEL")"
  echo
  echo "-----------------------------------------------------------"
  echo " Summary"
  echo "-----------------------------------------------------------"
  local line
  for line in "${RESULT_LINES[@]}"; do
    echo "  $line"
  done
  echo
  echo " OVERALL STATUS: $word   (exit code $OVERALL_LEVEL)"
  echo "-----------------------------------------------------------"
  echo " NOTE: This tool only observes. Any recovery command must be"
  echo "       reviewed and executed manually by the human operator."
  echo "==========================================================="
}

# ---------------------------------------------------------------------------
# Main — iterate the checks array and dispatch each function
# ---------------------------------------------------------------------------
main() {
  print_header

  local entry label fn
  for entry in "${CHECKS[@]}"; do
    label="${entry%%:*}"
    fn="${entry##*:}"
    if declare -F "$fn" >/dev/null; then
      "$fn"
    else
      record "$label" "$LEVEL_WARN" "check function '$fn' not implemented"
    fi
  done

  print_summary
  exit "$OVERALL_LEVEL"
}

main "$@"
