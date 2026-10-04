#!/usr/bin/env python3
"""Normalize the researched card-benefit JSONs into the PerkPilot SeedData.json bundle.

Rules (mirror the approved architecture plan's normalized catalog):
- Usage tricks / strategy notes become *tips* nested under their parent benefit,
  never standalone benefits or checklist rows.
- Discontinued / negative / metadata-only rows are excluded.
- Southwest's DoorDash bundle is split into two records (annual DashPass +
  quarterly $10 credit).
- Stable IDs are deterministic slugs; import is idempotent on stableId.

Expected normalized counts per card (must total 238):
  amex-platinum:36 chase-sapphire-reserve:23 chase-sapphire-preferred:23
  chase-ink-business-preferred:17 delta-skymiles-reserve:25 robinhood-gold:14
  costco-anywhere-visa:15 chase-prime-visa:20 sams-club-mastercard:11
  southwest-premier:17 chase-freedom-unlimited:19 chase-ink-business-unlimited:18
"""
import hashlib
import json
import re
import sys
from pathlib import Path

SRC_DIR = Path.home() / "workspace/research_notes/card-benefits"
OUT = Path.home() / "workspace/perkpilot/PerkPilot/PerkPilot/Resources/SeedData.json"

CARD_META = [
    # (match substring in canonical name, stableId, issuer)
    ("American Express Platinum Card", "amex-platinum", "American Express"),
    ("Chase Sapphire Reserve", "chase-sapphire-reserve", "Chase"),
    ("Chase Sapphire Preferred", "chase-sapphire-preferred", "Chase"),
    ("Chase Ink Business Preferred", "chase-ink-business-preferred", "Chase"),
    ("Delta SkyMiles Reserve", "delta-skymiles-reserve", "American Express"),
    ("Robinhood Gold Card", "robinhood-gold", "Robinhood"),
    ("Costco Anywhere Visa", "costco-anywhere-visa", "Citi"),
    ("Prime Rewards Visa Signature", "chase-prime-visa", "Chase"),
    ("Sam's Club Mastercard", "sams-club-mastercard", "Synchrony Bank"),
    ("Southwest Rapid Rewards Premier", "southwest-premier", "Chase"),
    ("Chase Freedom Unlimited", "chase-freedom-unlimited", "Chase"),
    ("Chase Ink Business Unlimited", "chase-ink-business-unlimited", "Chase"),
]

EXPECTED_COUNTS = {
    "amex-platinum": 36, "chase-sapphire-reserve": 23, "chase-sapphire-preferred": 23,
    "chase-ink-business-preferred": 17, "delta-skymiles-reserve": 25, "robinhood-gold": 14,
    "costco-anywhere-visa": 15, "chase-prime-visa": 20, "sams-club-mastercard": 11,
    "southwest-premier": 17, "chase-freedom-unlimited": 19, "chase-ink-business-unlimited": 18,
}

# parent benefit name -> [tip benefit names]  (exact source names)
FOLD_TIPS = {
    "amex-platinum": {
        "Airline incidental fee credit": [
            "Airline fee credit workarounds: what still triggers it in 2026",
            "Airline selection mid-year change via chat",
        ],
    },
    "chase-sapphire-reserve": {
        "The Edit by Chase Travel Hotel Credit": [
            "Double-Dip Hotel Credit Stack ($500 off one stay)",
        ],
    },
    "delta-skymiles-reserve": {
        "Delta Sky Club access": ["Sky Club Visit mechanics and guest-pass strategy"],
        "Annual companion certificate": ["Companion certificate fare-class and expiration strategy"],
        "MQD Boost": ["MQD Boost counting and exclusions"],
        "Delta Stays statement credit": ["Delta Stays credit stacking and multi-card strategy"],
        "Rideshare credit": ["Rideshare credit quirks"],
    },
    "robinhood-gold": {
        "3% flat cash back on all eligible purchases": [
            "Redeem points for upgraded card designs",
            "Points clawback and rescission rules (things that break the 3%)",
            "Ineligible purchases earn no points",
            "Points forfeiture on account closure",
            "No sign-up bonus or 0% intro APR",
            "No penalty APR, no overlimit fee, no minimum interest charge",
        ],
    },
}

# card stableId -> [benefit names to drop entirely]
EXCLUDE = {
    "chase-sapphire-preferred": [
        "No airport lounge access (Sapphire Lounges are Reserve-only)",
        "10% anniversary points bonus (discontinued)",
    ],
    "chase-ink-business-preferred": ["Card identity note"],
}

SOUTHWEST_DOORDASH_NAME = "DoorDash DashPass + quarterly grocery credit"


def slugify(text: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return re.sub(r"-{2,}", "-", s) or "item"


def unique(base: str, seen: set) -> str:
    cand, i = base, 2
    while cand in seen:
        cand, i = f"{base}-{i}", i + 1
    seen.add(cand)
    return cand


def load_all():
    cards = []
    for fname in ("card-benefits.json", "new-cards.json"):
        data = json.loads((SRC_DIR / fname).read_text())
        cards.extend(data["cards"])
    return cards


def southwest_split(benefit: dict, seen_ids: set) -> list:
    """Split the DoorDash bundle into DashPass membership + quarterly credit."""
    src = benefit["sources"]
    dashpass = {
        "name": "DoorDash DashPass membership",
        "cadence": "annual",
        "amount": "One-year complimentary DashPass; must activate by Dec 31, 2027",
        "how_to_use": ("Activate DashPass by Dec 31, 2027 via the Chase offer page. "
                       "After the free year it auto-enrolls at the paid monthly rate — "
                       "set a reminder to cancel."),
        "enrollment_required": True,
        "lesser_known": True,
        "sources": src,
    }
    quarterly = {
        "name": "DoorDash $10 quarterly credit (non-restaurant orders)",
        "cadence": "quarterly",
        "amount": "$10 off per quarter; through Dec 31, 2027",
        "how_to_use": ("Applies to grocery, convenience, and retail orders (not restaurants) "
                       "while DashPass is active; discount applies automatically at checkout "
                       "on eligible orders."),
        "enrollment_required": True,
        "lesser_known": True,
        "sources": src,
    }
    return [dashpass, quarterly]


def main() -> int:
    raw_cards = load_all()
    used_card_ids, used_benefit_ids, used_tip_ids = set(), set(), set()
    out_cards = []

    for raw in raw_cards:
        match = next((m for m in CARD_META if m[0] in raw["name"]), None)
        if match is None:
            print(f"ERROR: no card mapping for {raw['name']}", file=sys.stderr)
            return 1
        _, card_id, issuer = match
        card_id = unique(card_id, used_card_ids)

        fold = FOLD_TIPS.get(card_id, {})
        tip_lookup = {}
        for parent, tips in fold.items():
            for t in tips:
                tip_lookup[t] = parent
        excluded = set(EXCLUDE.get(card_id, []))

        # Expand Southwest split before processing
        benefits_src = []
        for b in raw["benefits"]:
            if card_id == "southwest-premier" and b["name"] == SOUTHWEST_DOORDASH_NAME:
                benefits_src.extend(southwest_split(b, used_benefit_ids))
            else:
                benefits_src.append(b)

        pending_tips = {}  # parent name -> [tip dicts]
        out_benefits = []

        for b in benefits_src:
            name = b["name"]
            if name in excluded:
                continue
            if name in tip_lookup:
                parent = tip_lookup[name]
                tip = {
                    "stableId": unique(f"{card_id}--tip-{slugify(name)[:48]}", used_tip_ids),
                    "text": f"{name}: {b['how_to_use']}",
                    "sources": b["sources"],
                }
                if not tip["sources"]:
                    print(f"ERROR: tip without sources: {name}", file=sys.stderr)
                    return 1
                pending_tips.setdefault(parent, []).append(tip)
                continue
            out_benefits.append(b)

        # Verify every fold target existed
        for parent, tips in pending_tips.items():
            if parent not in {b["name"] for b in out_benefits}:
                print(f"ERROR: tip parent '{parent}' not found in {card_id}", file=sys.stderr)
                return 1
        for parent in {p for tips in fold.values() for p in [parent for parent in []]}:
            pass

        normalized = []
        for b in out_benefits:
            if not b["sources"]:
                print(f"ERROR: benefit without sources: {card_id}/{b['name']}", file=sys.stderr)
                return 1
            normalized.append({
                "stableId": unique(f"{card_id}--{slugify(b['name'])[:56]}", used_benefit_ids),
                "name": b["name"],
                "cadence": b["cadence"],
                "amountDisplay": b["amount"],
                "howToUse": b["how_to_use"],
                "enrollmentRequired": bool(b["enrollment_required"]),
                "lesserKnown": bool(b["lesser_known"]),
                "sources": b["sources"],
                "tips": pending_tips.get(b["name"], []),
            })

        out_cards.append({
            "stableId": card_id,
            "canonicalName": raw["name"],
            "issuer": issuer,
            "annualFeeDisplay": raw.get("annual_fee", ""),
            "benefits": normalized,
        })

    # Order cards per plan table
    order = [m[1] for m in CARD_META]
    out_cards.sort(key=lambda c: order.index(c["stableId"]))

    # Validate counts
    total, ok = 0, True
    for c in out_cards:
        n, want = len(c["benefits"]), EXPECTED_COUNTS[c["stableId"]]
        total += n
        flag = "OK " if n == want else "FAIL"
        if n != want:
            ok = False
        print(f"{flag} {c['stableId']}: {n} (expected {want})")
    print(f"TOTAL: {total} (expected 238)")
    if total != 238 or not ok:
        return 1

    payload = {"cards": out_cards}
    checksum = hashlib.sha256(json.dumps(payload, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    manifest = {
        "catalogVersion": "2026.10.03",
        "schemaVersion": 1,
        "locale": "en-US",
        "exportedAt": "2026-10-04",
        "cardCount": len(out_cards),
        "benefitCount": total,
        "checksum": f"sha256:{checksum}",
        **payload,
    }

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
