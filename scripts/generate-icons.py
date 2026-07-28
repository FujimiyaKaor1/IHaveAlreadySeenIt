#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Assets" / "IconSource.jpg"
BACKGROUND_SOURCE = ROOT / "Assets" / "BackgroundSource.jpg"
OUTPUT = ROOT / "Packaging" / "GeneratedIcons"
ICONSET = OUTPUT / "IHaveAlreadySeenIt.iconset"
APP_RESOURCES = ROOT / "Sources" / "IHaveAlreadySeenItApp" / "Resources"


def render_master() -> Image.Image:
    source = Image.open(SOURCE).convert("RGB")
    # Fit the supplied square artwork before generating every required macOS size.
    width, height = source.size
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    source = source.crop((left, top, left + side, top + side))
    source = source.resize((920, 920), Image.Resampling.LANCZOS)
    source = source.filter(ImageFilter.UnsharpMask(radius=1.4, percent=120, threshold=3))

    canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (52, 66, 972, 986), radius=218, fill=(24, 51, 60, 92)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    panel = Image.new("RGBA", (920, 920), (0, 0, 0, 0))
    image_layer = source.convert("RGBA")

    mask = Image.new("L", panel.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, panel.width - 1, panel.height - 1), radius=205, fill=255
    )
    panel.paste(image_layer, (0, 0), mask)
    canvas.alpha_composite(panel, (52, 52))

    border = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        (52, 52, 971, 971),
        radius=205,
        outline=(255, 255, 255, 155),
        width=3,
    )
    canvas.alpha_composite(border)
    return canvas


def render_background() -> None:
    if not BACKGROUND_SOURCE.is_file():
        raise SystemExit(f"Missing background source: {BACKGROUND_SOURCE}")
    background = Image.open(BACKGROUND_SOURCE).convert("RGB")
    background.thumbnail((1920, 1440), Image.Resampling.LANCZOS)
    APP_RESOURCES.mkdir(parents=True, exist_ok=True)
    background.save(
        APP_RESOURCES / "CommunityBackground.jpg",
        quality=88,
        optimize=True,
        progressive=True,
    )


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing icon source: {SOURCE}")
    render_background()
    shutil.rmtree(OUTPUT, ignore_errors=True)
    ICONSET.mkdir(parents=True)

    master = render_master()
    master.save(OUTPUT / "AppIcon.png", optimize=True)
    variants = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }
    for filename, size in variants.items():
        master.resize((size, size), Image.Resampling.LANCZOS).save(
            ICONSET / filename, optimize=True
        )

    subprocess.run(
        ["/usr/bin/iconutil", "-c", "icns", str(ICONSET), "-o", str(OUTPUT / "AppIcon.icns")],
        check=True,
    )
    shutil.rmtree(ICONSET)


if __name__ == "__main__":
    main()
