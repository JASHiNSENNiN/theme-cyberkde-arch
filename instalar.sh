#!/usr/bin/env bash
# instalar.sh — instala o CyberKDE para o usuário atual (sem root).
#
#   ./instalar.sh              instala (ou atualiza) o programa e os arquivos do tema, sem ligar nada
#   ./instalar.sh --ligar      instala e já liga o tema inteiro
#   ./instalar.sh --continuar  segue mesmo com itens "!" na checagem (o que eles afetam fica diferente)
#   ./instalar.sh --sem-latte  não instala o Latte Dock (a dock fica um painel do Plasma)
#   ./instalar.sh --sem-animados  não instala o Dolphin e o Konsole animados
#
# Põe também o "Painel do CyberKDE" no menu de aplicativos (fica lá com o tema desligado).
#
# Antes de tudo, confere os pré-requisitos e os problemas conhecidos ("cyberkde checar") e diz como
# corrigir cada um. O programa vai para ~/.local/opt/cyberkde e o comando para ~/.local/bin/cyberkde.
# Depois disso esta pasta pode ser apagada. Para remover tudo: ./desinstalar.sh (ou "cyberkde uninstall").

set -euo pipefail

# Message language: the session's ($LC_ALL/$LC_MESSAGES/$LANG); Portuguese only for pt* locales.
case ${CYBERKDE_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}} in pt*) lang=pt ;; *) lang=en ;; esac
export CYBERKDE_LANG=$lang
t() { if [[ $lang == en ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }  # pt en

src="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
dest="$HOME/.local/opt/cyberkde"
bin_dir="$HOME/.local/bin"
link="$bin_dir/cyberkde"
ligar=0 continuar=0 latte=1 animados=1

for arg in "$@"; do
  case $arg in
    --ligar | --on) ligar=1 ;;
    --continuar | --continue) continuar=1 ;;
    --sem-latte | --no-latte) latte=0 ;;
    --sem-animados | --no-animated) animados=0 ;;
    -h | --help)
      if [[ $lang == pt ]]; then sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi
      cat <<'HELP'
instalar.sh: install CyberKDE for the current user (no root).

  ./instalar.sh                 install (or update) the program and theme files, turn nothing on
  ./instalar.sh --on            install and turn the whole theme on
  ./instalar.sh --continue      go on even with "!" items in the check
  ./instalar.sh --no-latte      do not install Latte Dock (the dock is a Plasma panel)
  ./instalar.sh --no-animated   do not install the animated Dolphin and Konsole

The program goes to ~/.local/opt/cyberkde and the command to ~/.local/bin/cyberkde; this folder
can be deleted afterwards. To remove everything: cyberkde uninstall.
HELP
      exit 0 ;;
    *) echo "$(t "opção desconhecida: $arg (use --ligar, --continuar, --sem-latte, --sem-animados ou --help)" "unknown option: $arg (use --on, --continue, --no-latte, --no-animated or --help)")" >&2; exit 2 ;;
  esac
done

if (( EUID == 0 )); then
  echo "$(t "Rode como o seu usuário, sem sudo: o tema é por usuário. Quando precisar de root (tela de login), o próprio cyberkde pede a senha." "Run as your own user, without sudo: the theme is per user. When root is needed (login screen), cyberkde asks for the password itself.")" >&2
  exit 1
fi

# --- Pré-requisitos e problemas conhecidos --------------------------------------------------------
rc=0
"$src/scripts/cyberkde" checar || rc=$?
if (( rc == 1 )); then
  exit 1
elif (( rc == 2 && ! continuar )); then
  echo "$(t "Nada foi instalado. Depois de corrigir, rode de novo; para seguir assim mesmo: ./instalar.sh --continuar ${*}" "Nothing was installed. Fix it and run again; to go on anyway: ./instalar.sh --continue ${*}")" >&2
  exit 1
fi
echo

# --- Cópia do programa ----------------------------------------------------------------------------
# Só o que o tema usa: sem histórico do git, imagens de referência, prévias ou opções descartadas.
lista=$(mktemp)
trap 'rm -f "$lista"' EXIT
if git -C "$src" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # Rastreados + novos ainda sem commit (respeitando o .gitignore).
  git -C "$src" ls-files -z --cached --others --exclude-standard >"$lista"
else
  (cd "$src" && find . -type f ! -path './.git/*' -printf '%P\0') >"$lista"
fi
novo="$dest.novo"
rm -rf -- "$novo"
mkdir -p -- "$novo"
while IFS= read -r -d '' f; do
  case $f in
    imagens-referencia/* | backups/* | */preview/* | modules/papeis-de-parede/opcoes/* | \
      assets/icons/ai-raw/* | assets/icons/ai-alt/* | assets/icons/scripts/* | assets/icons/preview*.png | \
      scripts/baixar_imagens_referencia.sh | instalar.sh | desinstalar.sh | */__pycache__/* | .github/* | \
      modules/*/build/* | dolphin/src/* | dolphin/build/* | konsole/src/* | konsole/build/* | latte/*) continue ;;
  esac
  [[ -f $src/$f ]] || continue  # apagado na pasta e ainda não commitado
  install -D -m "$(stat -c %a "$src/$f")" -- "$src/$f" "$novo/$f"
done <"$lista"
# Apps compilados (Dolphin/Konsole): o código baixado fica junto do programa; numa atualização, reaproveita.
for app in dolphin konsole latte; do
  for sub in src build; do
    if [[ -d $dest/$app/$sub ]]; then mkdir -p -- "$novo/$app"; mv -- "$dest/$app/$sub" "$novo/$app/$sub"; fi
  done
done
: >"$novo/.instalado"  # marca: o "cyberkde uninstall" desta cópia também remove o programa
chmod 755 "$novo/scripts/cyberkde"
atualizacao=0
if [[ -d $dest ]]; then atualizacao=1; fi
rm -rf -- "$dest.velho"
if [[ -d $dest ]]; then mv -T -- "$dest" "$dest.velho"; fi
mv -T -- "$novo" "$dest"
rm -rf -- "$dest.velho"

# --- Comando --------------------------------------------------------------------------------------
mkdir -p -- "$bin_dir"
if [[ -e $link && ! -L $link ]]; then
  echo "$(t "Já existe um arquivo em $link que não é do CyberKDE; não vou sobrescrever." "$link already exists and is not CyberKDE's; it will not be overwritten.")" >&2
  echo "$(t "O programa ficou em $dest; rode $dest/scripts/cyberkde diretamente." "The program is in $dest; run $dest/scripts/cyberkde directly.")" >&2
  exit 1
fi
ln -sfn -- "$dest/scripts/cyberkde" "$link"
avisos=()
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    # O ~/.profile (Ubuntu/Debian) só põe ~/.local/bin no PATH se a pasta já existia no login. Um
    # terminal novo não resolve: só um login novo.
    if grep -qs '\.local/bin' "$HOME/.profile" "$HOME/.bash_profile"; then
      avisos+=("$(t "O comando 'cyberkde' só funciona depois de sair e entrar na sessão (o $bin_dir acabou de ser criado). Até lá, neste terminal: export PATH=\"\$HOME/.local/bin:\$PATH\"  (ou use $link)" "The 'cyberkde' command only works after logging out and back in ($bin_dir was just created). Until then, in this terminal: export PATH=\"\$HOME/.local/bin:\$PATH\"  (or use $link)")")
    else
      avisos+=("$(t "$bin_dir não está no PATH. Acrescente ao ~/.profile: export PATH=\"\$HOME/.local/bin:\$PATH\"  e saia e entre na sessão (até lá, use $link)." "$bin_dir is not in PATH. Add to ~/.profile: export PATH=\"\$HOME/.local/bin:\$PATH\"  and log out and back in (until then, use $link).")")
    fi
    ;;
esac

# --- Barra e dock ---------------------------------------------------------------------------------
# Instalação nova: arranjo das capturas (barra em cima, dock). Quem já usava o CyberKDE continua
# com a barra e a dock que tem ("cyberkde layout tema" muda depois).
layout_pref="${XDG_CONFIG_HOME:-$HOME/.config}/cyberkde/layout"
if [[ ! -s $layout_pref ]]; then
  mkdir -p -- "$(dirname -- "$layout_pref")"
  if (( atualizacao )); then echo manter >"$layout_pref"; else echo tema >"$layout_pref"; fi
fi
# Dock das capturas: o Latte Dock NG, pelo pacote revisado ("cyberkde latte"), só nos ambientes
# validados (hoje, Ubuntu 26.04). Fora deles (ou com --sem-latte), a dock é um painel do Plasma, sem
# pergunta. Nada é compilado (no Arch: compila o PKGBUILD de arch/latte-dock-ng).
if [[ $(<"$layout_pref") == tema ]] && (( latte )) && [[ ${XDG_SESSION_TYPE:-wayland} == wayland ]] &&
  "$dest/scripts/cyberkde" latte --disponivel &&
  ! command -v latte-dock-ng >/dev/null && [[ ! -x $HOME/.local/bin/latte-dock-ng ]] && ! command -v latte-dock >/dev/null; then
  resposta=s
  if [[ -t 0 ]]; then
    if command -v pacman >/dev/null && ! command -v apt-get >/dev/null; then
      como=$(t "compila o PKGBUILD revisado, alguns minutos; pede a senha" "builds the reviewed PKGBUILD, a few minutes; asks for the password")
    else
      como=$(t "pacote revisado; pede a senha" "reviewed package; asks for the password")
    fi
    read -r -p "$(t "A dock das capturas é o Latte Dock NG. Instalar agora ($como)? [S/n] " "The dock in the screenshots is Latte Dock NG. Install it now ($como)? [Y/n] ")" resposta || resposta=n
  fi
  case ${resposta,,} in
    n | no | nao | não) avisos+=("$(t "Sem o Latte, a dock é um painel do Plasma. Para instalar depois: cyberkde latte" "Without Latte, the dock is a Plasma panel. To install it later: cyberkde latte")") ;;
    *) "$dest/scripts/cyberkde" latte || avisos+=("$(t "O Latte não foi instalado; a dock é um painel do Plasma. Para tentar de novo: cyberkde latte" "Latte was not installed; the dock is a Plasma panel. To try again: cyberkde latte")") ;;
  esac
fi

# Dolphin e Konsole animados, por pacote revisado (Ubuntu 26.04); no Arch, compilados com o patch da versão instalada.
if (( animados )) && "$dest/scripts/cyberkde" animados --disponivel; then
  resposta=s
  if [[ -t 0 ]]; then
    if command -v pacman >/dev/null && ! command -v apt-get >/dev/null; then
      como=$(t "compila os apps do sistema com o patch, ~10-20 min; a senha só para as dependências de compilação" "builds the system apps with the patch, ~10-20 min; password only for build dependencies")
    else
      como=$(t "pacotes revisados, pede a senha" "reviewed packages, asks for the password")
    fi
    read -r -p "$(t "Instalar o Dolphin e o Konsole animados (cascata ao abrir pastas, texto animado; $como)? [S/n] " "Install the animated Dolphin and Konsole (cascade when opening folders, animated text; $como)? [Y/n] ")" resposta || resposta=n
  fi
  case ${resposta,,} in
    n | no | nao | não) avisos+=("$(t "Para instalar depois o Dolphin e o Konsole animados: cyberkde animados" "To install the animated Dolphin and Konsole later: cyberkde animated")") ;;
    *) "$dest/scripts/cyberkde" animados || avisos+=("$(t "Dolphin/Konsole animados não instalados; ficam os do sistema." "Animated Dolphin/Konsole not installed; the system apps stay.")") ;;
  esac
fi

# --- Lançador do painel ---------------------------------------------------------------------------
# "Painel do CyberKDE" no menu de aplicativos. Fica FORA do registro do tema (ledger/files.tsv): o
# "cyberkde off" não o tira, porque o painel tem de continuar no menu com o tema desligado — é por ele
# que se liga o tema. Quem remove é o "cyberkde uninstall". O modelo vem do painel (app/): @APP@ vira
# a pasta app/ instalada. O nome do arquivo tem de ser cyberkde-painel.desktop: é o desktopFileName do
# painel, e sem ele o Wayland não acha o ícone nem o nome da janela.
modelo="$dest/app/cyberkde-painel.desktop"
lancador="${XDG_DATA_HOME:-$HOME/.local/share}/applications/cyberkde-painel.desktop"
if [[ -f $modelo ]]; then
  mkdir -p -- "$(dirname -- "$lancador")"
  # Sem as linhas de comentário do modelo (instruções para quem instala) e com @APP@ trocado.
  sed -e '/^#/d' -e "s|@APP@|$dest/app|g" "$modelo" >"$lancador.novo"
  mv -f -- "$lancador.novo" "$lancador"
  # O painel precisa do PyQt6 e de módulos QML do Qt 6; o tema funciona sem ele. Só avisa, com a linha
  # do apt (o "cyberkde checar" acima já mostrou o mesmo).
  if ! falta_painel=$("$dest/scripts/cyberkde" painel --checar 2>/dev/null); then
    avisos+=("$(t "O painel gráfico precisa de pacotes que faltam. Para usar o painel: $falta_painel" "The graphical panel needs missing packages. To use it: $falta_painel")")
  fi
else
  avisos+=("$(t "Esta versão não traz o painel gráfico (app/cyberkde-painel.desktop); use os comandos." "This version has no graphical panel (app/cyberkde-painel.desktop); use the commands.")")
fi

# --- Arquivos do tema -----------------------------------------------------------------------------
echo "$(t "Gerando e instalando os arquivos do tema (pode levar um minuto)…" "Generating and installing the theme files (may take a minute)…")"
"$dest/scripts/cyberkde" install

echo
if (( atualizacao )); then echo "$(t "CyberKDE atualizado em $dest." "CyberKDE updated in $dest.")"; else echo "$(t "CyberKDE instalado em $dest." "CyberKDE installed in $dest.")"; fi
for a in "${avisos[@]}"; do echo "$(t Aviso Note): $a"; done
ligado=$("$dest/scripts/cyberkde" status --json | grep -q '^{"ligado":true' && echo 1 || echo 0)
# Sem ~/.local/bin no PATH ainda, as instruções usam o caminho completo.
cmd=cyberkde
case ":$PATH:" in *":$bin_dir:"*) ;; *) cmd=$link ;; esac
if (( ligar )); then
  "$dest/scripts/cyberkde" on
elif (( ligado )); then
  echo "$(t "O tema já estava ligado: rode '$cmd on' para aplicar a versão nova." "The theme was already on: run '$cmd on' to apply the new version.")"
else
  echo "$(t "Para ligar: $cmd on        Para desligar: $cmd off        Remover tudo: $cmd uninstall" "Turn on: $cmd on        Turn off: $cmd off        Remove everything: $cmd uninstall")"
fi
