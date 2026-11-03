#!/usr/bin/env python3
"""Builds the exercise picture package from the Everkinetic data repository.

    python3 tool/exercise_images/build.py --source <everkinetic/data clone> --out <dir>

Reads `src/exercises/<id>/` of https://github.com/everkinetic/data (pinned to
SOURCE_COMMIT: the script refuses any other commit, so what is published is
what was reviewed) and writes:

  <out>/png/<name>.png   transparent mask, 1024 px: dark lines opaque black,
                         paper transparent (tinted by the app / web page)
  <out>/images.json      one row per picture: public id, keywords, source,
                         licence, author, attribution
  <out>/seed.sql         the same rows as an idempotent upsert

Only `src/exercises` is used. `images-png-unknown` (provenance unknown) and
`images-ai` (unclear) are never read. Nothing here is secret; the upload step
(upload.py) is the only one that needs credentials.
Needs Pillow (`pip install pillow`). See docs/features/exercise_image_library.md.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageOps

SOURCE_COMMIT = "446bb9a3d0c3beb6b84f7c9d77dfc8af707a2ab6"
SOURCE_REPO = "https://github.com/everkinetic/data"
LICENSE = "CC-BY-SA-4.0"
AUTHOR = "Everkinetic (Greg Priday)"
PUBLIC_ID_PREFIX = "azm/exercises"
FRAMES = ("tension", "relaxation")
MAX_SIDE = 1024
MAX_KEYWORDS = 40

STOP_WORDS = {"with", "the", "and", "of", "on", "to", "in", "for", "using", "a"}

# Muscle -> the six groups of the app's library (MuscleGroup).
GROUP_OF_MUSCLE = {
    "pectoralis major": "chest",
    "latissimus dorsi": "back",
    "trapezius": "back",
    "erector spinae": "back",
    "deltoid": "shoulders",
    "biceps brachii": "arms",
    "triceps brachii": "arms",
    "quadriceps": "legs",
    "ischiocrural muscles": "legs",
    "glutaeus maximus": "legs",
    "gastrocnemius": "legs",
    "soleus": "legs",
    "abdominals": "core",
    "obliques": "core",
}

# Arabic (Egyptian gym words) for search. Fixed table: nothing is guessed per
# exercise. Keep it reviewed by an Arabic speaker when it grows.
AR_GROUP = {
    "chest": "صدر",
    "back": "ضهر",
    "shoulders": "كتف",
    "arms": "دراع",
    "legs": "رجل",
    "core": "بطن",
}
AR_MUSCLE = {
    "pectoralis major": ["صدر"],
    "abdominals": ["بطن"],
    "biceps brachii": ["باي", "بايسبس"],
    "quadriceps": ["فخذ", "أمامية"],
    "triceps brachii": ["تراي", "ترايسبس"],
    "deltoid": ["كتف"],
    "trapezius": ["ترابيس"],
    "gastrocnemius": ["سمانة"],
    "soleus": ["سمانة"],
    "latissimus dorsi": ["ضهر", "لات"],
    "ischiocrural muscles": ["خلفية", "فخذ"],
    "erector spinae": ["أسفل الضهر"],
    "glutaeus maximus": ["مؤخرة", "جلوتس"],
    "obliques": ["جوانب البطن"],
    "forearm": ["ساعد"],
    "hip abductors": ["مبعدات الفخذ"],
    "upper back": ["أعلى الضهر"],
    "core": ["بطن", "كور"],
    "back": ["ضهر"],
}
AR_EQUIPMENT = {
    "barbell": ["بار"],
    "dumbbell": ["دمبل"],
    "dumbbells": ["دمبل"],
    "machine": ["جهاز"],
    "cable": ["كابل"],
    "bench": ["بنش"],
    "flat bench": ["بنش"],
    "body": ["وزن الجسم"],
    "smith machine": ["سميث"],
    "exercise band": ["استك"],
    "stability ball": ["كرة"],
    "swiss ball": ["كرة"],
    "exercise ball": ["كرة"],
    "bosu ball": ["بوسو"],
    "medicine ball": ["كرة طبية"],
    "weight plate": ["صفيحة"],
    "pull-up bar": ["عقلة"],
    "parallel bars": ["متوازي"],
    "towel": ["فوطة"],
}

CLEAN = re.compile(r"[^\w\s:().,'&/+-]", re.UNICODE)


def clean_text(value: str) -> str:
    """Plain text only: no control characters, quotes kept for SQL escaping."""
    value = "".join(ch for ch in str(value) if ch.isprintable())
    return re.sub(r"\s+", " ", CLEAN.sub("", value)).strip()


def words(text: str):
    for token in re.split(r"[^a-z0-9]+", text.lower()):
        if len(token) >= 2 and token not in STOP_WORDS:
            yield token


def keywords_for(row: dict) -> list:
    out = []
    out += words(row["title_en"])
    out += words(row["name"])
    for muscle in row["primary"] + row["secondary"]:
        out += words(muscle)
        out += AR_MUSCLE.get(muscle.lower(), [])
    for group in row["groups"]:
        out += [group, AR_GROUP[group]]
    for equipment in row["equipment"]:
        base = equipment.lower().split(":")[0].strip()
        out += words(equipment)
        out += AR_EQUIPMENT.get(base, [])
    out += words(row["type"])
    seen, unique = set(), []
    for word in out:
        if word and word not in seen:
            seen.add(word)
            unique.append(word)
    return unique[:MAX_KEYWORDS]


def make_mask(src: Path, dst: Path) -> None:
    """Dark lines on light paper -> black lines on transparent."""
    gray = Image.open(src).convert("L")
    alpha = ImageOps.invert(gray).point(lambda v: 0 if v < 6 else v)
    box = alpha.getbbox()
    if box is None:
        raise ValueError(f"{src}: no drawing found")
    pad = 6
    box = (
        max(box[0] - pad, 0),
        max(box[1] - pad, 0),
        min(box[2] + pad, alpha.width),
        min(box[3] + pad, alpha.height),
    )
    alpha = alpha.crop(box)
    alpha.thumbnail((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    out = Image.new("RGBA", alpha.size, (0, 0, 0, 0))
    out.putalpha(alpha)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out.save(dst, optimize=True)


def sql_text(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_array(values) -> str:
    return "array[" + ", ".join(sql_text(v) for v in values) + "]::text[]"


def seed_sql(rows: list) -> str:
    cols = (
        "public_id, exercise_key, frame, title_en, keywords, muscle_groups, "
        "muscles, equipment, exercise_type, source_url, source_commit, "
        "license, author, attribution"
    )
    lines = [
        "-- Generated by tool/exercise_images/build.py from everkinetic/data at",
        f"-- {SOURCE_COMMIT}. Do not edit by hand: change the script and rebuild.",
        "insert into public.exercise_images (" + cols + ") values",
    ]
    values = []
    for r in rows:
        values.append(
            "  ("
            + ", ".join(
                [
                    sql_text(r["public_id"]),
                    sql_text(r["exercise_key"]),
                    sql_text(r["frame"]),
                    sql_text(r["title_en"]),
                    sql_array(r["keywords"]),
                    sql_array(r["muscle_groups"]),
                    sql_array(r["muscles"]),
                    sql_array(r["equipment"]),
                    sql_text(r["exercise_type"]),
                    sql_text(r["source_url"]),
                    sql_text(SOURCE_COMMIT),
                    sql_text(LICENSE),
                    sql_text(AUTHOR),
                    sql_text(r["attribution"]),
                ]
            )
            + ")"
        )
    lines.append(",\n".join(values))
    lines.append("on conflict (public_id) do update set")
    updates = [
        "keywords = excluded.keywords",
        "muscle_groups = excluded.muscle_groups",
        "muscles = excluded.muscles",
        "equipment = excluded.equipment",
        "title_en = excluded.title_en",
        "exercise_type = excluded.exercise_type",
        "source_url = excluded.source_url",
        "source_commit = excluded.source_commit",
        "license = excluded.license",
        "author = excluded.author",
        "attribution = excluded.attribution",
    ]
    lines.append("  " + ",\n  ".join(updates) + ";")
    return "\n".join(lines) + "\n"


def check_commit(source: Path) -> None:
    head = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    if head != SOURCE_COMMIT:
        sys.exit(
            f"The source is at {head}, but this script is reviewed for "
            f"{SOURCE_COMMIT}. Check the new commit's licence, then change "
            "SOURCE_COMMIT."
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--no-commit-check", action="store_true", help="tests only")
    args = parser.parse_args()
    if not args.no_commit_check:
        check_commit(args.source)

    rows = []
    for folder in sorted((args.source / "src" / "exercises").iterdir()):
        data_file = folder / f"{folder.name}.json"
        if not data_file.is_file():
            continue
        data = json.loads(data_file.read_text(encoding="utf-8"))
        exercise_id = clean_text(data["id"])
        if not re.fullmatch(r"\d{4}", exercise_id):
            sys.exit(f"{folder}: unexpected id {exercise_id!r}")
        name = clean_text(data["name"])
        title = clean_text(data["title"])
        primary = [clean_text(m) for m in data.get("primary", [])]
        secondary = [clean_text(m) for m in data.get("secondary", [])]
        equipment = [clean_text(e) for e in data.get("equipment", [])]
        groups = sorted({GROUP_OF_MUSCLE[m] for m in primary if m in GROUP_OF_MUSCLE})
        for frame in FRAMES:
            src = folder / f"{exercise_id}-{frame}.png"
            if not src.is_file():
                continue
            key = f"ek-{exercise_id}"
            public_id = f"{PUBLIC_ID_PREFIX}/{key}-{frame}"
            row = {
                "public_id": public_id,
                "exercise_key": key,
                "frame": frame,
                "name": name,
                "title_en": title,
                "primary": primary,
                "secondary": secondary,
                "equipment": equipment,
                "groups": groups,
                "type": clean_text(data.get("type", "")),
            }
            row["keywords"] = keywords_for(row)
            row["muscle_groups"] = groups
            row["muscles"] = primary + [m for m in secondary if m not in primary]
            row["exercise_type"] = row.pop("type")
            row["source_url"] = (
                f"{SOURCE_REPO}/blob/{SOURCE_COMMIT}/src/exercises/"
                f"{exercise_id}/{exercise_id}-{frame}.png"
            )
            row["attribution"] = (
                f'"{title}" by {AUTHOR}, {SOURCE_REPO}, CC BY-SA 4.0. '
                "Changed: made transparent, resized."
            )
            make_mask(src, args.out / "png" / f"{key}-{frame}.png")
            for drop in ("name", "primary", "secondary", "groups"):
                row.pop(drop)
            rows.append(row)

    rows.sort(key=lambda r: r["public_id"])
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "images.json").write_text(
        json.dumps(
            {"sourceCommit": SOURCE_COMMIT, "license": LICENSE, "images": rows},
            indent=2,
            ensure_ascii=False,
        )
        + "\n",
        encoding="utf-8",
    )
    (args.out / "seed.sql").write_text(seed_sql(rows), encoding="utf-8")
    print(f"{len(rows)} pictures, {len({r['exercise_key'] for r in rows})} exercises")


if __name__ == "__main__":
    main()
