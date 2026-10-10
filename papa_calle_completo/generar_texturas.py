"""
Genera las texturas del mapa (letreros, logos, patrones) en la carpeta texturas/.
Requiere Pillow:  pip install pillow
Los PNG ya vienen hechos; solo corre este script si quieres cambiar textos o colores.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

AQUI = os.path.dirname(os.path.abspath(__file__))
SALIDA = os.path.join(AQUI, "texturas")
os.makedirs(SALIDA, exist_ok=True)

CANDIDATAS = [
    "/usr/share/fonts/truetype/google-fonts/Poppins-BoldItalic.ttf",
    "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
]
FUENTE = next((f for f in CANDIDATAS if os.path.exists(f)), None)
S = 2  # supersampling para bordes suaves


class Lienzo:
    def __init__(self, w, h, fondo=(255, 255, 255)):
        self.w, self.h = w, h
        self.im = Image.new("RGB", (w*S, h*S), fondo)
        self.d = ImageDraw.Draw(self.im)

    def _p(self, pts):
        return [(x*S, y*S) for x, y in pts]

    def degradado(self, c1, c2):
        n = self.h*S
        for y in range(n):
            t = y/(n-1)
            c = tuple(int(c1[i]+(c2[i]-c1[i])*t) for i in range(3))
            self.d.line([(0, y), (self.w*S, y)], fill=c)

    def rect(self, x0, y0, x1, y1, relleno=None, borde=None, grosor=0, r=0):
        caja = [x0*S, y0*S, x1*S, y1*S]
        gr = int(grosor*S) if borde else 0
        if r:
            self.d.rounded_rectangle(caja, radius=r*S, fill=relleno, outline=borde, width=gr)
        else:
            self.d.rectangle(caja, fill=relleno, outline=borde, width=gr)

    def elipse(self, cx, cy, rx, ry, relleno=None, borde=None, grosor=0):
        gr = int(grosor*S) if borde else 0
        self.d.ellipse([(cx-rx)*S, (cy-ry)*S, (cx+rx)*S, (cy+ry)*S],
                       fill=relleno, outline=borde, width=gr)

    def poly(self, pts, relleno, borde=None, grosor=0):
        self.d.polygon(self._p(pts), fill=relleno)
        if borde:
            self.d.line(self._p(pts+[pts[0]]), fill=borde, width=int(grosor*S), joint="curve")

    def linea(self, pts, color, grosor):
        self.d.line(self._p(pts), fill=color, width=int(grosor*S), joint="curve")

    def texto(self, cx, cy, txt, size, relleno, borde=None, bw=0, ancho_max=None):
        tam = size
        while True:
            f = ImageFont.truetype(FUENTE, int(tam*S)) if FUENTE else ImageFont.load_default()
            w = self.d.textlength(txt, font=f)
            if ancho_max is None or w <= ancho_max*S or tam < 12:
                break
            tam -= 4
        self.d.text((cx*S, cy*S), txt, font=f, fill=relleno, anchor="mm",
                    stroke_width=int(bw*S) if borde else 0, stroke_fill=borde)

    def guardar(self, nombre):
        self.im.resize((self.w, self.h), Image.LANCZOS).save(
            os.path.join(SALIDA, nombre), optimize=True)


# ---------------- dibujos reutilizables ----------------
def garra(L, cx, cy, r, color):
    L.elipse(cx, cy+r*0.3, r*0.62, r*0.5, color)
    for dx, dy, s in ((-0.95, -0.1, 0.26), (-0.38, -0.62, 0.28),
                      (0.38, -0.62, 0.28), (0.95, -0.1, 0.26)):
        L.elipse(cx+dx*r, cy+dy*r, s*r, s*r*1.2, color)


def cara_perro(L, cx, cy, r, tipo):
    tinta = (40, 25, 20)
    if tipo == "caniche":
        pelo, borde = (222, 190, 250), (120, 80, 170)
        for a in range(0, 360, 45):
            x = cx+math.cos(math.radians(a))*r*0.85
            y = cy+math.sin(math.radians(a))*r*0.8
            L.elipse(x, y, r*0.38, r*0.38, pelo, borde, 3)
        L.elipse(cx, cy, r*0.8, r*0.85, pelo, borde, 3)
        L.elipse(cx, cy+r*0.3, r*0.5, r*0.38, (255, 240, 255), borde, 2)
    else:
        if tipo == "shiba":
            cuerpo, orejas, hocico = (240, 150, 60), (200, 100, 30), (255, 235, 200)
        else:
            cuerpo, orejas, hocico = (120, 130, 165), (50, 55, 85), (235, 238, 250)
        for sg in (-1, 1):
            L.poly([(cx+sg*r*0.95, cy-r*0.05), (cx+sg*r*0.75, cy-r*1.3),
                    (cx+sg*r*0.15, cy-r*0.8)], orejas, tinta, 3)
        L.elipse(cx, cy, r, r*0.92, cuerpo, tinta, 4)
        L.elipse(cx, cy+r*0.3, r*0.62, r*0.5, hocico, tinta, 3)
    for sg in (-1, 1):
        L.elipse(cx+sg*r*0.38, cy-r*0.15, r*0.2, r*0.24, (255, 255, 255), tinta, 3)
        L.elipse(cx+sg*r*0.4, cy-r*0.12, r*0.1, r*0.14, (20, 15, 20))
        L.elipse(cx+sg*r*0.43, cy-r*0.18, r*0.04, r*0.05, (255, 255, 255))
    L.elipse(cx, cy+r*0.62, r*0.16, r*0.2, (255, 110, 150), tinta, 2)   # lengua
    L.elipse(cx, cy+r*0.18, r*0.17, r*0.12, (25, 20, 25))               # nariz
    L.linea([(cx-r*0.3, cy+r*0.45), (cx, cy+r*0.5), (cx+r*0.3, cy+r*0.45)], tinta, 4)
    if tipo == "caniche":
        L.poly([(cx-r*0.5, cy-r*0.85), (cx-r*0.55, cy-r*1.3), (cx-r*0.25, cy-r*1.05),
                (cx, cy-r*1.4), (cx+r*0.25, cy-r*1.05), (cx+r*0.55, cy-r*1.3),
                (cx+r*0.5, cy-r*0.85)], (255, 205, 50), (150, 100, 0), 3)
        for sg in (-1, 1):
            L.rect(cx+sg*r*0.38-r*0.25, cy-r*0.34, cx+sg*r*0.38+r*0.25, cy+r*0.0,
                   (40, 30, 70), (255, 120, 170), 4, r=8)
        L.linea([(cx-r*0.13, cy-r*0.2), (cx+r*0.13, cy-r*0.2)], (255, 120, 170), 4)


def papas_icono(L, cx, cy, s):
    L.poly([(cx-s*0.6, cy-s*0.1), (cx+s*0.6, cy-s*0.1), (cx+s*0.45, cy+s*0.8),
            (cx-s*0.45, cy+s*0.8)], (220, 30, 40), (90, 10, 10), 3)
    for k in range(5):
        x = cx-s*0.42+k*s*0.21
        L.rect(x, cy-s*0.75-(k % 2)*s*0.15, x+s*0.17, cy-s*0.05, (255, 210, 50), (170, 120, 0), 2)


def tijeras(L, cx, cy, s, color):
    L.linea([(cx-s*0.5, cy+s*0.6), (cx+s*0.6, cy-s*0.7)], color, 10)
    L.linea([(cx+s*0.5, cy+s*0.6), (cx-s*0.6, cy-s*0.7)], color, 10)
    for sg in (-1, 1):
        L.elipse(cx+sg*s*0.45, cy+s*0.7, s*0.28, s*0.28, None, color, 8)


def marco(L, color, grosor=10, r=34, m=8):
    L.rect(m, m, L.w-m, L.h-m, None, color, grosor, r=r)


# ---------------- carteles ----------------
def veterinaria():
    L = Lienzo(1024, 256)
    L.degradado((30, 85, 205), (15, 35, 110))
    marco(L, (90, 230, 255))
    L.elipse(135, 128, 82, 82, (255, 255, 255), (90, 230, 255), 6)
    garra(L, 135, 128, 52, (30, 80, 200))
    L.texto(560, 128, "VETERINARIA", 118, (255, 255, 255), (10, 30, 90), 6, ancho_max=640)
    L.rect(924, 74, 958, 182, (90, 230, 255), (255, 255, 255), 3)
    L.rect(886, 112, 996, 146, (90, 230, 255), (255, 255, 255), 3)
    L.rect(925, 113, 957, 145, (90, 230, 255))
    L.guardar("veterinaria.png")


def heroes():
    L = Lienzo(1024, 192)
    L.degradado((40, 100, 220), (20, 55, 150))
    marco(L, (255, 255, 255), 8, 30, 6)
    L.texto(512, 96, "¡HÉROES DE CUATRO PATAS!", 100, (255, 245, 200), (15, 35, 100), 6, ancho_max=900)
    L.guardar("heroes.png")


def papas():
    L = Lienzo(1024, 256)
    L.degradado((120, 50, 25), (70, 28, 15))
    marco(L, (255, 170, 40))
    papas_icono(L, 130, 140, 130)
    L.texto(590, 128, "PAPAS FRITAS", 125, (255, 215, 60), (80, 25, 10), 7, ancho_max=700)
    L.guardar("papas.png")


def pelu():
    L = Lienzo(1024, 256)
    L.degradado((220, 50, 175), (140, 30, 130))
    marco(L, (255, 210, 245))
    tijeras(L, 120, 125, 85, (150, 240, 255))
    L.texto(520, 118, "PELUQUERÍA", 100, (255, 255, 255), (100, 10, 90), 6, ancho_max=560)
    L.texto(520, 192, "CANINA", 68, (255, 235, 120), (100, 10, 90), 5, ancho_max=400)
    garra(L, 920, 128, 52, (255, 235, 250))
    L.guardar("pelu.png")


def mercado():
    L = Lienzo(1024, 256)
    L.degradado((225, 55, 45), (170, 25, 30))
    marco(L, (255, 215, 70))
    garra(L, 120, 128, 60, (255, 240, 200))
    L.texto(525, 128, "MERCADO CANINO", 110, (255, 245, 210), (110, 15, 15), 6, ancho_max=610)
    garra(L, 925, 128, 48, (255, 240, 200))
    L.guardar("mercado.png")


def dogcity():
    L = Lienzo(1024, 256, (12, 16, 45))
    L.degradado((20, 25, 75), (8, 10, 30))
    marco(L, (110, 235, 255), 8, 30, 6)
    L.texto(512, 128, "DOG CITY", 175, (30, 120, 170), (30, 120, 170), 14, ancho_max=860)
    L.texto(512, 128, "DOG CITY", 175, (200, 250, 255), (90, 225, 255), 5, ancho_max=860)
    L.guardar("dogcity.png")


def comepapas():
    L = Lienzo(1024, 512)
    L.degradado((255, 170, 30), (235, 110, 15))
    marco(L, (255, 245, 200), 12, 40, 10)
    cara_perro(L, 255, 275, 185, "shiba")
    L.texto(700, 190, "¡COME", 150, (255, 255, 255), (110, 40, 0), 9, ancho_max=480)
    L.texto(700, 340, "PAPAS!", 150, (255, 235, 90), (110, 40, 0), 9, ancho_max=480)
    L.guardar("comepapas.png")


def cuadrado_perro(nombre, tipo, c1, c2, borde):
    L = Lienzo(512, 512)
    L.degradado(c1, c2)
    marco(L, borde, 12, 40, 10)
    cara_perro(L, 256, 280, 170, tipo)
    L.guardar(nombre)


def logo_papas():
    L = Lienzo(256, 256, (210, 25, 35))
    L.elipse(128, 128, 100, 100, (255, 255, 255))
    garra(L, 128, 128, 62, (210, 25, 35))
    L.guardar("logo_papas.png")


# ---------------- patrones ----------------
def toldo():
    L = Lienzo(256, 256)
    for i in range(8):
        L.rect(i*32, 0, (i+1)*32, 256, (225, 40, 40) if i % 2 == 0 else (255, 250, 240))
    L.guardar("toldo.png")


def barrera():
    L = Lienzo(512, 128, (255, 210, 30))
    for x0 in range(-128, 640, 96):
        L.poly([(x0, 0), (x0+48, 0), (x0+176, 128), (x0+128, 128)], (25, 25, 30))
    L.guardar("barrera.png")


def caja():
    L = Lienzo(256, 256, (176, 122, 66))
    for y in (64, 128, 192):
        L.linea([(0, y), (256, y)], (130, 85, 40), 4)
    L.rect(7, 7, 249, 249, None, (105, 65, 28), 14)
    L.linea([(10, 10), (246, 246)], (105, 65, 28), 12)
    L.linea([(246, 10), (10, 246)], (105, 65, 28), 12)
    L.guardar("caja.png")


def cubo_garra():
    L = Lienzo(256, 256, (58, 58, 72))
    L.rect(6, 6, 250, 250, None, (105, 105, 130), 10, r=18)
    garra(L, 128, 128, 62, (255, 100, 210))
    L.guardar("cubo_garra.png")


def vidrio():
    L = Lienzo(256, 256)
    L.degradado((165, 232, 250), (70, 160, 205))
    L.poly([(40, 0), (90, 0), (0, 90), (0, 40)], (205, 244, 255))
    L.poly([(150, 0), (175, 0), (0, 175), (0, 150)], (205, 244, 255))
    L.poly([(256, 120), (256, 150), (150, 256), (120, 256)], (140, 205, 235))
    L.guardar("vidrio.png")


def ladrillo():
    random.seed(3)
    L = Lienzo(256, 256, (150, 145, 140))
    for fila in range(8):
        y = fila*32
        desp = 32 if fila % 2 else 0
        for x in range(-64, 320, 64):
            v = random.randint(205, 245)
            L.rect(x+desp+2, y+2, x+desp+62, y+30, (v, v, v))
    L.guardar("ladrillo.png")


if __name__ == "__main__":
    veterinaria()
    heroes()
    papas()
    pelu()
    mercado()
    dogcity()
    comepapas()
    cuadrado_perro("shiba.png", "shiba", (255, 190, 90), (240, 130, 40), (255, 245, 200))
    cuadrado_perro("caniche.png", "caniche", (170, 80, 200), (110, 40, 150), (255, 200, 245))
    cuadrado_perro("bulldog.png", "bulldog", (70, 120, 220), (35, 70, 160), (190, 235, 255))
    logo_papas()
    toldo()
    barrera()
    caja()
    cubo_garra()
    vidrio()
    ladrillo()
    print("Texturas listas en", SALIDA)
