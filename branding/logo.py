from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math

S = 1024  # Arbeitsgröße

def lerp(a, b, t): return tuple(int(a[i] + (b[i]-a[i])*t) for i in range(len(a)))

def background(size=S):
    """Diagonaler Verlauf dunkles Petrol -> Petrol."""
    bg = Image.new("RGB", (size, size))
    px = bg.load()
    c0, c1 = (6, 46, 48), (11, 122, 117)
    for y in range(size):
        for x in range(size):
            t = (x*0.35 + y*0.65) / size
            px[x, y] = lerp(c0, c1, min(1, t))
    return bg

def mark(size=S):
    """Das Motiv (transparent): Scheinwerfer + Lichtkegel mit RGB-Auslauf."""
    k = size / 1024
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Lichtkegel: Fächer aus drei Farbstreifen, oben schmal, unten breit
    apex = (512*k, 300*k)
    cone = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    cols = [(40, 190, 255), (255, 200, 40), (255, 70, 120)]
    spread = 0.25  # Radiant pro Streifen
    for i, c in enumerate(cols):
        a0 = math.pi/2 - spread*1.5 + i*spread
        a1 = a0 + spread
        L = 760*k
        pts = [apex,
               (apex[0] + L*math.cos(a0), apex[1] + L*math.sin(a0)),
               (apex[0] + L*math.cos(a1), apex[1] + L*math.sin(a1))]
        band = Image.new("L", (size, size), 0)
        ImageDraw.Draw(band).polygon(pts, fill=255)
        # nach unten ausblenden
        fade = Image.new("L", (size, size), 0)
        fd = ImageDraw.Draw(fade)
        for y in range(size):
            t = (y - apex[1]) / (700*k)
            v = 0 if t < 0 else int(255 * max(0, 1 - t) ** 0.7)
            fd.line([(0, y), (size, y)], fill=v)
        alpha = ImageChops.multiply(band, fade)
        solid = Image.new("RGBA", (size, size), c + (0,))
        solid.putalpha(alpha)
        cone = Image.alpha_composite(cone, solid)
    cone = cone.filter(ImageFilter.GaussianBlur(3*k))
    layer = Image.alpha_composite(layer, cone)

    # Glühen um die Linse
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    r = 190*k
    gd.ellipse([apex[0]-r, apex[1]-r, apex[0]+r, apex[1]+r], fill=(255, 210, 120, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(70*k))
    layer = Image.alpha_composite(layer, glow)

    d = ImageDraw.Draw(layer)
    # Bügel des Scheinwerfers
    w = 40*k
    d.arc([apex[0]-238*k, apex[1]-238*k, apex[0]+238*k, apex[1]+238*k], 205, 335, fill=(235, 245, 244, 255), width=int(w))
    # Gehäuse
    R = 175*k
    d.ellipse([apex[0]-R, apex[1]-R, apex[0]+R, apex[1]+R], fill=(236, 246, 245, 255))
    # Linse
    R2 = 122*k
    d.ellipse([apex[0]-R2, apex[1]-R2, apex[0]+R2, apex[1]+R2], fill=(255, 196, 40, 255))
    R3 = 66*k
    d.ellipse([apex[0]-R3, apex[1]-R3, apex[0]+R3, apex[1]+R3], fill=(255, 238, 190, 255))
    return layer

def rounded(img, radius):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0]-1, img.size[1]-1], radius=radius, fill=255)
    out = img.convert("RGBA"); out.putalpha(m); return out

full = Image.alpha_composite(background().convert("RGBA"), mark())
full.save("icon_square_1024.png")
rounded(full, 224).save("icon_rounded_1024.png")

# Adaptive-Icon-Vordergrund: Motiv auf 66 % verkleinert, zentriert, transparent
fg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
m = mark().resize((int(S*0.66), int(S*0.66)), Image.LANCZOS)
fg.paste(m, ((S - m.size[0])//2, (S - m.size[1])//2), m)
fg.save("adaptive_fg_1024.png")
background().save("adaptive_bg_1024.png")
print("ok")
