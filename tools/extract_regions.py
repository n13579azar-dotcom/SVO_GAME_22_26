#!/usr/bin/env python3
"""Извлечение контуров областей из растровой схемы (reference/ukraine_oblasts.jpg).

Схема предоставлена автором проекта как основа геометрии. Скрипт:
  1) находит замкнутые белые области между линиями границ;
  2) разбивает всю площадь страны между ними (ближайшая область) — границы смежных областей совпадают;
  3) привязывает пиксели к координатам по городам-ориентирам (аффинная подгонка) и сообщает невязку;
  4) пишет tools/regions_raw.json (контуры в долготе/широте), который читает gen_ukraine.py.
Точность ограничена самой схемой (она не геодезическая).
"""
import json, os, sys
import numpy as np, cv2
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "reference", "ukraine_oblasts.jpg")

# пиксели центров городов на схеме (оценка по меткам) -> (область, lon, lat)
CTRL = {
 "lutsk": ((228,152),"volyn",25.34,50.75), "rivne": ((284,165),"rivne",26.25,50.62),
 "lviv": ((143,231),"lviv",24.03,49.84), "uzhhorod": ((31,321),"zakarpattia",22.29,48.62),
 "ivano_frankivsk": ((179,313),"ivano_frankivsk",24.71,48.92), "ternopil": ((237,259),"ternopil",25.59,49.55),
 "chernivtsi": ((251,376),"chernivtsi",25.94,48.29), "khmelnytskyi": ((322,280),"khmelnytskyi",26.98,49.42),
 "vinnytsia": ((412,301),"vinnytsia",28.47,49.23), "zhytomyr": ((427,204),"zhytomyr",28.66,50.25),
 "kyiv": ((536,191),"kyiv",30.52,50.45), "chernihiv": ((580,99),"chernihiv",31.29,51.49),
 "sumy": ((787,146),"sumy",34.80,50.91), "kharkiv": ((868,231),"kharkiv",36.23,49.99),
 "poltava": ((781,270),"poltava",34.55,49.59), "luhansk": ((1076,347),"luhansk",39.30,48.57),
 "donetsk": ((979,411),"donetsk",37.80,48.02), "dnipro": ((817,369),"dnipropetrovsk",35.05,48.46),
 "zaporizhzhia": ((820,434),"zaporizhzhia",35.14,47.84), "cherkasy": ((618,288),"cherkasy",32.06,49.44),
 "kropyvnytskyi": ((640,374),"kirovohrad",32.26,48.51), "mykolaiv": ((622,515),"mykolaiv",31.99,46.97),
 "kherson": ((668,542),"kherson",32.62,46.64), "odesa": ((556,541),"odesa",30.72,46.48),
 "simferopol": ((762,705),"crimea",34.10,44.95),
}
EXTRA_SEEDS = [((190, 95), "volyn"), ((310, 100), "rivne"), ((480, 600), "odesa"), ((730, 432), "dnipropetrovsk"), ((845, 350), "dnipropetrovsk")]

im = cv2.imread(SRC)
g = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)
white = g >= 110
lab, n = ndi.label(white)
bg = lab[0, 0]
sizes = ndi.sum(white, lab, range(1, n + 1))
big = {i + 1 for i, s in enumerate(sizes) if s > 1500 and (i + 1) != bg}

seed_region = {}
def nearest_big(pt):
    x, y = pt
    ys, xs = np.nonzero(np.isin(lab, list(big)))
    k = np.argmin((xs - x) ** 2 + (ys - y) ** 2)
    return int(lab[ys[k], xs[k]])
for cid, (pt, reg, lon, lat) in CTRL.items():
    seed_region[nearest_big(pt)] = reg
for pt, reg in EXTRA_SEEDS:
    seed_region[nearest_big(pt)] = reg
unassigned = big - set(seed_region)
print("компонент:", len(big), "назначено:", len(seed_region), "не назначено:", unassigned)

# карта областей: пиксели компонент -> id области
regs = sorted(set(seed_region.values()))
ridx = {r: i + 1 for i, r in enumerate(regs)}
lab_reg = np.zeros(lab.shape, np.int32)
for comp, reg in seed_region.items():
    lab_reg[lab == comp] = ridx[reg]
# маска страны: объединение областей, склейка линий и водоёмов
land = lab_reg > 0
land = cv2.morphologyEx(land.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
land = ndi.binary_fill_holes(land).astype(np.uint8)
# внешний чёрный контур схемы — декоративный: срезаем его, сжимая маску на 2 пикселя
land = cv2.erode(land, np.ones((3, 3), np.uint8), iterations=1)
dist, (iy, ix) = ndi.distance_transform_edt(lab_reg == 0, return_indices=True)
full = lab_reg[iy, ix] * land  # каждому пикселю страны — ближайшая область

# аффинная привязка пикселей к (lon, lat)
def feats(px, py):
    px, py = px / 1134.0, py / 768.0
    return [px, py, 1.0, px * px, px * py, py * py]
A = np.array([feats(p[0], p[1]) for (p, _, _, _) in CTRL.values()], float)
LON0, LAT0 = 21.6, 52.6
COS = np.cos(np.radians(48.5))
X = np.array([[(lo - LON0) * COS, (LAT0 - la)] for (_, _, lo, la) in CTRL.values()], float)
coef, *_ = np.linalg.lstsq(A, X, rcond=None)
res = A @ coef - X
err_deg = np.sqrt((res[:, 0] / COS) ** 2 + res[:, 1] ** 2)
print("невязка привязки, градусов: средняя %.3f, максимум %.3f" % (err_deg.mean(), err_deg.max()))
worst = sorted(zip(err_deg, CTRL.keys()), reverse=True)[:4]
print("худшие:", [(round(float(e), 2), k) for e, k in worst])

def to_lonlat(px, py):
    xy = np.array(feats(px, py)) @ coef
    return [round(float(xy[0] / COS + LON0), 3), round(float(LAT0 - xy[1]), 3)]

out = {"regions": {}, "country": []}
def contours(mask, eps):
    cs, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    res = []
    for c in cs:
        if cv2.contourArea(c) < 60:
            continue
        a = cv2.approxPolyDP(c, eps, True)[:, 0, :]
        if len(a) >= 3:
            res.append([to_lonlat(x, y) for x, y in a])
    return sorted(res, key=lambda p: -len(p))
for r in regs:
    out["regions"][r] = contours(full == ridx[r], 1.3)
out["country"] = contours(full > 0, 1.3)
out["fit_error_deg"] = {"mean": round(float(err_deg.mean()), 3), "max": round(float(err_deg.max()), 3)}
json.dump(out, open(os.path.join(HERE, "regions_raw.json"), "w"), separators=(",", ":"))
print("регионов:", len(regs), " вершин в контуре страны:", sum(len(p) for p in out["country"]))
cv2.imwrite("/home/claude/full.png", (full * 9 % 255).astype(np.uint8))
