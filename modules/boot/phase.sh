# modules/boot/phase.sh — tela de boot (Plymouth) CyberKDE: o logo da corporação com glitch e
# linhas de varredura, nas cores da paleta. Gerado por generator/gen_boot.py.
# Carregado com "source" pelo scripts/cyberkde: só define funções e registra nomes.
#
#   boot  tema "cyberkde" em /usr/share/plymouth/themes e Theme=cyberkde no plymouthd.conf (sudo).
#         Entra no "cyberkde on" (tudo); o "cyberkde corp/cor" refaz com o logo e as cores novos.
#         O "off" devolve o plymouthd.conf de antes (o tema do sistema volta) e apaga a pasta.

CYBERKDE_PHASES+=(boot)
descreve_fase boot "Tela de boot" sistema sim "Logo da corporação com glitch na tela de boot do Plymouth (pede sudo)." \
  "Boot screen" "Corporation logo with a glitch on the Plymouth boot screen (needs sudo)."

boot_tema=/usr/share/plymouth/themes/cyberkde
boot_conf=/etc/plymouth/plymouthd.conf

# O logo largo da corporação; sem corporação (ou sem logo), o ícone do painel.
boot_logo() {
  local logo
  logo=$(corp_logo_largo "$(corp_atual)")
  printf '%s\n' "${logo:-$project/app/cyberkde-painel.svg}"
}

# plymouthd.conf com Theme=cyberkde, mantendo as outras linhas (ShowDelay, DeviceTimeout...).
boot_conf_novo() {
  if [[ -f $boot_conf ]] && grep -q '^\[Daemon\]' "$boot_conf"; then
    awk '/^\[/ { sec = $0 } sec == "[Daemon]" && /^Theme=/ { next } { print } $0 == "[Daemon]" { print "Theme=cyberkde" }' "$boot_conf"
  else
    [[ -f $boot_conf ]] && cat -- "$boot_conf"
    printf '[Daemon]\nTheme=cyberkde\n'
  fi
}

phase_boot() {
  if ! command -v plymouthd >/dev/null 2>&1 || [[ ! -d /usr/share/plymouth/themes ]]; then
    echo "$(t "  (sem Plymouth: a tela de boot fica como está)" "  (no Plymouth: the boot screen stays as it is)")"
    return 0
  fi
  if [[ ! -f /usr/lib/plymouth/script.so ]]; then
    echo "$(t "  (o Plymouth não tem o módulo script: a tela de boot fica como está)" "  (Plymouth has no script module: the boot screen stays as it is)")"
    return 0
  fi
  local stage
  stage=$(mktemp -d)
  python3 "$project/modules/boot/generator/gen_boot.py" --logo "$(boot_logo)" --saida "$stage" >/dev/null || { rm -rf -- "$stage"; return 1; }
  find "$stage" -type d -exec chmod 755 {} + && find "$stage" -type f -exec chmod 644 {} +
  put_dir "$stage/cyberkde" "$boot_tema"
  rm -rf -- "$stage"
  boot_conf_novo | put_file "$boot_conf"
  # Com o hook do Plymouth no initramfs, a tela de boot sai de lá: só muda depois do mkinitcpio -P.
  if grep -qE '^HOOKS=.*\bplymouth\b' /etc/mkinitcpio.conf 2>/dev/null; then
    echo "$(t "  Aviso: o Plymouth está no initramfs. Rode 'sudo mkinitcpio -P' para ver a tela nova no boot." \
      "  Note: Plymouth is in the initramfs. Run 'sudo mkinitcpio -P' to see the new screen at boot.")"
  fi
}
