#!/usr/bin/env python3
"""Tema do Plymouth (tela de boot) CyberKDE: logo da corporação, fantasmas de glitch e varredura.

    gen_boot.py --logo <svg|png> [--saida <pasta>]

Grava em <saida>/cyberkde/ o .plymouth, o .script e as imagens, nas cores da paleta atual
(cyberkde cor/corp). O logo SVG é rasterizado com o rsvg-convert.
"""
import argparse
import pathlib
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "generator"))
from cyberlib import ALERTA, CYAN, RED, TOK, rgb  # noqa: E402

LOGO_MAX = (1000, 420)  # px; o script reduz para a tela (máx. 34% da largura)
LINHAS = 2160  # altura da textura das linhas de varredura (cobre até 4K)


def carregar_logo(caminho: pathlib.Path) -> Image.Image:
    if caminho.suffix.lower() == ".svg":
        with tempfile.TemporaryDirectory() as tmp:
            png = pathlib.Path(tmp) / "logo.png"
            subprocess.run(["rsvg-convert", "-w", str(LOGO_MAX[0]), "-o", str(png), str(caminho)], check=True)
            img = Image.open(png).convert("RGBA")
    else:
        img = Image.open(caminho).convert("RGBA")
    caixa = img.getbbox()  # sem a margem transparente, para centralizar pelo desenho
    if caixa:
        img = img.crop(caixa)
    esc = min(LOGO_MAX[0] / img.width, LOGO_MAX[1] / img.height, 1.0)
    if esc < 1.0:
        img = img.resize((round(img.width * esc), round(img.height * esc)), Image.Resampling.LANCZOS)
    return img


def fantasma(logo: Image.Image, cor: str) -> Image.Image:
    """Silhueta do logo numa cor só (o deslocamento de canal do glitch)."""
    chapa = Image.new("RGBA", logo.size, rgb(cor) + (255,))
    chapa.putalpha(logo.getchannel("A"))
    return chapa


def linhas_varredura() -> Image.Image:
    """1 px de largura (o script estica): uma linha escura a cada 3, como um monitor CRT."""
    img = Image.new("RGBA", (1, LINHAS), (0, 0, 0, 0))
    for y in range(0, LINHAS, 3):
        img.putpixel((0, y), (0, 0, 0, 70))
    return img


def faixa_varredura(cor: str) -> Image.Image:
    """Faixa de luz que desce pela tela: 1 px de largura, 48 px de altura, mais forte no meio."""
    r, g, b = rgb(cor)
    img = Image.new("RGBA", (1, 48), (0, 0, 0, 0))
    for y in range(48):
        a = 1.0 - abs(y - 40) / 40 if y <= 40 else 1.0 - (y - 40) / 8  # rastro em cima, borda em baixo
        img.putpixel((0, y), (r, g, b, round(70 * max(a, 0.0))))
    return img


def pixel(cor: str, alfa: int = 255) -> Image.Image:
    return Image.new("RGBA", (1, 1), rgb(cor) + (alfa,))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--logo", required=True)
    ap.add_argument("--saida", default=str(HERE.parent / "build"))
    a = ap.parse_args()
    fundo = TOK["reference"]["darkestBlue"]

    saida = pathlib.Path(a.saida) / "cyberkde"
    if saida.exists():
        shutil.rmtree(saida)
    saida.mkdir(parents=True)

    logo = carregar_logo(pathlib.Path(a.logo))
    logo.save(saida / "logo.png", optimize=True)
    fantasma(logo, CYAN).save(saida / "ghost-a.png", optimize=True)
    fantasma(logo, ALERTA).save(saida / "ghost-b.png", optimize=True)
    linhas_varredura().save(saida / "lines.png")
    faixa_varredura(RED).save(saida / "sweep.png")
    pixel(RED).save(saida / "bar.png")
    pixel(RED, 60).save(saida / "track.png")

    r, g, b = (c / 255 for c in rgb(fundo))
    script = (HERE / "cyberkde.script").read_text()
    script = script.replace("@FUNDO_R@", f"{r:.4f}").replace("@FUNDO_G@", f"{g:.4f}").replace("@FUNDO_B@", f"{b:.4f}")
    (saida / "cyberkde.script").write_text(script)
    (saida / "cyberkde.plymouth").write_text(
        "[Plymouth Theme]\n"
        "Name=CyberKDE\n"
        "Description=CyberKDE boot screen: corporation logo with a scanline glitch\n"
        "ModuleName=script\n\n"
        "[script]\n"
        "ImageDir=/usr/share/plymouth/themes/cyberkde\n"
        "ScriptFile=/usr/share/plymouth/themes/cyberkde/cyberkde.script\n"
    )
    print(saida)


if __name__ == "__main__":
    main()
