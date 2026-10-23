# Helpers for app/tool/desktop-check.sh: run the real release build on a
# virtual X11 screen (Xvfb), drive it with xdotool, and take screenshots.
# Source it; don't run it.
#
# Everything lives in app/build/desktop-check/ (git-ignored), except the
# memory-only folder, which must be on tmpfs: /dev/shm/pj-check-run.
# pj_stop_all closes the app and Xvfb; desktop-check.sh calls it on exit.

PJ_APP=${PJ_APP:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
PJ_BUNDLE=${PJ_BUNDLE:-$PJ_APP/build/linux/x64/release/bundle}
PJ_WORK=${PJ_WORK:-$PJ_APP/build/desktop-check}
PJ_HOME=$PJ_WORK/home
PJ_RUNTIME=/dev/shm/pj-check-run
PJ_SHOTS=$PJ_WORK/shots
PJ_DISPLAY=:77
export DISPLAY=$PJ_DISPLAY

pj_reset() {
  pj_stop_all
  rm -rf "$PJ_WORK" "$PJ_RUNTIME"
  mkdir -p "$PJ_HOME" "$PJ_WORK/fb" "$PJ_SHOTS"
  mkdir -m 700 "$PJ_RUNTIME"
}

# Xvfb with no TCP and no abstract socket: only a Unix socket in /tmp/.X11-unix.
pj_start_x() {
  Xvfb "$PJ_DISPLAY" -screen 0 1280x900x24 -fbdir "$PJ_WORK/fb" -nolisten tcp -nolisten local \
    >"$PJ_WORK/xvfb.log" 2>&1 &
  echo $! >"$PJ_WORK/xvfb.pid"
  for _ in $(seq 50); do xdotool getmouselocation >/dev/null 2>&1 && return 0; sleep 0.1; done
  echo "Xvfb didn't start" >&2
  return 1
}

# Starts the app like a normal desktop session: a non-C locale (the mpv crash
# needs one), its own home folder, and a tmpfs XDG_RUNTIME_DIR. Mesa's CPU
# renderer is forced, since there's no GPU here. Extra NAME=value pairs are
# passed through to the app's environment. PJ_WRAP runs the app through a
# wrapper, such as tool/desktop_check/under_gdb.sh.
pj_start_app() {
  env -i PATH=/usr/bin:/bin DISPLAY="$PJ_DISPLAY" HOME="$PJ_HOME" XDG_RUNTIME_DIR="$PJ_RUNTIME" \
    XDG_CONFIG_HOME="$PJ_HOME/.config" XDG_DATA_HOME="$PJ_HOME/.local/share" \
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LIBGL_ALWAYS_SOFTWARE=1 "$@" \
    dbus-run-session -- ${PJ_WRAP:+$PJ_WRAP} "${PJ_EXE:-$PJ_BUNDLE/portfolio_jockey}" >>"$PJ_WORK/app.log" 2>&1 &
  echo $! >"$PJ_WORK/app.pid"
  local win=""
  for _ in $(seq 100); do
    win=$(xdotool search --name '^Portfolio Jockey$' 2>/dev/null | head -n1)
    [ -n "$win" ] && break
    sleep 0.1
  done
  [ -n "$win" ] || { echo "The app window didn't appear" >&2; return 1; }
  xdotool windowsize "$win" 1280 900 windowmove "$win" 0 0
  # There is no window manager, so nothing has focus until we give it.
  xdotool windowfocus --sync "$win"
  sleep 3
}

pj_app_pid() { pgrep -f -n "${PJ_EXE:-$PJ_BUNDLE/portfolio_jockey}" || true; }
pj_app_alive() { [ -n "$(pj_app_pid)" ]; }

pj_stop_app() {
  local pid
  pid=$(pj_app_pid)
  [ -n "$pid" ] && kill "$pid" 2>/dev/null
  for _ in $(seq 30); do pj_app_alive || break; sleep 0.1; done
  pid=$(pj_app_pid)
  [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
  [ -f "$PJ_WORK/app.pid" ] && kill "$(cat "$PJ_WORK/app.pid")" 2>/dev/null
  rm -f "$PJ_WORK/app.pid"
  return 0
}

pj_stop_all() {
  pj_stop_app
  [ -f "$PJ_WORK/xvfb.pid" ] && kill "$(cat "$PJ_WORK/xvfb.pid")" 2>/dev/null
  rm -f "$PJ_WORK/xvfb.pid"
  return 0
}

# pj_shot NAME [x y w h]: saves shots/NAME.png, optionally cropped.
pj_shot() {
  local name=$1
  shift
  python3 -I "$PJ_APP/tool/desktop_check/xwd2png.py" "$PJ_WORK/fb/Xvfb_screen0" "$PJ_SHOTS/$name.png" "$@"
  echo "$PJ_SHOTS/$name.png"
}

# A short fingerprint of the screen, to tell whether it changed.
pj_screen_hash() { sha256sum "$PJ_WORK/fb/Xvfb_screen0" | cut -c1-16; }

pj_click() { xdotool mousemove "$1" "$2" sleep 0.25 click "${3:-1}"; sleep "${PJ_PAUSE:-1.2}"; }
pj_type() { xdotool type --delay 20 -- "$1"; sleep 1.2; }
pj_key() { xdotool key "$@"; sleep "${PJ_PAUSE:-1.2}"; }

# Waits up to $2 seconds (default 5) for a file or folder test to pass.
pj_wait_for() {
  local cond=$1 limit=${2:-5}
  for _ in $(seq $((limit * 10))); do eval "$cond" && return 0; sleep 0.1; done
  return 1
}

# A fingerprint of one area of the screen (x y w h), e.g. only the video.
pj_region_hash() {
  python3 -I "$PJ_APP/tool/desktop_check/xwd2png.py" "$PJ_WORK/fb/Xvfb_screen0" "$PJ_WORK/region.png" "$@"
  sha256sum "$PJ_WORK/region.png" | cut -c1-16
}

# Clicks, then waits up to $3 seconds (default 6) for the screen to change.
# Fails if nothing changed, so a missed click is noticed instead of the next
# click landing somewhere else.
pj_click_wait() {
  local before limit=${3:-6}
  # Hover effects change the screen too, so let them settle first.
  xdotool mousemove "$1" "$2"
  sleep 1
  before=$(pj_screen_hash)
  xdotool click 1
  for _ in $(seq $((limit * 5))); do
    sleep 0.2
    [ "$(pj_screen_hash)" != "$before" ] && { sleep 0.8; return 0; }
  done
  echo "Nothing changed after clicking $1,$2" >&2
  return 1
}

# Is the app's main thread blocked on a lock? When idle it waits in poll().
pj_main_blocked() { [ "$(cat /proc/"$(pj_app_pid)"/wchan 2>/dev/null)" = futex_wait_queue ]; }

# One close-while-playing round on the project screen: open the file card at
# ($1,$2), Preview, press Play, check for motion (video only), close, then
# check that a menu still opens. Prints one result line labelled $3.
pj_media_round() {
  local cx=$1 cy=$2 label=$3 video=${4:-1}
  pj_click_wait "$cx" "$cy" || { echo "$label: the file menu didn't open"; return 1; }
  pj_click_wait $((cx + 69)) $((cy + 64)) || { echo "$label: the preview didn't open"; return 1; }
  local copy=no
  pj_wait_for '[ -n "$(find "$PJ_RUNTIME/portfolio_jockey" -type f 2>/dev/null)" ]' 10 && copy=yes
  sleep 3
  xdotool mousemove 500 500 sleep 0.3 mousemove 58 855 sleep 0.5 click 1
  sleep 1
  xdotool mousemove 1100 600
  sleep 1.5
  local playing=n/a a b
  if [ "$video" = 1 ]; then
    a=$(pj_region_hash 20 130 944 300); sleep 1.2; b=$(pj_region_hash 20 130 944 300)
    [ "$a" != "$b" ] && playing=yes || playing=NO
  fi
  local closed=yes resp=NO
  pj_click_wait 28 28 || closed=NO
  sleep 6 # media_kit destroys mpv 5 s after dispose; a freeze shows after that
  pj_click_wait 462 362 4 && resp=yes
  xdotool key Escape; sleep 1.5; xdotool mousemove 700 700; sleep 0.5
  local left
  left=$(find "$PJ_RUNTIME/portfolio_jockey" -type f 2>/dev/null | wc -l)
  echo "$label: copy-while-open=$copy playing=$playing closed=$closed responds=$resp blocked=$(pj_main_blocked && echo YES || echo no) files-left=$left"
  [ "$resp" = yes ]
}
