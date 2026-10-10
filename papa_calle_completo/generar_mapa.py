"""
Generador del mapa "Papa Caliente" v2  ->  papa_calle.glb  (+ papa_calle.obj / .mtl)
Calle recta a lo largo de -Z (el jugador avanza hacia -Z, como en Godot).
Unidades: 1 = 1 metro. Eje Y hacia arriba. Python puro, sin librerías externas.
Las texturas (letreros, logos) viven en la carpeta texturas/ (ver generar_texturas.py).
"""
import json
import math
import os
import random
import struct

# ---------------- PARÁMETROS (cámbialos a gusto) ----------------
SEMILLA = 7          # cambia el número para otra ciudad distinta
N_POR_LADO = 14      # edificios por lado
ANCHO_CALLE = 6.0    # medio ancho de la calzada (calzada total = 12)
ANCHO_ACERA = 3.0
PASO = 14.0          # separación entre edificios en Z
# ----------------------------------------------------------------

AQUI = os.path.dirname(os.path.abspath(__file__))
random.seed(SEMILLA)
L = 8 + PASO * N_POR_LADO  # largo total de la calle

# ---------------- materiales ----------------
MATS = {
    # suelo
    'asfalto': (0.20, 0.20, 0.28), 'acera': (0.78, 0.74, 0.68), 'suelo': (0.40, 0.65, 0.35),
    'linea': (1.00, 0.85, 0.15), 'cebra': (0.95, 0.95, 0.95), 'bordillo': (1.00, 0.82, 0.15),
    # paredes lisas
    'pared_azul': (0.25, 0.45, 0.85), 'pared_morada': (0.62, 0.25, 0.78),
    'pared_naranja': (0.96, 0.55, 0.20), 'pared_roja': (0.85, 0.20, 0.18),
    # paredes de ladrillo (la textura se tiñe con este color)
    'ladrillo_rojo': (1.00, 0.58, 0.48), 'ladrillo_crema': (1.00, 0.88, 0.68),
    'ladrillo_azul': (0.68, 0.78, 1.00),
    # techos, molduras, marcos
    'techo_rojo': (0.80, 0.18, 0.22), 'techo_marron': (0.40, 0.22, 0.12),
    'techo_azul': (0.20, 0.30, 0.65), 'techo_morado': (0.45, 0.18, 0.55),
    'cornisa': (0.97, 0.92, 0.80), 'marco': (0.95, 0.95, 0.98), 'puerta': (0.35, 0.18, 0.10),
    'toldo_azul': (0.20, 0.40, 0.95), 'toldo_rosa': (1.00, 0.40, 0.75),
    # piezas sueltas
    'metal': (0.40, 0.40, 0.45), 'metal_oscuro': (0.15, 0.15, 0.20), 'lampara': (1.00, 0.95, 0.60),
    'hidrante': (0.95, 0.25, 0.20), 'carton_rojo': (0.85, 0.10, 0.12), 'papa_frita': (1.00, 0.82, 0.20),
    'conos': (1.00, 0.50, 0.10), 'banco_madera': (0.62, 0.42, 0.22), 'buzon': (0.20, 0.35, 0.90),
    'portal': (0.60, 0.35, 0.18), 'tanque': (0.55, 0.35, 0.25), 'cuerda': (0.9, 0.9, 0.9),
    # neón (en Godot brillan)
    'neon_cian': (0.30, 0.95, 1.00), 'neon_rosa': (1.00, 0.30, 0.80), 'neon_amarillo': (1.00, 0.85, 0.20),
    # texturizados (color blanco = la textura se ve tal cual)
    'vidrio': (1, 1, 1), 'toldo_rayas': (1, 1, 1), 'barrera': (1, 1, 1), 'caja': (1, 1, 1),
    'garra_cubo': (1, 1, 1), 'logo_papas': (1, 1, 1),
    'cartel_veterinaria': (1, 1, 1), 'cartel_heroes': (1, 1, 1), 'cartel_papas': (1, 1, 1),
    'cartel_pelu': (1, 1, 1), 'cartel_mercado': (1, 1, 1), 'cartel_dogcity': (1, 1, 1),
    'cartel_comepapas': (1, 1, 1), 'cartel_shiba': (1, 1, 1), 'cartel_caniche': (1, 1, 1),
    'cartel_bulldog': (1, 1, 1),
}
EMISION = {'neon_cian': (0.3, 0.95, 1.0), 'neon_rosa': (1.0, 0.3, 0.8),
           'neon_amarillo': (1.0, 0.85, 0.2), 'lampara': (1.0, 0.9, 0.5)}
TEXTURA = {
    'vidrio': 'vidrio.png', 'toldo_rayas': 'toldo.png', 'barrera': 'barrera.png', 'caja': 'caja.png',
    'garra_cubo': 'cubo_garra.png', 'logo_papas': 'logo_papas.png',
    'cartel_veterinaria': 'veterinaria.png', 'cartel_heroes': 'heroes.png', 'cartel_papas': 'papas.png',
    'cartel_pelu': 'pelu.png', 'cartel_mercado': 'mercado.png', 'cartel_dogcity': 'dogcity.png',
    'cartel_comepapas': 'comepapas.png', 'cartel_shiba': 'shiba.png', 'cartel_caniche': 'caniche.png',
    'cartel_bulldog': 'bulldog.png',
    'ladrillo_rojo': 'ladrillo.png', 'ladrillo_crema': 'ladrillo.png', 'ladrillo_azul': 'ladrillo.png',
}
TILED = {'ladrillo_rojo', 'ladrillo_crema', 'ladrillo_azul'}  # UV en metros (el patrón se repite)

verts, norms, lines, caras = [], [], [], []
vt_lista, vt_idx = [], {}
mat_actual = [None]
UV4 = [(0, 0), (1, 0), (1, 1), (0, 1)]   # convención OBJ: v hacia arriba


# ---------------- utilidades de geometría ----------------
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def lerp(a, b, t): return a + (b-a)*t


def objeto(nombre):
    lines.append(f"o {nombre}")


def material(m):
    mat_actual[0] = m
    lines.append(f"usemtl {m}")


def vti(uv):
    k = (round(uv[0], 4), round(uv[1], 4))
    if k not in vt_idx:
        vt_lista.append(k)
        vt_idx[k] = len(vt_lista)
    return vt_idx[k]


def uv_mundo(pts, n, esc=3.0):
    if abs(n[1]) > 0.7:
        return [(p[0]/esc, p[2]/esc) for p in pts]
    eje = 2 if abs(n[0]) > abs(n[2]) else 0
    return [(p[eje]/esc, p[1]/esc) for p in pts]


def cara(pts, ref, uv=None):
    """Cara plana con la normal hacia afuera (lejos del punto interior ref)."""
    n = cross(sub(pts[1], pts[0]), sub(pts[2], pts[0]))
    c = tuple(sum(p[i] for p in pts)/len(pts) for i in range(3))
    flip = dot(n, sub(c, ref)) < 0
    if flip:
        pts = pts[::-1]
        n = (-n[0], -n[1], -n[2])
    ln = math.sqrt(dot(n, n))
    if ln < 1e-9:
        return
    n = (n[0]/ln, n[1]/ln, n[2]/ln)
    if uv is None:
        uv = [UV4[i % 4] for i in range(len(pts))]
    elif flip:
        uv = uv[::-1]
    if mat_actual[0] in TILED:
        uv = uv_mundo(pts, n)
    caras.append((mat_actual[0], list(pts), n, list(uv)))
    verts.extend(pts)
    norms.append(n)
    s = len(verts) - len(pts) + 1
    k = len(norms)
    lines.append("f " + " ".join(f"{s+i}/{vti(uv[i])}/{k}" for i in range(len(pts))))


def solido(p8):
    """8 puntos: 4 de abajo + 4 de arriba (mismo orden de esquinas)."""
    ref = tuple(sum(p[i] for p in p8)/8 for i in range(3))
    b, t = p8[:4], p8[4:]
    cara(b, ref)
    cara(t, ref)
    for i in range(4):
        j = (i+1) % 4
        cara([b[i], b[j], t[j], t[i]], ref)


def caja(cx, cy, cz, w, h, d, rx=0.0, ry=0.0, rz=0.0):
    """Caja centrada en (cx,cy,cz). w=eje X, h=eje Y, d=eje Z. Rotaciones en radianes."""
    pts = []
    for sy in (-1, 1):
        for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            x, y, z = sx*w/2, sy*h/2, sz*d/2
            y, z = y*math.cos(rx)-z*math.sin(rx), y*math.sin(rx)+z*math.cos(rx)
            x, y = x*math.cos(rz)-y*math.sin(rz), x*math.sin(rz)+y*math.cos(rz)
            x, z = x*math.cos(ry)+z*math.sin(ry), -x*math.sin(ry)+z*math.cos(ry)
            pts.append((cx+x, cy+y, cz+z))
    solido(pts)


def esquinas(cx, cz, xe, ze, y):
    return [(cx-xe/2, y, cz-ze/2), (cx+xe/2, y, cz-ze/2),
            (cx+xe/2, y, cz+ze/2), (cx-xe/2, y, cz+ze/2)]


def piramide(cx, cz, xe, ze, y, rh, over=0.8):
    c = esquinas(cx, cz, xe+over*2, ze+over*2, y)
    ap = (cx, y+rh, cz)
    ref = (cx, y+rh*0.3, cz)
    cara(c, ref)
    for i in range(4):
        cara([c[i], c[(i+1) % 4], ap], ref)


def dos_aguas(cx, cz, xe, ze, y, rh, over=0.8):
    c = esquinas(cx, cz, xe+over*2, ze+over*2, y)
    r0 = (cx, y+rh, cz-(ze/2+over))
    r1 = (cx, y+rh, cz+(ze/2+over))
    ref = (cx, y+rh*0.3, cz)
    cara(c, ref)
    cara([c[0], c[3], r1, r0], ref)
    cara([c[1], c[2], r1, r0], ref)
    cara([c[0], c[1], r0], ref)
    cara([c[3], c[2], r1], ref)


def cilindro(cx, cy, cz, r, h, seg=10):
    """Cilindro con la base en cy."""
    b = [(cx+r*math.cos(2*math.pi*i/seg), cy, cz+r*math.sin(2*math.pi*i/seg)) for i in range(seg)]
    t = [(p[0], cy+h, p[2]) for p in b]
    ref = (cx, cy+h/2, cz)
    cara(b, ref)
    cara(t, ref)
    for i in range(seg):
        j = (i+1) % seg
        cara([b[i], b[j], t[j], t[i]], ref)


# ---------------- letreros y logos ----------------
UV_CARTEL = [(0, 0), (1, 0), (1, 1), (0, 1)]


def poster(x, y, z, w, h, mat, lado, pend=0.0):
    """Cuadro con textura pegado a una fachada que mira a la calle. lado=-1 izq, +1 der."""
    material(mat)
    a, b = y-h/2, y+h/2
    X = lambda py: x - lado*0.02 + pend*(py-y)
    p0 = (X(a), a, z-lado*w/2)
    p1 = (X(a), a, z+lado*w/2)
    p2 = (X(b), b, z+lado*w/2)
    p3 = (X(b), b, z-lado*w/2)
    cara([p0, p1, p2, p3], (x+lado*1.0, y, z), uv=UV_CARTEL)


def cartel(x, y, z, w, h, mat, lado, pend=0.0, prof=0.3):
    """Letrero con tablero trasero metálico + cuadro texturizado."""
    material('metal_oscuro')
    caja(x+lado*prof/2, y, z, prof, h+0.3, w+0.3, rz=-math.atan(pend))
    poster(x, y, z, w, h, mat, lado, pend)


def cartel_z(x, y, zf, w, h, mat):
    """Letrero que mira hacia +Z (hacia donde viene el jugador). zf = plano frontal."""
    material('metal_oscuro')
    caja(x, y, zf-0.22, w+0.4, h+0.4, 0.44)
    material(mat)
    z = zf+0.02
    pts = [(x-w/2, y-h/2, z), (x+w/2, y-h/2, z), (x+w/2, y+h/2, z), (x-w/2, y+h/2, z)]
    cara(pts, (x, y, zf-1.0), uv=UV_CARTEL)


def ventana(xf, y, z, lado, ang):
    material('marco')
    caja(xf-lado*0.12, y, z, 0.24, 2.4, 2.2, rz=ang)
    material('vidrio')
    caja(xf-lado*0.26, y, z, 0.1, 2.0, 1.8, rz=ang)
    material('marco')
    caja(xf-lado*0.36, y-1.25, z, 0.55, 0.2, 2.6, rz=ang)   # alféizar


# ---------------- edificios ----------------
TIPOS = {
    'vet':     dict(pared='pared_azul',    techo='techo_azul',    h=(13, 16), neon='neon_cian',
                    rotulo='cartel_veterinaria', toldo='toldo_azul'),
    'pelu':    dict(pared='pared_morada',  techo='techo_morado',  h=(11, 14), neon='neon_rosa',
                    rotulo='cartel_pelu', toldo='toldo_rosa'),
    'mercado': dict(pared='pared_naranja', techo='techo_rojo',    h=(9, 12), neon='neon_amarillo',
                    rotulo='cartel_mercado', toldo='toldo_rayas'),
    'fries':   dict(pared='pared_roja',    techo=None,            h=(10, 13), neon='neon_amarillo',
                    rotulo='cartel_papas', toldo='toldo_rayas'),
    'casa':    dict(pared=None,            techo='techo_rojo',    h=(8, 15), neon=None,
                    rotulo=None, toldo='toldo_azul'),
}


def edificio(tipo, lado, z0, i):
    T = TIPOS[tipo]
    D = random.uniform(9, 11)             # profundidad (eje X)
    F = random.uniform(10, 11)            # frente (eje Z)
    h = random.uniform(*T['h'])
    base_x = lado*(ANCHO_CALLE+ANCHO_ACERA+D/2)
    lean = random.uniform(0.4, 2.0)       # inclinación caricaturesca hacia la calle
    lean_z = random.uniform(-0.7, 0.7)
    s = random.uniform(1.05, 1.20)        # los pisos de arriba se ensanchan
    if tipo == 'fries':
        s, lean, lean_z = 1.2, random.uniform(0, 0.5), 0.0
    topx, topz = base_x - lado*lean, z0 + lean_z
    xe, ze = D*s, F*s
    pared = T['pared'] or random.choice(['ladrillo_rojo', 'ladrillo_crema', 'ladrillo_azul'])

    objeto(f"{tipo}_{'izq' if lado < 0 else 'der'}_{i:02d}")
    material(pared)
    solido(esquinas(base_x, z0, D, F, 0) + esquinas(topx, topz, xe, ze, h))

    x_b, x_t = base_x - lado*D/2, topx - lado*xe/2
    pend = (x_t - x_b)/h
    ang = -math.atan(pend)
    fa = lambda y: lerp(x_b, x_t, y/h)            # x de la fachada a la altura y
    cz = lambda y: lerp(z0, topz, y/h)            # z del centro a la altura y
    der = lambda y, dz: cz(y) + lado*dz            # dz>0 = hacia la derecha de quien mira

    # --- planta baja ---
    if tipo != 'casa':
        y = 2.3
        gw = F*0.58
        gz = der(y, -F*0.12)
        material('marco')
        caja(fa(y)-lado*0.08, y, gz, 0.2, 3.0, gw+0.5, rz=ang)
        material('vidrio')
        caja(fa(y)-lado*0.2, y, gz, 0.1, 2.6, gw, rz=ang)
        poster_mat = {'vet': 'cartel_bulldog', 'pelu': 'cartel_caniche'}.get(tipo, 'cartel_shiba')
        poster(fa(y)-lado*0.27, y-0.1, der(y, -F*0.12-gw/2+1.4), 1.6, 1.6, poster_mat, lado, pend)
        y = 1.7
        material('marco')
        caja(fa(y)-lado*0.1, y, der(y, F*0.33), 0.24, 3.4, 2.4, rz=ang)
        material('puerta')
        caja(fa(y)-lado*0.22, 1.6, der(y, F*0.33), 0.1, 3.0, 1.9, rz=ang)
        material(T['neon'])
        caja(fa(4.5)-lado*0.3, 4.5, cz(4.5), 0.15, 0.15, F*0.95, rz=ang)
        material(T['toldo'])
        caja(fa(3.7)-lado*1.3, 3.7, cz(3.7), 2.4, 0.2, F*0.92, rz=lado*0.3)
        w = F*0.92
        cartel(fa(5.9)-lado*0.35, 5.9, cz(5.9), w, w/4, T['rotulo'], lado, pend)
        y_ini = 8.9
        if tipo == 'vet':
            cartel(fa(8.3)-lado*0.35, 8.3, cz(8.3), 7.5, 1.4, 'cartel_heroes', lado, pend)
            y_ini = 11.0
    else:
        for dz in (-3.8, -1.0):
            ventana(fa(2.4), 2.4, der(2.4, dz), lado, ang)
        material('marco')
        caja(fa(1.7)-lado*0.1, 1.7, der(1.7, 3.4), 0.24, 3.4, 2.4, rz=ang)
        material('puerta')
        caja(fa(1.7)-lado*0.22, 1.6, der(1.7, 3.4), 0.1, 3.0, 1.9, rz=ang)
        material(T['toldo'])
        caja(fa(3.9)-lado*1.0, 3.9, der(3.9, 3.4), 2.0, 0.2, 3.6, rz=lado*0.3)
        y_ini = 6.0

    # --- ventanas de los pisos altos ---
    y = y_ini
    while y < h-1.5:
        for dz in (-3.4, 0.0, 3.4):
            ventana(fa(y), y, der(y, dz), lado, ang)
        y += 3.6

    # --- moldura y techo ---
    if tipo != 'fries':
        material('cornisa')
        caja(topx, h-0.25, topz, xe+0.5, 0.5, ze+0.5)
    bx = topx - lado*(xe/2-0.7)
    if tipo in ('vet', 'pelu', 'mercado') or (tipo == 'casa' and random.random() < 0.5):
        material(T['techo'])
        caja(topx, h+0.2, topz, xe+0.6, 0.4, ze+0.6)
        if tipo == 'vet':
            cartel(bx, h+0.4+2.35, topz, 4.4, 4.4, 'cartel_bulldog', lado, 0, 0.4)
        elif tipo == 'pelu':
            cartel(bx, h+0.4+2.35, topz, 4.4, 4.4, 'cartel_caniche', lado, 0, 0.4)
        else:
            cartel(bx, h+0.4+1.9, topz, 7.0, 3.5, 'cartel_comepapas', lado, 0, 0.4)
        material('metal')
        for _ in range(2):
            caja(topx+random.uniform(-2, 2), h+0.9, topz+lado*random.uniform(3, 4)*random.choice((-1, 1)),
                 1.6, 1.0, 1.4)
        if tipo == 'casa' and random.random() < 0.6:
            material('metal_oscuro')
            for sx, sz in ((-0.6, -0.6), (0.6, -0.6), (0.6, 0.6), (-0.6, 0.6)):
                caja(topx-lado*2.5+sx, h+1.0, topz+3+sz, 0.15, 1.2, 0.15)
            material('tanque')
            cilindro(topx-lado*2.5, h+1.6, topz+3, 1.0, 1.6)
    elif tipo == 'fries':
        bw, bd, alto = xe*0.65, ze*0.65, 3.2
        material('carton_rojo')
        solido(esquinas(topx, topz, bw, bd, h) + esquinas(topx, topz, bw*1.25, bd*1.25, h+alto))
        xf0, xf1 = topx - lado*bw/2, topx - lado*bw*1.25/2
        poster((xf0+xf1)/2, h+alto/2, topz, 2.6, 2.6, 'logo_papas', lado, (xf1-xf0)/alto)
        material('papa_frita')
        for _ in range(12):
            hh = random.uniform(2.0, 4.0)
            caja(topx+random.uniform(-bw*0.55, bw*0.55), h+alto+hh/2-0.3,
                 topz+random.uniform(-bd*0.55, bd*0.55), 0.8, hh, 0.8,
                 rx=random.uniform(-0.2, 0.2), rz=random.uniform(-0.2, 0.2))
    else:
        material(random.choice(('techo_rojo', 'techo_marron')))
        piramide(topx, topz, xe, ze, h, random.uniform(2.5, 4.5))
        material('techo_marron')
        caja(topx+random.uniform(-1, 1), h+4.0, topz+random.uniform(-2, 2), 1.0, 3.0, 1.0)


# ---------------- mobiliario de calle ----------------
Y0 = 0.3  # altura de la banqueta


def farola(x, z, lado):
    material('metal_oscuro')
    caja(x, Y0+0.3, z, 0.5, 0.6, 0.5)
    caja(x, Y0+3.3, z, 0.25, 6.0, 0.25)
    caja(x-lado*0.9, 6.5, z, 1.8, 0.18, 0.18)
    material('lampara')
    caja(x-lado*1.7, 6.35, z, 0.7, 0.3, 0.7)


def hidrante(x, z):
    material('hidrante')
    cilindro(x, Y0, z, 0.28, 0.9)
    cilindro(x, Y0+0.9, z, 0.34, 0.2)
    caja(x, Y0+0.6, z, 0.9, 0.16, 0.16)


def cubo_basura(x, z, lado):
    material('metal_oscuro')
    caja(x, Y0+0.6, z, 0.9, 1.2, 0.9)
    material('metal')
    caja(x, Y0+1.28, z, 1.0, 0.16, 1.0)
    poster(x-lado*0.45, Y0+0.7, z, 0.7, 0.7, 'garra_cubo', lado)


def cajas(x, z):
    material('caja')
    caja(x, Y0+0.5, z, 1.0, 1.0, 1.0, ry=random.uniform(-0.3, 0.3))
    caja(x, Y0+0.5, z+1.1, 0.9, 0.9, 0.9, ry=random.uniform(-0.3, 0.3))
    caja(x, Y0+1.45, z+0.5, 0.9, 0.9, 0.9, ry=random.uniform(-0.3, 0.3))


def banco(x, z):
    material('banco_madera')
    caja(x, Y0+0.5, z, 0.5, 0.12, 2.0)
    caja(x+0.2, Y0+0.95, z, 0.1, 0.6, 2.0)
    material('metal_oscuro')
    for dz in (-0.8, 0.8):
        caja(x, Y0+0.25, z+dz, 0.5, 0.5, 0.1)


def barrera(x, z):
    material('barrera')
    caja(x, Y0+0.9, z, 0.15, 0.5, 2.6)
    material('metal_oscuro')
    for dz in (-1.1, 1.1):
        caja(x, Y0+0.45, z+dz, 0.15, 0.9, 0.15)


def conos(x, z):
    material('conos')
    for dz in (-0.9, 0.0, 0.9):
        piramide(x, z+dz, 0.5, 0.5, Y0, 0.8, over=0.0)


def buzon(x, z):
    material('buzon')
    caja(x, Y0+0.6, z, 0.8, 1.2, 0.8)
    material('metal_oscuro')
    caja(x, Y0+1.25, z, 0.9, 0.12, 0.9)


def props_gap(lado, z, idx):
    x1 = lado*(ANCHO_CALLE+1.0)
    x2 = lado*(ANCHO_CALLE+2.2)
    if idx % 2 == 0:
        farola(x1, z, lado)
        random.choice((lambda: hidrante(x1, z-2.2), lambda: buzon(x1, z-2.2),
                       lambda: conos(x1, z-2.6)))()
    else:
        random.choice((lambda: cubo_basura(x1, z, lado), lambda: banco(x2, z),
                       lambda: barrera(x1, z), lambda: cajas(x2, z)))()
        cubo_basura(x1, z+3.0, lado) if random.random() < 0.5 else None


# ---------------- construcción de la ciudad ----------------
zc = -L/2
objeto('calzada')
material('asfalto')
caja(0, -0.1, zc, ANCHO_CALLE*2, 0.2, L+20)
objeto('lineas_calle')
material('linea')
z = 0.0
while z > -L - 6:
    caja(0, 0.02, z, 0.3, 0.04, 3.0)
    z -= 6.0
objeto('pasos_cebra')
material('cebra')
for i in range(1, N_POR_LADO, 4):
    zz = -(8 + i*PASO) - PASO/2
    for k in range(-4, 5):
        caja(k*1.3, 0.025, zz, 0.7, 0.05, 3.0)
objeto('banquetas')
material('acera')
for lado in (-1, 1):
    caja(lado*(ANCHO_CALLE+ANCHO_ACERA/2), 0.1, zc, ANCHO_ACERA, 0.4, L+20)
material('bordillo')
for lado in (-1, 1):
    caja(lado*(ANCHO_CALLE+0.1), 0.31, zc, 0.2, 0.04, L+20)
objeto('suelo')
material('suelo')
caja(0, -0.35, zc, 160, 0.5, L+80)

base_tipos = ['vet', 'fries', 'pelu', 'casa', 'mercado', 'casa']
for lado in (-1, 1):
    rot = random.randint(0, len(base_tipos)-1)
    for i in range(N_POR_LADO):
        edificio(base_tipos[(i+rot) % len(base_tipos)], lado, -(8 + i*PASO), i)

objeto('mobiliario')
for lado in (-1, 1):
    for i in range(N_POR_LADO):
        props_gap(lado, -(8 + i*PASO) - PASO/2, i + (0 if lado < 0 else 1))

# portal final: la gran perrera "DOG CITY"
objeto('portal_perrera')
zE = -L - 6
material('portal')
caja(-8, 5, zE, 3, 10, 3)
caja(8, 5, zE, 3, 10, 3)
caja(0, 10.5, zE, 19, 3, 3)
material('techo_marron')
dos_aguas(0, zE, 20, 3.5, 12, 3.5, over=1.0)
cartel_z(0, 10.5, zE+1.5, 12, 3, 'cartel_dogcity')
cartel_z(0, 19.0, zE+0.5, 8, 8, 'cartel_bulldog')

# =====================================================================
# EXPORTAR .GLB  (colores, texturas, neón y colisiones para Godot)
# =====================================================================
# Colisionadores simples: (nombre, cx, cy, cz, ancho_x, alto_y, largo_z)
# El sufijo "-convcolonly" hace que Godot cree un StaticBody3D con colisión
# convexa y NO muestre la malla. Si el jugador debe poder caminar por las
# banquetas, cambia el ancho del piso a 18 y mueve las paredes a x = +-9.5.
Z_INI, Z_FIN = 10.0, -L - 14.0
Z_CEN, Z_LARGO = (Z_INI + Z_FIN) / 2, Z_INI - Z_FIN
COLISIONADORES = [
    ("suelo-convcolonly",        0.0,                -0.5, Z_CEN,      ANCHO_CALLE*2, 1.0, Z_LARGO),
    ("pared_izq-convcolonly",   -(ANCHO_CALLE+0.5),  10.0, Z_CEN,      1.0, 20.0, Z_LARGO),
    ("pared_der-convcolonly",    (ANCHO_CALLE+0.5),  10.0, Z_CEN,      1.0, 20.0, Z_LARGO),
    ("pared_inicio-convcolonly", 0.0,                10.0, Z_INI+0.5,  ANCHO_CALLE*2+2, 20.0, 1.0),
    ("pared_fin-convcolonly",    0.0,                10.0, Z_FIN-0.5,  ANCHO_CALLE*2+2, 20.0, 1.0),
]


def malla_caja(cx, cy, cz, w, h, d):
    pts = [(cx+sx*w/2, cy+sy*h/2, cz+sz*d/2)
           for sy in (-1, 1) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    ref = (cx, cy, cz)
    quads = [[0, 1, 2, 3], [4, 5, 6, 7]] + [[i, (i+1) % 4, (i+1) % 4+4, i+4] for i in range(4)]
    idx = []
    for q in quads:
        a, b, c = pts[q[0]], pts[q[1]], pts[q[2]]
        n = cross(sub(b, a), sub(c, a))
        cen = tuple(sum(pts[i][k] for i in q)/4 for k in range(3))
        if dot(n, sub(cen, ref)) < 0:
            q = q[::-1]
        idx += [q[0], q[1], q[2], q[0], q[2], q[3]]
    return pts, idx


def escribir_glb(ruta):
    blob = bytearray()
    views, accs = [], []

    def alinear():
        while len(blob) % 4:
            blob.append(0)

    def accesor(datos, comp, n, tipo, target, mn=None, mx=None):
        alinear()
        views.append({"buffer": 0, "byteOffset": len(blob),
                      "byteLength": len(datos), "target": target})
        blob.extend(datos)
        a = {"bufferView": len(views)-1, "componentType": comp, "count": n, "type": tipo}
        if mn is not None:
            a["min"], a["max"] = mn, mx
        accs.append(a)
        return len(accs)-1

    def primitiva(pos, nor, uvs, idx, mat_i=None):
        flat = [c for p in pos for c in p]
        mn = [min(p[k] for p in pos) for k in range(3)]
        mx = [max(p[k] for p in pos) for k in range(3)]
        attrs = {"POSITION": accesor(struct.pack(f"<{len(flat)}f", *flat),
                                     5126, len(pos), "VEC3", 34962, mn, mx)}
        if nor:
            fn = [c for n in nor for c in n]
            attrs["NORMAL"] = accesor(struct.pack(f"<{len(fn)}f", *fn),
                                      5126, len(nor), "VEC3", 34962)
        if uvs:
            fu = [c for u, v in uvs for c in (u, 1.0-v)]   # glTF: v hacia abajo
            attrs["TEXCOORD_0"] = accesor(struct.pack(f"<{len(fu)}f", *fu),
                                          5126, len(uvs), "VEC2", 34962)
        prim = {"attributes": attrs,
                "indices": accesor(struct.pack(f"<{len(idx)}I", *idx),
                                   5125, len(idx), "SCALAR", 34963)}
        if mat_i is not None:
            prim["material"] = mat_i
        return prim

    usados = [m for m in MATS if any(c[0] == m for c in caras)]
    faltan = {c[0] for c in caras} - set(MATS)
    if faltan:
        raise KeyError(f"Materiales sin definir: {faltan}")

    # --- imágenes y texturas incrustadas ---
    imagenes, texturas, tex_idx = [], [], {}
    for m in usados:
        archivo = TEXTURA.get(m)
        if archivo and archivo not in tex_idx:
            with open(os.path.join(AQUI, "texturas", archivo), "rb") as f:
                datos = f.read()
            alinear()
            views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(datos)})
            blob.extend(datos)
            imagenes.append({"name": archivo, "bufferView": len(views)-1, "mimeType": "image/png"})
            texturas.append({"sampler": 0, "source": len(imagenes)-1})
            tex_idx[archivo] = len(texturas)-1

    # --- malla visual: una primitiva por material ---
    prims = []
    for mi, nombre in enumerate(usados):
        pos, nor, uvs, idx = [], [], [], []
        for m, pts, n, uv in caras:
            if m != nombre:
                continue
            b = len(pos)
            pos += pts
            nor += [n]*len(pts)
            uvs += uv
            for i in range(1, len(pts)-1):
                idx += [b, b+i, b+i+1]
        prims.append(primitiva(pos, nor, uvs, idx, mi))
    materiales = []
    for m in usados:
        pbr = {"baseColorFactor": [*MATS[m], 1.0], "metallicFactor": 0.0, "roughnessFactor": 1.0}
        if m in TEXTURA:
            pbr["baseColorTexture"] = {"index": tex_idx[TEXTURA[m]]}
        mat = {"name": m, "pbrMetallicRoughness": pbr}
        if m in EMISION:
            mat["emissiveFactor"] = list(EMISION[m])
        materiales.append(mat)
    meshes = [{"name": "Mapa", "primitives": prims}]
    nodes = [{"name": "Mapa", "mesh": 0}]

    # --- colisionadores ---
    for nombre, *dim in COLISIONADORES:
        pos, idx = malla_caja(*dim)
        meshes.append({"name": nombre, "primitives": [primitiva(pos, None, None, idx)]})
        nodes.append({"name": nombre, "mesh": len(meshes)-1})

    gltf = {"asset": {"version": "2.0", "generator": "generar_mapa.py"},
            "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
            "nodes": nodes, "meshes": meshes, "materials": materiales,
            "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
            "images": imagenes, "textures": texturas,
            "accessors": accs, "bufferViews": views,
            "buffers": [{"byteLength": len(blob)}]}
    j = json.dumps(gltf).encode()
    j += b" " * (-len(j) % 4)
    alinear()
    total = 12 + 8 + len(j) + 8 + len(blob)
    with open(ruta, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))


def escribir_obj():
    with open(os.path.join(AQUI, "papa_calle.obj"), "w") as f:
        f.write("# Mapa Papa Caliente\nmtllib papa_calle.mtl\n")
        for v in verts:
            f.write("v %.4f %.4f %.4f\n" % v)
        for u, v in vt_lista:
            f.write("vt %.4f %.4f\n" % (u, v))
        for n in norms:
            f.write("vn %.4f %.4f %.4f\n" % n)
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(AQUI, "papa_calle.mtl"), "w") as f:
        for nombre, (r, g, b) in MATS.items():
            f.write(f"newmtl {nombre}\nKd {r} {g} {b}\nKa 0 0 0\nKs 0 0 0\nd 1\nillum 1\n")
            if nombre in EMISION:
                f.write("Ke %s %s %s\n" % EMISION[nombre])
            if nombre in TEXTURA:
                f.write(f"map_Kd texturas/{TEXTURA[nombre]}\n")
            f.write("\n")


if __name__ == "__main__":
    escribir_glb(os.path.join(AQUI, "papa_calle.glb"))
    escribir_obj()
    print(f"Listo: {len(caras)} caras, calle de {L:.0f} m -> papa_calle.glb / .obj / .mtl")
