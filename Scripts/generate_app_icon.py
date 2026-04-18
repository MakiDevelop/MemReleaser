from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
ICONSET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
BASE_SIZE = 1024
PANEL_BOUNDS = (92, 92, 932, 932)
INNER_BOUNDS = (132, 132, 892, 892)
CHIP_BOUNDS = (248, 292, 776, 716)
BADGE_BOUNDS = (664, 188, 852, 376)


def hex_rgba(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def vertical_gradient(size: tuple[int, int], top: str, bottom: str) -> Image.Image:
    image = Image.new("RGBA", size)
    draw = ImageDraw.Draw(image)
    top_rgba = hex_rgba(top)
    bottom_rgba = hex_rgba(bottom)

    height = max(size[1] - 1, 1)
    for y in range(size[1]):
        t = y / height
        color = tuple(
            round(top_rgba[i] * (1 - t) + bottom_rgba[i] * t) for i in range(4)
        )
        draw.line((0, y, size[0], y), fill=color)

    return image


def radial_glow(
    size: tuple[int, int], center: tuple[int, int], radius: int, color: str, alpha: int
) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = image.load()
    rgba = hex_rgba(color)
    max_distance = max(radius, 1)

    for y in range(size[1]):
        for x in range(size[0]):
            distance = math.hypot(x - center[0], y - center[1])
            if distance > radius:
                continue
            t = 1 - distance / max_distance
            eased = t * t
            pixels[x, y] = rgba[:3] + (round(alpha * eased),)

    return image


def shadow(size: tuple[int, int], bounds: tuple[int, int, int, int], radius: int, blur: int) -> Image.Image:
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(bounds, radius=radius, fill=(0, 0, 0, 150))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def draw_bar(draw: ImageDraw.ImageDraw, bounds: tuple[int, int, int, int], color_top: str, color_bottom: str) -> None:
    bar = vertical_gradient((bounds[2] - bounds[0], bounds[3] - bounds[1]), color_top, color_bottom)
    mask = rounded_mask(bar.size, 26)
    overlay = Image.new("RGBA", bar.size, (0, 0, 0, 0))
    overlay.paste(bar, (0, 0), mask)
    draw._image.alpha_composite(overlay, bounds[:2])  # type: ignore[attr-defined]


def build_icon() -> Image.Image:
    canvas = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (0, 0, 0, 0))

    canvas.alpha_composite(shadow(canvas.size, (110, 126, 914, 938), radius=212, blur=34))

    panel_size = (PANEL_BOUNDS[2] - PANEL_BOUNDS[0], PANEL_BOUNDS[3] - PANEL_BOUNDS[1])
    panel = vertical_gradient(panel_size, "#0B1C2B", "#123D53")
    panel = ImageChops.screen(panel, radial_glow(panel_size, (640, 156), 280, "#F97316", 160))
    panel = ImageChops.screen(panel, radial_glow(panel_size, (180, 640), 320, "#22D3EE", 120))
    panel_mask = rounded_mask(panel_size, 212)
    panel_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    panel_layer.paste(panel, PANEL_BOUNDS[:2], panel_mask)
    canvas.alpha_composite(panel_layer)

    inner_size = (INNER_BOUNDS[2] - INNER_BOUNDS[0], INNER_BOUNDS[3] - INNER_BOUNDS[1])
    inner = vertical_gradient(inner_size, "#163247", "#0E2434")
    inner = ImageChops.screen(inner, radial_glow(inner_size, (520, 120), 260, "#FDE68A", 54))
    inner_mask = rounded_mask(inner_size, 176)
    inner_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    inner_layer.paste(inner, INNER_BOUNDS[:2], inner_mask)
    canvas.alpha_composite(inner_layer)

    detail = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(detail)
    draw.rounded_rectangle(PANEL_BOUNDS, radius=212, outline=hex_rgba("#D9F4FF", 56), width=3)
    draw.rounded_rectangle(INNER_BOUNDS, radius=176, outline=hex_rgba("#F8FAFC", 36), width=3)

    detail.alpha_composite(shadow(canvas.size, (272, 322, 788, 742), radius=126, blur=26))
    chip_size = (CHIP_BOUNDS[2] - CHIP_BOUNDS[0], CHIP_BOUNDS[3] - CHIP_BOUNDS[1])
    chip = vertical_gradient(chip_size, "#F8FAFC", "#D8E4EA")
    chip = ImageChops.screen(chip, radial_glow(chip_size, (130, 54), 170, "#FFFFFF", 64))
    chip_mask = rounded_mask(chip_size, 120)
    chip_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    chip_layer.paste(chip, CHIP_BOUNDS[:2], chip_mask)
    detail.alpha_composite(chip_layer)
    draw.rounded_rectangle(CHIP_BOUNDS, radius=120, outline=hex_rgba("#F8FAFC", 148), width=4)

    slot_bounds = [
        (316, 368, 386, 610),
        (402, 332, 472, 610),
        (488, 390, 558, 610),
        (574, 352, 644, 610),
        (660, 404, 730, 610),
    ]
    slot_colors = [
        ("#0F766E", "#38BDF8"),
        ("#155E75", "#22D3EE"),
        ("#0F766E", "#5EEAD4"),
        ("#A16207", "#FBBF24"),
        ("#C2410C", "#FB923C"),
    ]
    for bounds, colors in zip(slot_bounds, slot_colors, strict=True):
        draw.rounded_rectangle(bounds, radius=26, fill=hex_rgba("#0E2434", 72))
        draw_bar(draw, bounds, colors[0], colors[1])

    for x in (304, 382, 460, 538, 616, 694):
        draw.rounded_rectangle((x, 260, x + 22, 304), radius=10, fill=hex_rgba("#D8E4EA", 220))
        draw.rounded_rectangle((x, 704, x + 22, 748), radius=10, fill=hex_rgba("#D8E4EA", 220))

    draw.line((320, 650, 704, 650), fill=hex_rgba("#0F2534", 68), width=20)
    draw.rounded_rectangle((340, 628, 684, 672), radius=22, fill=hex_rgba("#EDF3F7", 220))
    draw.line((372, 650, 440, 650), fill=hex_rgba("#0F766E", 188), width=14)
    draw.line((468, 650, 548, 650), fill=hex_rgba("#F59E0B", 168), width=14)
    draw.line((576, 650, 652, 650), fill=hex_rgba("#C2410C", 188), width=14)

    detail.alpha_composite(shadow(canvas.size, (678, 206, 866, 394), radius=94, blur=18))
    badge_size = (BADGE_BOUNDS[2] - BADGE_BOUNDS[0], BADGE_BOUNDS[3] - BADGE_BOUNDS[1])
    badge = vertical_gradient(badge_size, "#FED7AA", "#F97316")
    badge = ImageChops.screen(badge, radial_glow(badge_size, (54, 44), 80, "#FFF7ED", 96))
    badge_mask = rounded_mask(badge_size, 94)
    badge_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    badge_layer.paste(badge, BADGE_BOUNDS[:2], badge_mask)
    detail.alpha_composite(badge_layer)
    draw.rounded_rectangle(BADGE_BOUNDS, radius=94, outline=hex_rgba("#FFFBEB", 164), width=3)
    draw.arc((708, 232, 808, 332), start=200, end=340, fill=hex_rgba("#132B3C", 212), width=14)
    draw.line((758, 282, 798, 258), fill=hex_rgba("#132B3C", 232), width=12)
    draw.ellipse((744, 268, 772, 296), fill=hex_rgba("#132B3C", 232))

    for coords, alpha in [((222, 220, 324, 236), 88), ((198, 256, 288, 270), 66), ((204, 292, 270, 304), 48)]:
        draw.rounded_rectangle(coords, radius=8, fill=hex_rgba("#E0F2FE", alpha))

    canvas.alpha_composite(detail)
    return canvas


def save_iconset(base_icon: Image.Image) -> None:
    sizes = {
        "appicon-16.png": 16,
        "appicon-16@2x.png": 32,
        "appicon-32.png": 32,
        "appicon-32@2x.png": 64,
        "appicon-128.png": 128,
        "appicon-128@2x.png": 256,
        "appicon-256.png": 256,
        "appicon-256@2x.png": 512,
        "appicon-512.png": 512,
        "appicon-512@2x.png": 1024,
    }
    for filename, size in sizes.items():
        output = base_icon.resize((size, size), Image.Resampling.LANCZOS)
        output.save(ICONSET / filename)


if __name__ == "__main__":
    ICONSET.mkdir(parents=True, exist_ok=True)
    save_iconset(build_icon())
