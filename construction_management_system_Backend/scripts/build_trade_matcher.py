"""Rebuild trade_matcher.joblib + trade_profiles.json from job_categorization.parquet.

Expanded seed keywords fix the 16 failing cases found in eval:
  - plumbing: flush/valve/mixer/tap/shower/faucet/toilet/drain/sewer
  - hvac: aircon/cooling/duct/refrigerant
  - carpenter: hinge/lock/door/wooden
  - electrical: cctv/camera/network cable/socket/breaker/conduit
  - laborer: clean/debris/scaffold/barrier/demolish/carry/haul/unload
  - supervision: fire extinguisher/inspection/compliance/sampling/test/inspect
  - roofing: membrane/waterproof/bitumen
  - tiling: grout/backsplash/ceramic
"""
import json
import re
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS, TfidfVectorizer

BACKEND = Path(__file__).resolve().parent.parent  # Backend/scripts -> Backend
DATA = BACKEND / "data"

CANONICAL = ["carpenter", "electrical", "plumbing", "masonry", "painting", "welding",
             "hvac", "roofing", "tiling", "drywall", "glazing", "flooring",
             "equipment", "laborer", "insulation", "supervision"]

# Expanded seed keywords (kept in sync with app/ai_service.py)
SEED_KEYWORDS = {
    "carpenter": ["carpenter", "cabinet", "joinery", "timber", "wood", "wooden", "plywood", "formwork", "framework", "carpentry", "hinge", "door lock", "partition wall", "sheathing", "stud", "木工", "橱柜", "tukang kayu", "pertukangan", "kabinet", "bingkai"],
    "electrical": ["electrician", "electrical", "electric", "wiring", "cable", "lighting", "db panel", "cctv", "camera", "network cable", "socket", "breaker", "conduit", "switch", "ceiling fan", "电工", "电线", "照明", "elektrik", "pendawaian", "juruelektrik", "lampu", "kabel"],
    "plumbing": ["plumber", "plumbing", "pipe", "water pipe", "sanitary", "chiller", "flush", "valve", "mixer", "tap", "shower", "faucet", "toilet", "drain", "sewer", "水管", "管道", "给排水", "paip", "tukang paip", "pili", "longkang"],
    "masonry": ["mason", "masonry", "brick", "block", "concrete", "rebar", "stucco", "砌砖", "砖墙", "混凝土", "bata", "tembok", "konkrit", "simen", "bancuh", "asas"],
    "painting": ["painter", "painting", "paint", "emulsion", "primer", "coat", "varnish", "stain", "lacquer", "sealer", "topcoat", "polyurethane", "stair rail", "handrail", "furniture", "trim", "油漆", "粉刷", "涂料", "mengecat", "pengecat", "cat dinding"],
    "welding": ["welder", "welding", "weld", "steel", "metal", "ironworker", "railing", "column", "erect", "焊接", "钢结构", "kimpal", "pengimpal", "keluli"],
    "hvac": ["hvac", "air conditioning", "aircon", "cooling", "ventilation", "ahu", "duct", "refrigerant", "vent", "air vent", "暖通", "空调", "通风", "penghawa dingin", "penyaman udara", "pengudaraan"],
    "roofing": ["roofer", "roofing", "roof", "shingle", "membrane", "waterproof", "bitumen", "屋顶", "屋面", "bumbung", "atap"],
    "tiling": ["tile", "tiler", "tiling", "terrazzo", "ceramic", "grout", "backsplash", "瓷砖", "地砖", "jubin", "mozek"],
    "drywall": ["drywall", "sheetrock", "gypsum", "taper", "partition", "ceiling board", "隔墙", "石膏板", "dinding kering", "gipsum", "papan gypsum"],
    "glazing": ["glazier", "glass", "window", "glazing", "玻璃", "门窗安装", "kaca", "tingkap"],
    "flooring": ["floor", "flooring", "linoleum", "carpet", "vinyl", "laminate", "epoxy", "wooden floor", "grind", "grinding", "地板", "地毯", "lantai", "vinil", "lamina", "permaidani"],
    "equipment": ["operator", "excavator", "bulldozer", "backhoe", "crane", "grader", "shovel", "dozer", "pile", "forklift", "concrete pump", "挖掘机", "推土机", "jengkaut", "kren", "jentera", "operator jentera"],
    "laborer": ["laborer", "labourer", "helper", "trench", "digger", "craft", "clean", "debris", "scaffold", "scaffolding", "barrier", "demolish", "demolition", "carry", "haul", "unload", "jackhammer", "signage", "sign", "breaking", "chipping", "rubble", "sweep", "搬运", "杂工", "普工", "buruh", "pekerja kasar", "pembantu", "perancah", "perobohan"],
    "insulation": ["insulation", "insulator", "insulate", "rockwool", "fiberglass", "foam", "cavity", "保温", "隔热", "penebat", "penebat haba", "busa", "gentian kaca"],
    "supervision": ["superintendent", "supervisor", "foreman", "coordinator", "manager", "inspection", "inspector", "inspect", "fire extinguisher", "compliance", "sampling", "工地主任", "监工", "巡查", "penyelia", "penyelia tapak", "pemeriksa", "pemantauan", "mandor"],
}

# category -> canonical trade mapping from job_categorization.parquet
CATEGORY_MAP = {
    "carpenter": ["Cabinetmakers and Bench Carpenters", "Carpenters", "Woodworkers, All Other", "Furniture Finishers", "Model Makers, Wood"],
    "electrical": ["Electricians", "Electrical Power-Line Installers and Repairers", "Electrical and Electronics Installers and Repairers", "Electrical and Electronics Repairers", "Audio and Video Equipment Installers and Repairers", "Security and Fire Alarm Systems Installers", "Telecommunications Equipment Installers and Repairers", "Electrical and Electronic Equipment Assemblers", "Electric Motor, Power Tool, and Related Repairers", "Electrical and Electronics Drafters", "Electrical Engineers"],
    "plumbing": ["Plumbers, Pipefitters, and Steamfitters", "Pipelayers", "Plumbing, Heating, and Air-Conditioning Installers", "Septic Tank Servicers and Sewer Pipe Cleaners"],
    "masonry": ["Brickmasons and Blockmasons", "Cement Masons and Concrete Finishers", "Stonemasons", "Terrazzo Workers and Finishers", "Reinforcing Iron and Rebar Workers"],
    "painting": ["Painters, Construction and Maintenance", "Painting, Coating, and Decorating Workers", "Paperhangers", "Coating, Painting, and Spraying Machine Setters, Operators, and Tenders"],
    "welding": ["Welders, Cutters, Solderers, and Brazers", "Welding, Soldering, and Brazing Machine Setters, Operators, and Tenders", "Structural Iron and Steel Workers", "Sheet Metal Workers", "Boilermakers"],
    "hvac": ["Heating, Air Conditioning, and Refrigeration Mechanics and Installers", "Boiler Operators and Tenders, Low Pressure", "Stationary Engineers and Boiler Operators"],
    "roofing": ["Roofers", "Waterproofing and Related Workers", "Roof Bolters, Mining"],
    "tiling": ["Tile and Stone Setters", "Floor Layers, Except Carpet, Wood, and Hard Tiles", "Floor Sanders and Finishers", "Carpet Installers"],
    "drywall": ["Drywall and Ceiling Tile Installers", "Tapers", "Insulation Workers, Floor, Ceiling, and Wall", "Plasterers and Stucco Masons"],
    "glazing": ["Glaziers", "Automotive Glass Installers and Repairers"],
    "flooring": ["Floor Layers, Except Carpet, Wood, and Hard Tiles", "Carpet Installers", "Floor Sanders and Finishers", "Hardwood Floor Installers"],
    "equipment": ["Excavating and Loading Machine and Dragline Operators, Surface Mining", "Crane and Tower Operators", "Operating Engineers and Other Construction Equipment Operators", "Pile Driver Operators", "Dredge Operators", "Loading Machine Operators, Underground Mining", "Hoist and Winch Operators", "Industrial Truck and Tractor Operators", "Material Moving Workers, All Other", "Conveyor Operators and Tenders", "Heavy and Tractor-Trailer Truck Drivers"],
    "laborer": ["Construction Laborers", "Helpers--Construction Trades", "Building Cleaning Workers, All Other", "Construction and Related Workers, All Other", "Refuse and Recyclable Material Collectors", "Laborers and Freight, Stock, and Material Movers, Hand", "Cleaners of Vehicles and Equipment", "Landscaping and Groundskeeping Workers", "Demolition Workers"],
    "insulation": ["Insulation Workers, Floor, Ceiling, and Wall", "Insulation Workers, Mechanical", "Hazardous Materials Removal Workers"],
    "supervision": ["Construction Managers", "Construction and Building Inspectors", "First-Line Supervisors of Construction Trades and Extraction Workers", "Managers, All Other", "Supervisors of Building and Grounds Cleaning and Maintenance Workers", "Architects, Except Landscape and Naval"],
}

def clean(text: str) -> str:
    t = re.sub(r"[^a-zA-Z0-9\u4e00-\u9fff ]+", " ", str(text).lower())
    return re.sub(r"\s+", " ", t).strip()

STOP_WORDS = (
    set("the a an and or for with of to in on at by from into onto under over install installing new fix apply lay test check do make set up build construction project work task done ready please need want using use".split())
    | set("yang dan di ke dari ini itu untuk dengan pada atau adalah tidak saya anda kami pasang memasang baiki membaiki periksa memeriksa kerja bekerja projek tugas siap perlu mahu guna menggunakan buat membuat baru letak meletakkan uji menguji pengujian kawasan bangunan semua akan sudah boleh ada tanpa selepas sebelum antara dalam jadual sila mohon bantu".split())
    | set(ENGLISH_STOP_WORDS)
)

def build_profiles():
    df = pd.read_parquet(DATA / "job_categorization.parquet")
    profiles = {}
    titles_all = []
    trade_labels = []
    for trade in CANONICAL:
        cats = CATEGORY_MAP.get(trade, [])
        sel = df[df["category"].isin(cats)] if cats else pd.DataFrame()
        titles = sel["title"].dropna().unique().tolist() if len(sel) else []
        profiles[trade] = titles
        for t in titles:
            titles_all.append(clean(t))
            trade_labels.append(trade)
    return profiles, titles_all, trade_labels

def main():
    profiles, titles_all, trade_labels = build_profiles()
    # Profile text = dataset titles + seed keywords repeated for weight.
    docs = []
    for trade in CANONICAL:
        text_parts = list(profiles[trade])
        seeds = SEED_KEYWORDS.get(trade, [])
        # Repeat seeds so they dominate the TF-IDF profile vector.
        text_parts += seeds * 12
        docs.append(" ".join(clean(p) for p in text_parts))

    vec = TfidfVectorizer(
        sublinear_tf=True,
        stop_words=sorted(STOP_WORDS),
        ngram_range=(1, 2),
        max_features=20000,
    )
    X = vec.fit_transform(docs)
    print("vocab size:", len(vec.vocabulary_))
    for i, trade in enumerate(CANONICAL):
        print(f"  {trade}: {len(profiles[trade])} titles, {X[i].nnz} nz features")

    joblib.dump(
        {"vectorizer": vec, "trade_names": CANONICAL, "trade_vectors": X},
        DATA / "trade_matcher.joblib",
    )
    with open(DATA / "trade_profiles.json", "w", encoding="utf-8") as f:
        json.dump(profiles, f, ensure_ascii=False, indent=2)
    print("saved:", DATA / "trade_matcher.joblib")

if __name__ == "__main__":
    main()
