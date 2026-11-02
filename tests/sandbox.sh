#!/usr/bin/env bash
# tests/sandbox.sh: install, on and off in a sealed sandbox, then check that "off" put every
# setting back. The real desktop is never touched: own PID namespace (pkill cannot see the real
# plasmashell), private D-Bus, fake HOME and runtime dir, no display, sudo disabled.
# Starts from a copy of your KDE config (read only), so the restore is checked on real values.
#   bash tests/sandbox.sh            (needs unshare with user namespaces, and dbus-run-session)
set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ ${1:-} != --inside ]]; then
  w=$(mktemp -d)
  echo "sandbox: $w"
  exec unshare --user --map-root-user --pid --fork --mount-proc \
    dbus-run-session -- env REALHOME="$HOME" bash "${BASH_SOURCE[0]}" --inside "$w"
fi

w=$2
files=(kdeglobals kwinrc plasmarc kscreenlockerrc ksplashrc kcminputrc dolphinrc konsolerc)
mkdir -p "$w/home/.config" "$w/run"
chmod 700 "$w/run"
for f in "${files[@]}" plasma-org.kde.plasma.desktop-appletsrc; do
  [[ -f $REALHOME/.config/$f ]] && cp "$REALHOME/.config/$f" "$w/home/.config/$f"
done
[[ -d $REALHOME/.config/kdedefaults ]] && cp -a "$REALHOME/.config/kdedefaults" "$w/home/.config/"
cp -a "$w/home/.config" "$w/before"

export HOME=$w/home XDG_CONFIG_HOME=$w/home/.config XDG_DATA_HOME=$w/home/.local/share \
  XDG_STATE_HOME=$w/home/.local/state XDG_CACHE_HOME=$w/home/.cache XDG_RUNTIME_DIR=$w/run \
  XDG_CONFIG_DIRS=$w/home/.config/kdedefaults:/etc/xdg CYBERKDE_SEM_SUDO=1 PATH=/usr/bin:/bin
unset WAYLAND_DISPLAY DISPLAY SUDO_ASKPASS
cli=$root/scripts/cyberkde
fails=0
step() {  # name allowed-exit-codes command...
  local name=$1 ok=$2 rc
  shift 2
  timeout 900 "$@" </dev/null >>"$w/log" 2>&1
  rc=$?
  if [[ " $ok " == *" $rc "* ]]; then echo "ok    $name (exit $rc)"; else echo "FAIL  $name (exit $rc, see $w/log)"; fails=$((fails + 1)); fi
}
step install "0" "$cli" install
step on "0 4" "$cli" on            # 4 = applied, login pending (no sudo here)
step status "0" "$cli" status
step off "0" "$cli" off
grep -qiE 'unbound variable|syntax error|command not found|bad array subscript' "$w/log" &&
  { echo "FAIL  shell errors in $w/log"; fails=$((fails + 1)); }

effective() {  # config-dir file
  XDG_CONFIG_HOME=$1 XDG_CONFIG_DIRS=$1/kdedefaults:/etc/xdg kreadconfig6 --file "$2" --dump 2>/dev/null | sort
}
for f in "${files[@]}"; do
  if [[ $(effective "$w/before" "$f") == "$(effective "$w/home/.config" "$f")" ]]; then
    echo "ok    $f: same effective values after off"
  else
    echo "FAIL  $f: effective values changed after off"
    diff <(effective "$w/before" "$f") <(effective "$w/home/.config" "$f") | head -10
    fails=$((fails + 1))
  fi
done

echo
(( fails == 0 )) && echo "all passed" || echo "$fails failed"
exit $(( fails > 0 ))
