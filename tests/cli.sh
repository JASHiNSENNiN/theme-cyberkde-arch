#!/usr/bin/env bash
# tests/cli.sh: checks for the English command line and the bilingual messages.
# Runs only read-only commands, against a throwaway HOME: nothing on the desktop changes.
#   bash tests/cli.sh
set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cli=$root/scripts/cyberkde
fails=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }

# 1. English names map to the Portuguese ones (and Portuguese passes through).
(
  source <(sed -n '/^declare -A cli_en_cmd=/,/^nome_cli()/p' "$cli")
  check() {  # expected args...
    local want=$1
    shift
    cli_en_para_pt "$@"
    [[ "${cli_args[*]}" == "$want" ]] && pass "alias: $* -> $want" || fail "alias: $* -> '${cli_args[*]}' (want '$want')"
  }
  check "efeito janelas --abrir moldura --fechar nenhuma" effect windows --open frame --close none
  check "efeito splash nenhum" effect splash none
  check "efeito estilo-marcador --variante nenhum" effect style-marker --variant none
  check "efeito login --entrada=completa" effect login --entrance=full
  check "efeito login --entrada curta" effect login --entrance short
  check "efeito estilo-abas --variante sublinhada" effect style-tabs --variant underline
  check "efeito icones music=padrao" effect icons music=default
  check "corp nenhuma" corp none
  check "cor padrao --sem-sudo" color default --no-sudo
  check "cerca snapshot listar" fence snapshot list
  check "cerca regras aplicar --simular" fence rules apply --simulate
  check "widgets estado" widgets status
  check "ilha status" island status
  check "efeito widget-relogio on --posicao superior-direito --modo medio" effect widget-clock on --position top-right --mode medium
  check "efeito papel usuario:new.mp4" effect wallpaper user:new.mp4
  check "arquivos new" files new
  check "on login-bloqueio" on lock-screen
  check "layout lateral --aplicar" layout side --apply
  check "papel /home/u/none.jpg" wallpaper /home/u/none.jpg
  check "cor #ff0040" color "#ff0040"
  check "efeito janelas --abrir glitch" efeito janelas --abrir glitch
  check "papel frame" wallpaper frame
  check "papel padrao" wallpaper default
  check "padrao konsole" original konsole
  check "corp militech --sem-sudo" corp militech --no-sudo
  check "cor padrao" cor default
  check "" ""
  exit "$fails"
) || fails=$((fails + $?))

# 2. Every $(t ...) call gets exactly two arguments (pt, en).
mapfile -t calls < <(python3 -I - "$root" <<'PY'
import glob, sys
root = sys.argv[1]
files = [root + "/scripts/cyberkde", root + "/instalar.sh"] + sorted(glob.glob(root + "/modules/*/phase.sh"))
for f in files:
    raw = open(f, encoding="utf-8").read().split("\n")
    joined, k = [], 0
    while k < len(raw):  # join "\" continuations so multi-line calls are read whole
        n, line = k + 1, raw[k]
        while line.endswith("\\") and k + 1 < len(raw):
            k += 1
            line = line[:-1] + " " + raw[k].lstrip()
        joined.append((n, line))
        k += 1
    for n, line in joined:
        if line.lstrip().startswith("#"):
            continue
        i = line.find("$(t ")
        while i != -1:
            # Quote-aware scan: parentheses inside "..." or '...' do not count.
            stack, j = ["cmd"], i + 2
            while j < len(line) and stack:
                c, top = line[j], stack[-1]
                if c == "\\":
                    j += 2
                    continue
                if top == "cmd":
                    if c == '"':
                        stack.append("dq")
                    elif c == "'":
                        j = line.index("'", j + 1)
                    elif line.startswith("$(", j):
                        stack.append("cmd")
                        j += 1
                    elif c == "(":
                        stack.append("par")
                    elif c == ")":
                        stack.pop()
                elif top == "par":
                    if c == ")":
                        stack.pop()
                    elif c == "(":
                        stack.append("par")
                elif top == "dq":
                    if c == '"':
                        stack.pop()
                    elif line.startswith("$(", j):
                        stack.append("cmd")
                        j += 1
                j += 1
            print(f"{f.replace(root + '/', '')}:{n}\t{line[i:j]}")
            i = line.find("$(t ", j)
PY
)
bad_cmd=$(printf '%s\n' "${calls[@]}" | grep -E '\$\((rm|sudo|kill|mv|cp|tee|dd)\b' || true)
[[ -z $bad_cmd ]] && pass "t(): no side-effect commands inside messages" || fail "t(): commands inside messages: $bad_cmd"
arity=0
for c in "${calls[@]}"; do
  loc=${c%%$'\t'*} expr=${c#*$'\t'}
  out=$(bash -c 't() { [[ $# -eq 2 ]] || { echo "ARITY $#"; exit 1; }; printf %s "$2"; }
command_not_found_handle() { return 0; }
: '"$expr" 2>/dev/null </dev/null) || { fail "t() arity at $loc: $out"; arity=1; }
done
(( arity )) || pass "t(): ${#calls[@]} calls, all with 2 arguments"

# 3. trap '...' bodies parse (bash -n does not look inside single quotes).
trap_bad=0
while IFS= read -r body; do
  bash -n -c "$body" 2>/dev/null || { fail "trap body does not parse: $body"; trap_bad=1; }
done < <(grep -hE "^\s*trap '" "$cli" "$root"/modules/*/phase.sh |
  python3 -I -c 'import shlex,sys
for l in sys.stdin:
    a = shlex.split(l.strip(), comments=False)
    print(a[1].replace("\n", " "))')
(( trap_bad )) || pass "trap bodies parse"

# 4. Commands, in a throwaway HOME.
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
run() { HOME=$tmp XDG_CONFIG_HOME=$tmp/.config XDG_DATA_HOME=$tmp/.local/share XDG_STATE_HOME=$tmp/.local/state \
  XDG_CACHE_HOME=$tmp/.cache "$cli" "$@" 2>&1; }

for j in "fases --json" "status --json" "efeito --lista --json" "corp --lista --json"; do
  pt=$(CYBERKDE_LANG=pt run $j) en=$(CYBERKDE_LANG=en run $j)
  python3 -I -c 'import json,sys; json.load(sys.stdin)' <<<"$pt" 2>/dev/null || { fail "json: $j is not valid JSON"; continue; }
  [[ $pt == "$en" ]] && pass "json: '$j' is the same in both languages" || fail "json: '$j' changes with the language"
done

[[ $(LANG=en_US.UTF-8 CYBERKDE_LANG= run help | head -1) == cyberkde:* ]] && pass "lang: English locale -> English" || fail "lang: English locale"
[[ $(LANG=pt_BR.UTF-8 CYBERKDE_LANG= run help | head -1) == *aplica* ]] && pass "lang: pt_BR locale -> Portuguese" || fail "lang: pt_BR locale"
[[ $(LANG=C CYBERKDE_LANG= run help | head -1) == cyberkde:* ]] && pass "lang: C locale -> English" || fail "lang: C locale"

for c in "help" "effect" "effect --list" "phases" "status" "wallpaper" "color" "layout" "corp --list" \
  "effect windows" "effect motion" "effect style-cut" "ajuda" "efeito --lista" "fases" "papel" "cor"; do
  CYBERKDE_LANG=en run $c >/dev/null && pass "run: $c" || fail "run: $c (exit $?)"
done
for c in "effect bogus" "on bogus" "corp bogus" "color nothex"; do
  CYBERKDE_LANG=en run $c >/dev/null
  [[ $? == 2 ]] && pass "usage error: $c -> 2" || fail "usage error: $c"
done

# 5. Boot screen: plymouthd.conf gets Theme=cyberkde under [Daemon] and keeps the other lines.
(
  source <(sed -n '/^boot_conf_novo()/,/^}/p' "$root/modules/boot/phase.sh")
  tmp=$(mktemp)
  boot_conf=$tmp
  printf '[Daemon]\nTheme=cachyos-bootanimation\nShowDelay=0\n[Other]\nTheme=x\n' >"$tmp"
  want=$'[Daemon]\nTheme=cyberkde\nShowDelay=0\n[Other]\nTheme=x'
  [[ $(boot_conf_novo) == "$want" ]] && pass "boot: Theme replaced in [Daemon] only" || fail "boot: got '$(boot_conf_novo)'"
  printf '# empty\n' >"$tmp"
  [[ $(boot_conf_novo) == $'# empty\n[Daemon]\nTheme=cyberkde' ]] && pass "boot: [Daemon] added when missing" || fail "boot: missing section"
  rm -f -- "$tmp"
)

echo
(( fails == 0 )) && echo "all passed" || echo "$fails failed"
exit $(( fails > 0 ))
