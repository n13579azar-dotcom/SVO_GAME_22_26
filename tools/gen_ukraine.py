#!/usr/bin/env python3
"""Генератор данных глобальной карты Украины (этап 2, уточнение).

Запуск (из корня проекта):  python3 tools/gen_ukraine.py [--preview preview.png]

Что делает:
  * берёт ориентирные точки (широта/долгота) контура страны, рек, городов;
  * подбирает положения «центров» областей так, чтобы каждый город попал в свою область
    (диаграмма мощности), и режет контур страны на области;
  * проецирует всё в плоские координаты карты и пишет
      data/global_map/ukraine.json   (контур, реки, коридоры, рельеф, города)
      data/global_map/territories.json (области как территории игры)

ВАЖНО: контур и границы областей СХЕМАТИЧНЫЕ (приближение по ориентирным точкам), это не
геодезические данные. Точные границы под конкретную дату подключаются на этапе 7.
Скрипт нужен только разработчику; в APK не попадает.
"""
import json, math, os, random, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LON0, LAT0, K = 21.6, 52.6, 80.0
COS = math.cos(math.radians(48.5))


def proj(lon, lat):
    return ((lon - LON0) * COS * K, (LAT0 - lat) * K)


# ---------- контур страны (lon, lat), по часовой стрелке от северо-запада ----------
BORDER = [
    (23.60, 51.52), (24.10, 51.62), (24.30, 51.85), (25.00, 51.93), (26.00, 51.90), (27.00, 51.77),
    (27.80, 51.62), (28.60, 51.45), (29.40, 51.40), (30.20, 51.48), (30.60, 51.36), (31.10, 51.75),
    (31.70, 52.10), (32.40, 52.30), (33.10, 52.36), (33.80, 52.36), (34.40, 52.20), (35.00, 51.95),
    (35.40, 51.55), (35.25, 51.15), (35.60, 50.75), (36.10, 50.45), (36.65, 50.20), (37.40, 50.40),
    (38.00, 49.95), (38.10, 49.60), (39.15, 49.75), (40.15, 49.60), (39.85, 49.10), (40.10, 48.85),
    (39.75, 48.30), (39.85, 48.05), (39.30, 47.85), (38.85, 47.85), (38.25, 47.50), (38.20, 47.10),
    # Азовское побережье
    (37.55, 47.07), (36.80, 46.72), (36.00, 46.55), (35.30, 46.40), (34.85, 46.18),
    (35.05, 45.78), (35.40, 45.40), (35.90, 45.35), (36.45, 45.38), (36.60, 45.25),
    # Крымское побережье
    (36.45, 45.05), (35.80, 44.98), (35.40, 44.95), (35.00, 44.80), (34.50, 44.65), (34.15, 44.40),
    (33.75, 44.40), (33.50, 44.55), (33.40, 44.65), (32.75, 45.05), (32.50, 45.35), (33.20, 45.40),
    (33.60, 45.80), (33.65, 46.10),
    # Каркинитский залив и побережье Херсонщины
    (33.30, 46.12), (32.60, 46.10), (32.00, 46.20), (31.50, 46.55), (31.45, 46.60), (31.75, 46.65),
    (31.40, 46.62), (30.80, 46.48), (30.45, 46.40), (30.25, 46.05), (30.00, 45.80), (29.65, 45.50),
    (29.60, 45.25), (29.20, 45.38), (28.85, 45.30), (28.25, 45.45),
    # граница с Молдовой и Румынией
    (28.55, 46.05), (28.90, 46.45), (29.60, 46.35), (29.95, 46.55), (29.75, 46.95), (30.10, 47.35),
    (29.95, 47.95), (29.30, 48.05), (28.60, 48.15), (27.80, 48.45), (27.00, 48.50), (26.60, 48.28),
    (26.00, 48.25), (25.25, 47.95), (24.50, 47.95), (23.85, 47.95), (23.15, 48.25), (22.85, 48.40),
    (22.15, 48.40), (22.55, 49.08), (22.70, 49.50), (22.90, 49.80), (23.30, 50.10), (23.60, 50.40),
    (24.10, 50.85), (23.65, 51.20),
]

# мор.контур для «суши соседей»: внешняя часть (против часовой от Азова к Дунаю)
NEIGHBOR_OUTER = [
    (38.20, 47.10), (38.90, 47.25), (39.40, 47.10), (39.00, 46.80), (38.30, 46.60), (38.20, 46.10),
    (37.50, 45.45), (37.00, 45.25), (37.30, 44.85), (37.80, 44.70), (39.05, 44.10), (39.75, 43.55),
    (42.0, 43.0), (46.0, 43.0), (46.0, 54.0), (19.0, 54.0), (19.0, 43.0), (26.5, 43.0),
    (28.6, 43.8), (29.70, 44.60), (29.60, 45.25),
]

# ---------- области: id, ru, uk, центр-ориентир (lon, lat), админцентр (id города) ----------
REGIONS = [
    ("volyn", "Волынская область", "Волинська область", (25.1, 51.1), "lutsk"),
    ("rivne", "Ровенская область", "Рівненська область", (26.5, 51.0), "rivne"),
    ("zhytomyr", "Житомирская область", "Житомирська область", (28.5, 50.7), "zhytomyr"),
    ("kyiv", "Киевская область", "Київська область", (30.2, 50.2), "kyiv"),
    ("chernihiv", "Черниговская область", "Чернігівська область", (32.0, 51.5), "chernihiv"),
    ("sumy", "Сумская область", "Сумська область", (34.2, 50.9), "sumy"),
    ("kharkiv", "Харьковская область", "Харківська область", (36.7, 49.6), "kharkiv"),
    ("luhansk", "Луганская область", "Луганська область", (39.2, 48.9), "luhansk"),
    ("donetsk", "Донецкая область", "Донецька область", (37.7, 48.1), "donetsk"),
    ("zaporizhzhia", "Запорожская область", "Запорізька область", (35.5, 47.2), "zaporizhzhia"),
    ("kherson", "Херсонская область", "Херсонська область", (33.3, 46.5), "kherson"),
    ("crimea", "Автономная Республика Крым", "Автономна Республіка Крим", (34.2, 45.2), "simferopol"),
    ("mykolaiv", "Николаевская область", "Миколаївська область", (31.8, 47.3), "mykolaiv"),
    ("odesa", "Одесская область", "Одеська область", (30.0, 46.7), "odesa"),
    ("vinnytsia", "Винницкая область", "Вінницька область", (28.5, 49.0), "vinnytsia"),
    ("khmelnytskyi", "Хмельницкая область", "Хмельницька область", (26.8, 49.5), "khmelnytskyi"),
    ("ternopil", "Тернопольская область", "Тернопільська область", (25.4, 49.4), "ternopil"),
    ("lviv", "Львовская область", "Львівська область", (24.0, 49.7), "lviv"),
    ("ivano_frankivsk", "Ивано-Франковская область", "Івано-Франківська область", (24.6, 48.8), "ivano_frankivsk"),
    ("zakarpattia", "Закарпатская область", "Закарпатська область", (23.1, 48.4), "uzhhorod"),
    ("chernivtsi", "Черновицкая область", "Чернівецька область", (25.7, 48.3), "chernivtsi"),
    ("cherkasy", "Черкасская область", "Черкаська область", (31.5, 49.1), "cherkasy"),
    ("kirovohrad", "Кировоградская область", "Кіровоградська область", (32.3, 48.6), "kropyvnytskyi"),
    ("poltava", "Полтавская область", "Полтавська область", (33.9, 49.6), "poltava"),
    ("dnipropetrovsk", "Днепропетровская область", "Дніпропетровська область", (35.0, 48.5), "dnipro"),
]

SHORT = {"crimea": "Крым", "ivano_frankivsk": "Ивано-Франк.", "dnipropetrovsk": "Днепропетр."}

# ориентировочные площади областей, тыс. км² (округлённо) — для подбора пропорций схемы
AREA_KM2 = {
    "volyn": 20.1, "rivne": 20.1, "zhytomyr": 29.8, "kyiv": 28.1, "chernihiv": 31.9, "sumy": 23.8,
    "kharkiv": 31.4, "luhansk": 26.7, "donetsk": 26.5, "zaporizhzhia": 27.2, "kherson": 28.5,
    "crimea": 27.0, "mykolaiv": 24.6, "odesa": 33.3, "vinnytsia": 26.5, "khmelnytskyi": 20.6,
    "ternopil": 13.8, "lviv": 21.8, "ivano_frankivsk": 13.9, "zakarpattia": 12.8, "chernivtsi": 8.1,
    "cherkasy": 20.9, "kirovohrad": 24.6, "poltava": 28.8, "dnipropetrovsk": 31.9,
}

# ---------- города: id, ru, uk, lon, lat, уровень (1 столица … 4), область ----------
C = []
def city(i, ru, uk, lon, lat, tier, reg): C.append((i, ru, uk, lon, lat, tier, reg))

city("kyiv", "Киев", "Київ", 30.52, 50.45, 1, "kyiv")
for a in [
    ("kharkiv", "Харьков", "Харків", 36.23, 49.99, "kharkiv"),
    ("odesa", "Одесса", "Одеса", 30.72, 46.48, "odesa"),
    ("dnipro", "Днепр", "Дніпро", 35.05, 48.46, "dnipropetrovsk"),
    ("donetsk", "Донецк", "Донецьк", 37.80, 48.02, "donetsk"),
    ("zaporizhzhia", "Запорожье", "Запоріжжя", 35.14, 47.84, "zaporizhzhia"),
    ("lviv", "Львов", "Львів", 24.03, 49.84, "lviv"),
    ("kryvyi_rih", "Кривой Рог", "Кривий Ріг", 33.39, 47.91, "dnipropetrovsk"),
    ("mykolaiv", "Николаев", "Миколаїв", 31.99, 46.97, "mykolaiv"),
    ("mariupol", "Мариуполь", "Маріуполь", 37.55, 47.10, "donetsk"),
    ("luhansk", "Луганск", "Луганськ", 39.30, 48.57, "luhansk"),
    ("sevastopol", "Севастополь", "Севастополь", 33.52, 44.62, "crimea"),
    ("simferopol", "Симферополь", "Сімферополь", 34.10, 44.95, "crimea"),
    ("vinnytsia", "Винница", "Вінниця", 28.47, 49.23, "vinnytsia"),
    ("kherson", "Херсон", "Херсон", 32.62, 46.64, "kherson"),
    ("poltava", "Полтава", "Полтава", 34.55, 49.59, "poltava"),
    ("chernihiv", "Чернигов", "Чернігів", 31.29, 51.49, "chernihiv"),
    ("cherkasy", "Черкассы", "Черкаси", 32.06, 49.44, "cherkasy"),
    ("sumy", "Сумы", "Суми", 34.80, 50.91, "sumy"),
    ("zhytomyr", "Житомир", "Житомир", 28.66, 50.25, "zhytomyr"),
    ("khmelnytskyi", "Хмельницкий", "Хмельницький", 26.98, 49.42, "khmelnytskyi"),
    ("rivne", "Ровно", "Рівне", 26.25, 50.62, "rivne"),
    ("chernivtsi", "Черновцы", "Чернівці", 25.94, 48.29, "chernivtsi"),
    ("ivano_frankivsk", "Ивано-Франковск", "Івано-Франківськ", 24.71, 48.92, "ivano_frankivsk"),
    ("ternopil", "Тернополь", "Тернопіль", 25.59, 49.55, "ternopil"),
    ("lutsk", "Луцк", "Луцьк", 25.34, 50.75, "volyn"),
    ("uzhhorod", "Ужгород", "Ужгород", 22.29, 48.62, "zakarpattia"),
    ("kropyvnytskyi", "Кропивницкий", "Кропивницький", 32.26, 48.51, "kirovohrad"),
]:
    city(*a[:5], 2, a[5])
for a in [
    ("melitopol", "Мелитополь", "Мелітополь", 35.37, 46.84, "zaporizhzhia"),
    ("berdiansk", "Бердянск", "Бердянськ", 36.79, 46.76, "zaporizhzhia"),
    ("energodar", "Энергодар", "Енергодар", 34.65, 47.50, "zaporizhzhia"),
    ("bakhmut", "Бахмут", "Бахмут", 38.00, 48.60, "donetsk"),
    ("kramatorsk", "Краматорск", "Краматорськ", 37.56, 48.72, "donetsk"),
    ("sloviansk", "Славянск", "Слов'янськ", 37.62, 48.87, "donetsk"),
    ("pokrovsk", "Покровск", "Покровськ", 37.18, 48.28, "donetsk"),
    ("horlivka", "Горловка", "Горлівка", 38.05, 48.30, "donetsk"),
    ("makiivka", "Макеевка", "Макіївка", 37.96, 48.05, "donetsk"),
    ("volnovakha", "Волноваха", "Волноваха", 37.50, 47.60, "donetsk"),
    ("sieverodonetsk", "Северодонецк", "Сєвєродонецьк", 38.49, 48.95, "luhansk"),
    ("lysychansk", "Лисичанск", "Лисичанськ", 38.43, 48.90, "luhansk"),
    ("alchevsk", "Алчевск", "Алчевськ", 38.80, 48.47, "luhansk"),
    ("kremenchuk", "Кременчуг", "Кременчук", 33.42, 49.07, "poltava"),
    ("bila_tserkva", "Белая Церковь", "Біла Церква", 30.10, 49.80, "kyiv"),
    ("uman", "Умань", "Умань", 30.22, 48.75, "cherkasy"),
    ("nikopol", "Никополь", "Нікополь", 34.39, 47.57, "dnipropetrovsk"),
    ("pavlohrad", "Павлоград", "Павлоград", 35.87, 48.53, "dnipropetrovsk"),
    ("kamianske", "Каменское", "Кам'янське", 34.61, 48.51, "dnipropetrovsk"),
    ("kerch", "Керчь", "Керч", 36.47, 45.36, "crimea"),
    ("feodosia", "Феодосия", "Феодосія", 35.38, 45.03, "crimea"),
    ("yalta", "Ялта", "Ялта", 34.16, 44.50, "crimea"),
    ("dzhankoi", "Джанкой", "Джанкой", 34.40, 45.71, "crimea"),
    ("izium", "Изюм", "Ізюм", 37.28, 49.21, "kharkiv"),
    ("kupiansk", "Купянск", "Куп'янськ", 37.62, 49.71, "kharkiv"),
    ("lozova", "Лозовая", "Лозова", 36.32, 48.89, "kharkiv"),
    ("konotop", "Конотоп", "Конотоп", 33.21, 51.24, "sumy"),
    ("shostka", "Шостка", "Шостка", 33.47, 51.87, "sumy"),
    ("mukachevo", "Мукачево", "Мукачеве", 22.72, 48.44, "zakarpattia"),
    ("drohobych", "Дрогобыч", "Дрогобич", 23.51, 49.35, "lviv"),
    ("kamianets", "Каменец-Подольский", "Кам'янець-Подільський", 26.58, 48.68, "khmelnytskyi"),
    ("kovel", "Ковель", "Ковель", 24.71, 51.22, "volyn"),
    ("izmail", "Измаил", "Ізмаїл", 28.84, 45.35, "odesa"),
    ("bilhorod_dnistrovskyi", "Белгород-Днестровский", "Білгород-Дністровський", 30.34, 46.19, "odesa"),
    ("podilsk", "Подольск", "Подільськ", 29.55, 47.75, "odesa"),
    ("pervomaisk", "Первомайск", "Первомайськ", 30.85, 48.04, "mykolaiv"),
    ("henichesk", "Геническ", "Генічеськ", 34.81, 46.17, "kherson"),
    ("kakhovka", "Каховка", "Каховка", 33.48, 46.81, "kherson"),
]:
    city(*a[:5], 3, a[5])
CITIES = C

RIVERS = [
    ("dnipro", "Днепр", "Дніпро", [(30.60, 51.42), (30.55, 50.95), (30.52, 50.45), (31.45, 49.75), (32.05, 49.43),
        (33.40, 49.07), (34.20, 48.70), (35.05, 48.46), (35.15, 47.85), (34.40, 47.60), (33.37, 46.75), (32.62, 46.63), (32.30, 46.50)], 3.0),
    ("dniester", "Днестр", "Дністер", [(23.00, 49.00), (24.00, 49.15), (24.70, 49.10), (25.70, 48.65), (26.50, 48.50),
        (27.80, 48.45), (28.30, 48.23), (29.00, 47.80), (29.15, 47.27), (29.60, 46.85), (30.30, 46.20)], 2.2),
    ("southern_bug", "Южный Буг", "Південний Буг", [(27.10, 49.60), (27.00, 49.42), (28.47, 49.23), (29.85, 48.35),
        (30.85, 48.05), (31.30, 47.55), (31.99, 46.97), (31.90, 46.75)], 2.0),
    ("siverskyi_donets", "Северский Донец", "Сіверський Донець", [(36.65, 50.20), (36.70, 49.84), (37.28, 49.21),
        (37.80, 49.00), (38.43, 48.90), (39.70, 48.65), (40.00, 48.55)], 1.8),
    ("desna", "Десна", "Десна", [(33.50, 52.30), (33.25, 52.00), (32.40, 51.75), (31.30, 51.45), (30.80, 50.90), (30.60, 50.55)], 1.8),
    ("danube", "Дунай", "Дунай", [(28.25, 45.45), (28.85, 45.33), (29.20, 45.40), (29.62, 45.25)], 2.0),
]

# «Коридоры» — схематичные связи крупных городов (основа будущей логистики), не точные трассы
ROADS = [
    ("kyiv_lviv", "Киев — Львов", ["kyiv", "zhytomyr", "rivne", "lviv"]),
    ("kyiv_kharkiv", "Киев — Харьков", ["kyiv", "poltava", "kharkiv"]),
    ("kyiv_odesa", "Киев — Одесса", ["kyiv", "uman", "podilsk", "odesa"]),
    ("kyiv_chernihiv", "Киев — Чернигов", ["kyiv", "chernihiv"]),
    ("kyiv_sumy", "Киев — Сумы", ["kyiv", "konotop", "sumy"]),
    ("kharkiv_dnipro", "Харьков — Днепр — Запорожье", ["kharkiv", "dnipro", "zaporizhzhia"]),
    ("dnipro_donetsk", "Днепр — Донецк", ["dnipro", "pavlohrad", "donetsk"]),
    ("kharkiv_luhansk", "Харьков — Луганск", ["kharkiv", "izium", "sieverodonetsk", "luhansk"]),
    ("zaporizhzhia_crimea", "Запорожье — Крым", ["zaporizhzhia", "melitopol", "dzhankoi", "simferopol"]),
    ("mykolaiv_odesa", "Николаев — Херсон — Одесса", ["kherson", "mykolaiv", "odesa"]),
    ("lviv_uzhhorod", "Львов — Ужгород", ["lviv", "drohobych", "mukachevo", "uzhhorod"]),
    ("lviv_chernivtsi", "Львов — Черновцы", ["lviv", "ternopil", "kamianets", "chernivtsi"]),
    ("kyiv_dnipro", "Киев — Днепр", ["kyiv", "cherkasy", "kremenchuk", "dnipro"]),
    ("donetsk_mariupol", "Донецк — Мариуполь", ["donetsk", "volnovakha", "mariupol"]),
    ("simferopol_kerch", "Симферополь — Керчь", ["simferopol", "feodosia", "kerch"]),
    ("simferopol_sevastopol", "Симферополь — Севастополь", ["simferopol", "sevastopol"]),
]

AREAS = [
    ("carpathians", "mountains", "Карпаты", "Карпати",
     [(22.45, 48.6), (23.3, 49.1), (24.3, 49.3), (25.2, 48.8), (25.6, 48.2), (24.8, 47.97), (23.8, 47.97), (22.9, 48.2)]),
    ("crimean_mountains", "mountains", "Крымские горы", "Кримські гори",
     [(33.55, 44.62), (34.3, 44.85), (35.2, 44.95), (35.0, 44.7), (34.2, 44.5), (33.65, 44.45)]),
    ("polissia", "forest", "Полесье", "Полісся",
     [(24.0, 51.5), (27.0, 51.75), (30.4, 51.3), (32.3, 52.2), (34.0, 51.9), (33.4, 51.2), (31.5, 50.95),
      (29.5, 50.75), (27.5, 50.8), (25.5, 50.9)]),
]

LABELS = [
    ("Чёрное море", "Чорне море", 32.0, 44.0, "sea"), ("Азовское море", "Азовське море", 36.6, 46.2, "sea"),
    ("Беларусь", "Білорусь", 28.0, 52.9, "country"), ("Россия", "Росія", 41.5, 50.5, "country"),
    ("Польша", "Польща", 21.5, 50.6, "country"), ("Словакия", "Словаччина", 21.4, 48.9, "country"),
    ("Венгрия", "Угорщина", 21.4, 47.9, "country"), ("Румыния", "Румунія", 25.0, 46.4, "country"),
    ("Молдова", "Молдова", 28.5, 47.0, "country"),
]


# ---------- геометрия ----------
def poly_area(p):
    return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))


def centroid(p):
    a = poly_area(p)
    if abs(a) < 1e-9:
        return (sum(x for x, _ in p) / len(p), sum(y for _, y in p) / len(p))
    cx = cy = 0.0
    for i in range(len(p)):
        x0, y0 = p[i]; x1, y1 = p[(i + 1) % len(p)]
        f = x0 * y1 - x1 * y0
        cx += (x0 + x1) * f; cy += (y0 + y1) * f
    return (cx / (6 * a), cy / (6 * a))


def point_in(pt, poly):
    x, y = pt; inside = False
    n = len(poly)
    for i in range(n):
        x0, y0 = poly[i]; x1, y1 = poly[(i + 1) % n]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            inside = not inside
    return inside


def clip_halfplane(poly, a, b, c):
    """Оставляет часть полигона, где a*x + b*y <= c (Сазерленд–Ходжман)."""
    out = []
    n = len(poly)
    for i in range(n):
        p, q = poly[i], poly[(i + 1) % n]
        fp = a * p[0] + b * p[1] - c
        fq = a * q[0] + b * q[1] - c
        if fp <= 0:
            out.append(p)
        if (fp < 0 < fq) or (fq < 0 < fp):
            t = fp / (fp - fq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


def dedupe(poly, eps=0.05):
    out = []
    for p in poly:
        if not out or abs(p[0] - out[-1][0]) > eps or abs(p[1] - out[-1][1]) > eps:
            out.append(p)
    if len(out) > 1 and abs(out[0][0] - out[-1][0]) <= eps and abs(out[0][1] - out[-1][1]) <= eps:
        out.pop()
    return out


def _ccw(a, b, c):
    return (c[1] - a[1]) * (b[0] - a[0]) - (b[1] - a[1]) * (c[0] - a[0])


def segs_cross(a, b, c, d):
    d1, d2, d3, d4 = _ccw(c, d, a), _ccw(c, d, b), _ccw(a, b, c), _ccw(a, b, d)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def is_simple(poly):
    n = len(poly)
    for i in range(n):
        for j in range(i + 1, n):
            if abs(i - j) <= 1 or (i == 0 and j == n - 1):
                continue
            if segs_cross(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n]):
                return False
    return True


def assign(pt, seeds, w):
    best, bi = 1e18, -1
    for i, (sx, sy) in enumerate(seeds):
        d = (pt[0] - sx) ** 2 + (pt[1] - sy) ** 2 - w[i]
        if d < best:
            best, bi = d, i
    return bi


def pole_of_inaccessibility(poly):
    xs = [p[0] for p in poly]; ys = [p[1] for p in poly]
    best, bp = -1.0, centroid(poly)
    n = len(poly)
    gx = [min(xs) + (max(xs) - min(xs)) * i / 40.0 for i in range(41)]
    gy = [min(ys) + (max(ys) - min(ys)) * i / 40.0 for i in range(41)]
    for x in gx:
        for y in gy:
            if not point_in((x, y), poly):
                continue
            d = 1e18
            for i in range(n):
                x0, y0 = poly[i]; x1, y1 = poly[(i + 1) % n]
                dx, dy = x1 - x0, y1 - y0
                t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)))
                d = min(d, (x - x0 - t * dx) ** 2 + (y - y0 - t * dy) ** 2)
            if d > best:
                best, bp = d, (x, y)
    return bp


def main():
    import places_data
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
    raw = json.load(open(os.path.join(ROOT, "tools/regions_raw.json")))
    ids = [r[0] for r in REGIONS]
    r1 = lambda p: [round(p[0], 1), round(p[1], 1)]

    cells = {}   # id -> список полигонов (самый большой первым)
    for rid in ids:
        polys = [dedupe([proj(*pt) for pt in poly]) for poly in raw["regions"][rid]]
        cells[rid] = [p for p in polys if len(p) >= 3]
        assert cells[rid], "нет контура области " + rid
    country = [dedupe([proj(*pt) for pt in poly]) for poly in raw["country"]]
    allx = [p[0] for poly in country for p in poly]; ally = [p[1] for poly in country for p in poly]
    W, H = float(math.ceil(max(allx) + 40)), float(math.ceil(max(ally) + 40))
    print("карта %dx%d, невязка привязки по схеме: %s" % (W, H, raw.get("fit_error_deg")))
    for rid in ids:
        for poly in cells[rid]:
            if not is_simple(poly):
                print("  предупреждение: полигон не простой:", rid, len(poly))

    # города против областей
    bad = []
    for c in CITIES:
        pt = proj(c[3], c[4])
        if not any(point_in(pt, poly) for poly in cells[c[6]]):
            bad.append(c[0])
    print("города вне своей области (допустимая погрешность схемы):", bad)

    def snap(pt, limit=30.0):
        """Береговые города из-за грубого берега схемы могут оказаться в воде: сдвигаем на сушу (не больше limit)."""
        if any(point_in(pt, poly) for poly in country):
            return pt
        best, bp = 1e18, pt
        for poly in country:
            for i in range(len(poly)):
                x0, y0 = poly[i]; x1, y1 = poly[(i + 1) % len(poly)]
                dx, dy = x1 - x0, y1 - y0
                t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, ((pt[0] - x0) * dx + (pt[1] - y0) * dy) / (dx * dx + dy * dy)))
                qx, qy = x0 + t * dx, y0 + t * dy
                d = (pt[0] - qx) ** 2 + (pt[1] - qy) ** 2
                if d < best:
                    best, bp = d, (qx, qy)
        dist = best ** 0.5
        if dist > limit or dist == 0:
            return pt
        ux, uy = (bp[0] - pt[0]) / dist, (bp[1] - pt[1]) / dist
        return (bp[0] + ux * 2.5, bp[1] + uy * 2.5)

    def near_country(pt, limit=25.0):
        if any(point_in(pt, poly) for poly in country):
            return True
        q = snap(pt, limit)
        return q != pt

    def trim_river(rid, pts):
        if rid == "danube":
            return pts
        keep = [near_country(p) for p in pts]
        a = 0
        while a < len(pts) and not keep[a]:
            a += 1
        b = len(pts)
        while b > a and not keep[b - 1]:
            b -= 1
        return pts[a:b]

    # море и суша соседей
    SEA = [
        [(29.7, 44.6), (29.6, 45.3), (30.5, 46.8), (33.0, 47.3), (36.0, 47.6), (38.2, 47.4), (38.9, 47.25), (39.4, 47.15),
         (38.5, 46.6), (38.2, 46.1), (37.5, 45.45), (37.0, 45.25), (37.3, 44.85), (37.8, 44.7), (39.05, 44.1), (39.75, 43.55),
         (42.0, 43.0), (42.0, 41.0), (26.0, 41.0), (26.5, 43.0), (28.6, 43.8)],
    ]
    geo = {
        "version": 2,
        "note": "Контуры областей получены из схемы, предоставленной автором проекта (tools/extract_regions.py); реки, города и рельеф — ориентирные точки. Не геодезические данные.",
        "projection": {"lon0": LON0, "lat0": LAT0, "k": K, "cos_lat": COS},
        "map_size": [W, H],
        "country": [[r1(p) for p in poly] for poly in country],
        "land_frame": [[-200.0, -200.0], [W + 400.0, -200.0], [W + 400.0, H + 300.0], [-200.0, H + 300.0]],
        "sea": [[r1(proj(*p)) for p in poly] for poly in SEA],
        "rivers": [{"id": r[0], "name": r[1], "name_uk": r[2], "width": r[4],
                    "points": [r1(p) for p in trim_river(r[0], [proj(*p) for p in r[3]])]} for r in RIVERS],
        "areas": [{"id": a[0], "kind": a[1], "name": a[2], "name_uk": a[3],
                   "points": [r1(proj(*p)) for p in a[4]]} for a in AREAS],
        "labels": [{"text": l[0], "text_uk": l[1], "pos": r1(proj(l[2], l[3])), "kind": l[4]} for l in LABELS],
    }
    cpos = {c[0]: snap(proj(c[3], c[4])) for c in CITIES}
    geo["roads"] = [{"id": r[0], "name": r[1], "cities": r[2], "points": [r1(cpos[c]) for c in r[2]]} for r in ROADS]
    geo["cities"] = [{"id": c[0], "name": c[1], "name_uk": c[2], "pos": r1(cpos[c[0]]),
                      "tier": c[5], "region": c[6], "lon": c[3], "lat": c[4]} for c in CITIES]
    with open(os.path.join(ROOT, "data/global_map/ukraine.json"), "w", encoding="utf-8") as f:
        json.dump(geo, f, ensure_ascii=False, separators=(",", ":"))

    cname = {c[0]: c[1] for c in CITIES}
    terr = []
    for r in REGIONS:
        polys = cells[r[0]]
        main_poly = polys[0]
        terr.append({
            "id": r[0], "name": r[1], "name_uk": r[2], "short": SHORT.get(r[0], r[1].replace(" область", "")),
            "kind": "oblast" if r[0] != "crimea" else "republic", "capital": r[4], "capital_name": cname[r[4]],
            "owner": "neutral", "control": "neutral",
            "polygon": [r1(p) for p in main_poly], "extra_polygons": [[r1(p) for p in q] for q in polys[1:]],
            "label_pos": r1(pole_of_inaccessibility(main_poly)),
            "scenarios": [],
        })
    with open(os.path.join(ROOT, "data/global_map/territories.json"), "w", encoding="utf-8") as f:
        json.dump({"map_size": [W, H], "layout": "reference_scheme_v2", "territories": terr}, f, ensure_ascii=False, separators=(",", ":"))

    # места и события
    places = []
    nev = 0
    stat = {}
    for (pid, name, lon, lat, pos_status, region, prio, events) in places_data.PLACES:
        pos = (r1(snap(proj(lon, lat))) if (pos_status == "exact" and pid != "snake_island") else r1(proj(lon, lat))) if lon is not None else None
        evs = []
        for (eid, title, years, dstat, dlabel, summary, srcs, note) in events:
            evs.append({"id": eid, "title": title, "years": years, "date_status": dstat, "date_label": dlabel,
                        "summary": summary, "note": note,
                        "sources": [{"title": places_data.SRC[k][0], "url": places_data.SRC[k][1]} for k in srcs],
                        "scenario_id": eid if dstat == "fictional" else ""})
            nev += 1
            stat[dstat] = stat.get(dstat, 0) + 1
        places.append({"id": pid, "name": name, "pos": pos, "pos_status": pos_status, "region": region,
                       "priority": prio, "events": evs})
    with open(os.path.join(ROOT, "data/global_map/places.json"), "w", encoding="utf-8") as f:
        json.dump({"version": 1, "places": places}, f, ensure_ascii=False, indent=1)
    print("мест: %d, событий: %d, статусы дат: %s" % (len(places), nev, stat))
    names = {"verified": "подтверждены", "partial": "частично", "needs_check": "ТРЕБУЕТ ПРОВЕРКИ", "fictional": "вымышленный тест"}
    lines = ["# Места и события глобальной карты", "",
             "Автогенерируется `tools/gen_ukraine.py` из `tools/places_data.py`. Список мест — из перечня автора проекта; новых событий не добавлено.", "",
             "Статусы: **подтверждены** — сверено по источникам; **частично** — источники расходятся; **ТРЕБУЕТ ПРОВЕРКИ** — даты и описание не сверялись, годы ориентировочные.", "",
             "| Место | Событие | Даты | Статус | Положение |", "|---|---|---|---|---|"]
    for pl in places:
        for ev in pl["events"]:
            lines.append("| %s | %s | %s | %s | %s |" % (pl["name"], ev["title"], ev["date_label"], names[ev["date_status"]], pl["pos_status"]))
    os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
    with open(os.path.join(ROOT, "docs/PLACES.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    if preview:
        import matplotlib; matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from matplotlib.patches import Polygon
        import colorsys
        fig, ax = plt.subplots(figsize=(13, 8.5))
        ax.set_facecolor("#1b4f7a")
        ax.add_patch(Polygon(geo["land_frame"], closed=True, fc="#5d6158"))
        for sea in geo["sea"]:
            ax.add_patch(Polygon(sea, closed=True, fc="#1b4f7a"))
        for poly in country:
            ax.add_patch(Polygon(poly, closed=True, fc="#46654d", ec="k", lw=1.2))
        for k, rid in enumerate(ids):
            for poly in cells[rid]:
                ax.add_patch(Polygon(poly, closed=True, fc="none", ec="#10161c", lw=0.7))
            lx, ly = pole_of_inaccessibility(cells[rid][0]); ax.text(lx, ly, rid, fontsize=6, ha="center", color="w")
        for r in RIVERS:
            pts = [proj(*p) for p in r[3]]; ax.plot(*zip(*pts), c="#4aa3ff", lw=r[4] * 0.7)
        for pl in places:
            if pl["pos"]:
                ax.plot(*pl["pos"], "D", c="#facc15" if pl["events"][0]["date_status"] != "fictional" else "#cbd5e1", ms=5)
                if pl["priority"] == 1: ax.text(pl["pos"][0] + 4, pl["pos"][1] - 4, pl["name"], fontsize=6, color="w")
        ax.set_xlim(-40, W + 40); ax.set_ylim(H + 40, -40); ax.set_aspect("equal")
        fig.savefig(preview, dpi=90, bbox_inches="tight")
        print("превью:", preview)


if __name__ == "__main__":
    main()
