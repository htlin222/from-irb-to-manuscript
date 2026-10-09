"""Simulate a hospital data export for the HER2+ neoadjuvant teaching demo.

SYNTHETIC DATA. No real patient is represented. The export imitates what a
hospital IT office would hand over after IRB approval: four CSV tables keyed by
chart number, with identifiers, brand/generic drug-name chaos and a handful of
deliberate data-quality defects, so the demo has something real to validate.

Because we generate the data, we also know the truth. Every patient is simulated
under BOTH regimens with the same random draws (coupled potential outcomes), and
the true marginal effects are written to truth.json -- the yardstick for the
causal analysis the agent performs later.

    uv run --no-project --with numpy --with pandas --with lifelines \
        python demo/simulate/simulate_export.py --out demo/simulate/out
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 20260412
N_ELIGIBLE = 640
CUTOFF = date(2025, 12, 31)
ACCRUAL = (date(2012, 1, 1), date(2023, 12, 31))
TDM1_FROM = date(2020, 7, 1)  # adjuvant T-DM1 for residual disease becomes routine

# True data-generating parameters (kept here, never in the study repo).
PCR_LOGIT = {
    "intercept": -0.05,
    "hp": 0.70,
    "hr_pos": -1.00,
    "ct34": -0.40,
    "n23": -0.25,
    "grade3": 0.30,
    "ki67_per10": 0.10,
    "anthracycline": 0.05,
}
EFS_LOGHR = {
    "pcr": -1.30,
    "hp_direct": -0.10,
    "ct34": 0.45,
    "n23": 0.55,
    "n1": 0.20,
    "age65": 0.30,
    "ecog1": 0.25,
    "hr_pos": -0.10,
    "tdm1": -0.60,
}
EFS_BASE = {"shape": 1.25, "scale_years": 21.0}  # Weibull for a reference patient


def dfloat(d: date) -> float:
    return d.toordinal()


def to_date(x: float) -> date:
    return date.fromordinal(int(round(x)))


def simulate_cohort(rng: np.random.Generator, n: int) -> pd.DataFrame:
    span = dfloat(ACCRUAL[1]) - dfloat(ACCRUAL[0])
    # accrual grows over time (more referrals in later years)
    u = rng.beta(1.25, 1.0, n)
    t0 = np.array([to_date(dfloat(ACCRUAL[0]) + x * span) for x in u])
    year = np.array([d.year + (d.timetuple().tm_yday / 366) for d in t0])

    age = np.clip(rng.normal(51, 11, n), 24, 84).round().astype(int)
    ecog = rng.choice([0, 1, 2], n, p=[0.70, 0.27, 0.03])
    ct = rng.choice(["T1c", "T2", "T3", "T4b", "T4d"], n, p=[0.12, 0.55, 0.20, 0.10, 0.03])
    cn = rng.choice(["N0", "N1", "N2", "N3"], n, p=[0.30, 0.45, 0.15, 0.10])
    hr_pos = rng.random(n) < 0.55
    grade = rng.choice([1, 2, 3], n, p=[0.05, 0.45, 0.50])
    ki67 = np.clip(rng.normal(40 + 8 * (grade == 3), 18, n), 3, 95).round()
    bmi = np.clip(rng.normal(24.2, 3.8, n), 16, 42).round(1)
    lvef = np.clip(rng.normal(65, 5, n), 52, 78).round()

    ct34 = np.isin(ct, ["T3", "T4b", "T4d"])
    n23 = np.isin(cn, ["N2", "N3"])
    n1 = cn == "N1"

    # Treatment assignment: era dominates, severity and age modulate (confounding
    # by indication: dual blockade went first to the higher-risk patients).
    lp_hp = (
        1.9 * (year - 2017.3)
        + 1.1 * ct34
        + 0.9 * n23
        + 0.4 * n1
        - 0.04 * (age - 51)
        - 0.6 * (ecog >= 1)
        + 0.2 * (~hr_pos)
    )
    p_hp = 1 / (1 + np.exp(-lp_hp))
    p_hp = np.clip(p_hp, 0.02, 0.97)
    hp = rng.random(n) < p_hp

    # Chemotherapy backbone
    anthracycline = np.where(hp, rng.random(n) < 0.30, rng.random(n) < 0.50)

    df = pd.DataFrame(
        dict(
            t0=t0,
            year=year,
            age=age,
            ecog=ecog,
            ct=ct,
            cn=cn,
            hr_pos=hr_pos,
            grade=grade,
            ki67=ki67,
            bmi=bmi,
            lvef=lvef,
            ct34=ct34,
            n23=n23,
            n1=n1,
            hp=hp,
            anthracycline=anthracycline,
            p_hp=p_hp,
        )
    )
    return df


def potential_outcomes(df: pd.DataFrame, rng: np.random.Generator) -> pd.DataFrame:
    n = len(df)
    u_pcr = rng.random(n)
    u_efs = rng.random(n)
    u_death_rec = rng.random(n)
    u_death_bg = rng.random(n)
    u_prog = rng.random(n)
    u_pfx = rng.random(n)

    out = {}
    for arm in (0, 1):
        lp = (
            PCR_LOGIT["intercept"]
            + PCR_LOGIT["hp"] * arm
            + PCR_LOGIT["hr_pos"] * df.hr_pos
            + PCR_LOGIT["ct34"] * df.ct34
            + PCR_LOGIT["n23"] * df.n23
            + PCR_LOGIT["grade3"] * (df.grade == 3)
            + PCR_LOGIT["ki67_per10"] * (df.ki67 - 40) / 10
            + PCR_LOGIT["anthracycline"] * df.anthracycline
        )
        p = 1 / (1 + np.exp(-lp))
        # progression during neoadjuvant therapy (no surgery, counted non-pCR)
        p_prog = np.where(arm == 1, 0.008, 0.016) * (1 + 1.5 * df.ct34)
        prog = u_prog < p_prog
        pcr = (u_pcr < p) & ~prog

        # adjuvant T-DM1 for residual disease in the later era (date fixed by t0)
        surg_date_approx = df.t0.apply(lambda d: d + timedelta(days=150))
        tdm1 = (~pcr) & ~prog & (surg_date_approx >= TDM1_FROM)

        lh = (
            EFS_LOGHR["pcr"] * pcr
            + EFS_LOGHR["hp_direct"] * arm
            + EFS_LOGHR["ct34"] * df.ct34
            + EFS_LOGHR["n23"] * df.n23
            + EFS_LOGHR["n1"] * df.n1
            + EFS_LOGHR["age65"] * (df.age >= 65)
            + EFS_LOGHR["ecog1"] * (df.ecog >= 1)
            + EFS_LOGHR["hr_pos"] * df.hr_pos
            + EFS_LOGHR["tdm1"] * tdm1
        )
        k, lam = EFS_BASE["shape"], EFS_BASE["scale_years"]
        # inverse-CDF Weibull PH: S(t)=exp(-(t/lam)^k * e^lh)
        t_efs = lam * (-np.log(u_efs) / np.exp(lh)) ** (1 / k)
        # progression before surgery happens early
        t_efs = np.where(prog, 0.25 + 0.2 * u_pfx, t_efs)
        distant = u_pfx < 0.72
        t_death_after = np.where(distant, 2.6, 7.0) * (-np.log(u_death_rec)) ** (1 / 1.1)
        bg_rate = 0.0025 * np.exp(0.075 * (df.age - 50))
        t_bg = -np.log(u_death_bg) / bg_rate
        # EFS event = recurrence/progression or death from any cause, whichever first
        t_rec = t_efs
        t_death = np.minimum(t_rec + t_death_after, t_bg)
        efs_time = np.minimum(t_rec, t_bg)
        out[arm] = pd.DataFrame(
            dict(
                pcr=pcr,
                prog=prog,
                tdm1=tdm1,
                t_rec=t_rec,
                t_bg=t_bg,
                t_death=t_death,
                efs_time=efs_time,
                distant=distant,
            )
        )
    return out


def km_at(times: np.ndarray, years: float) -> float:
    return float(np.mean(times > years))


def truth_summary(df: pd.DataFrame, po: dict) -> dict:
    from lifelines import CoxPHFitter

    res = {}
    p1, p0 = po[1].pcr.mean(), po[0].pcr.mean()
    res["estimand_note"] = (
        "Unsuffixed values are ATE over all simulated eligible patients; _ATT = among HP-treated; _ATO = overlap-weighted (true propensity)."
    )
    res["pcr_risk_H"] = round(float(p0), 4)
    res["pcr_risk_HP"] = round(float(p1), 4)
    res["pcr_risk_difference"] = round(float(p1 - p0), 4)
    res["pcr_odds_ratio_marginal"] = round(float((p1 / (1 - p1)) / (p0 / (1 - p0))), 3)
    w_att = df.hp.values.astype(float)
    w_ato = (df.p_hp * (1 - df.p_hp)).values
    for tag, w in (("ATT", w_att), ("ATO", w_ato)):
        a1 = np.average(po[1].pcr, weights=w)
        a0 = np.average(po[0].pcr, weights=w)
        res[f"pcr_risk_difference_{tag}"] = round(float(a1 - a0), 4)
        for ep, col in (("efs", "efs_time"), ("os", "t_death")):
            s1 = np.average(po[1][col].values > 5, weights=w)
            s0 = np.average(po[0][col].values > 5, weights=w)
            res[f"{ep}_5y_difference_{tag}"] = round(float(s1 - s0), 4)
    obs = np.where(df.hp, po[1].pcr, po[0].pcr)
    res["pcr_crude_H_observed_cohort"] = round(float(obs[~df.hp.values].mean()), 4)
    res["pcr_crude_HP_observed_cohort"] = round(float(obs[df.hp.values].mean()), 4)
    for ep, col in (("efs", "efs_time"), ("os", "t_death")):
        for yrs in (3, 5):
            s1, s0 = km_at(po[1][col].values, yrs), km_at(po[0][col].values, yrs)
            res[f"{ep}_{yrs}y_H"] = round(s0, 4)
            res[f"{ep}_{yrs}y_HP"] = round(s1, 4)
            res[f"{ep}_{yrs}y_difference"] = round(s1 - s0, 4)
        # marginal HR over 5 years of follow-up (administrative censoring at 5y)
        rows = []
        for arm in (0, 1):
            t = po[arm][col].values
            rows.append(pd.DataFrame({"T": np.minimum(t, 5), "E": (t <= 5).astype(int), "hp": arm}))
        cph = CoxPHFitter().fit(pd.concat(rows), "T", "E")
        res[f"{ep}_marginal_HR_5y"] = round(float(np.exp(cph.params_["hp"])), 3)
    res["share_of_EFS_benefit_note"] = (
        "HP raises pCR; pCR lowers EFS hazard; adjuvant T-DM1 (from 2020-07) acts on "
        "residual disease and is era-bound, so it is part of the treatment strategy context."
    )
    return res


DRUG_NAMES = {
    "trastuzumab": ["Trastuzumab", "Herceptin", "HERCEPTIN 440MG INJ", "Herzuma 150mg", "trastuzumab (Ontruzant)"],
    "pertuzumab": ["Pertuzumab", "Perjeta", "PERJETA 420MG/14ML"],
    "phesgo": ["Phesgo 1200/600 SC"],
    "docetaxel": ["Docetaxel", "Taxotere", "DOCETAXEL 80MG"],
    "carboplatin": ["Carboplatin", "Paraplatin"],
    "epirubicin": ["Epirubicin", "Pharmorubicin"],
    "cyclophosphamide": ["Cyclophosphamide", "Endoxan"],
    "paclitaxel": ["Paclitaxel", "Taxol", "Genexol"],
    "tdm1": ["Kadcyla", "Trastuzumab emtansine", "T-DM1 (Kadcyla) 160mg"],
}


def pick(rng, key):
    names = DRUG_NAMES[key]
    return names[rng.integers(len(names))]


def build_export(df: pd.DataFrame, po: dict, rng: np.random.Generator):
    n = len(df)
    arm = df.hp.astype(int).values
    obs = {c: np.where(arm == 1, po[1][c].values, po[0][c].values) for c in po[0].columns}

    chart = rng.choice(np.arange(1_000_000, 9_999_999), n + 80, replace=False)
    registry, orders, surgery, follow = [], [], [], []

    for i in range(n):
        r = df.iloc[i]
        cno = f"{chart[i]:07d}"
        t0 = r.t0
        dx = t0 - timedelta(days=int(rng.integers(10, 35)))
        birth = date(dx.year - int(r.age), int(rng.integers(1, 13)), int(rng.integers(1, 28)))
        er = int(rng.choice([60, 70, 80, 90, 95])) if r.hr_pos else 0
        pr = int(rng.choice([0, 5, 10, 30, 50, 80])) if r.hr_pos else 0
        if r.hr_pos and er < 1:
            er = 50
        ihc, ish = ("3+", "") if rng.random() < 0.78 else ("2+", "Amplified")
        ki = r.ki67
        ki_txt = str(int(ki)) if rng.random() > 0.12 else ""
        if ki_txt and rng.random() < 0.03:
            ki_txt = ">90" if ki > 85 else f"{int(ki)}%"
        grade = "" if rng.random() < 0.06 else str(int(r.grade))
        menop = "Post" if r.age >= 52 or (r.age >= 46 and rng.random() < 0.4) else "Pre"
        stage = stage_group(r.ct, r.cn)
        registry.append(
            dict(
                chart_no=cno,
                sex="F",
                birth_date=birth.isoformat(),
                dx_date=dx.isoformat(),
                cT=r.ct,
                cN=r.cn,
                cM="M0",
                stage_ajcc8=stage,
                ER_pct=er,
                PR_pct=pr,
                HER2_IHC=ihc,
                HER2_ISH=ish,
                grade=grade,
                ki67=ki_txt,
                menopause=menop,
                ECOG=int(r.ecog),
                BMI=r.bmi,
                LVEF_baseline=int(r.lvef),
            )
        )

        # neoadjuvant orders
        cycles = neo_cycles(bool(r.hp), bool(r.anthracycline), t0, rng)
        orders += [dict(chart_no=cno, order_date=d.isoformat(), drug_name=nm, dose_mg=ds) for d, nm, ds in cycles]
        last_neo = max(d for d, _, _ in cycles)

        prog = bool(obs["prog"][i])
        pcr = bool(obs["pcr"][i])
        surg = None
        if not prog:
            surg = last_neo + timedelta(days=int(rng.integers(21, 45)))
            ypT, ypN = yp_stage(pcr, r, rng)
            surgery.append(
                dict(
                    chart_no=cno,
                    surgery_date=surg.isoformat(),
                    surgery_type=rng.choice(["Mastectomy", "Breast-conserving surgery"], p=[0.6, 0.4]),
                    ypT=ypT,
                    ypN=ypN,
                )
            )
            # adjuvant anti-HER2 to complete one year, or T-DM1 for residual disease
            adj_start = surg + timedelta(days=int(rng.integers(21, 40)))
            n_adj = 14 if pcr or not obs["tdm1"][i] else 14
            for k in range(n_adj):
                d = adj_start + timedelta(days=21 * k)
                if d > CUTOFF:
                    break
                if obs["tdm1"][i]:
                    orders.append(
                        dict(chart_no=cno, order_date=d.isoformat(), drug_name=pick(rng, "tdm1"), dose_mg=int(3.6 * 58))
                    )
                else:
                    orders.append(
                        dict(
                            chart_no=cno,
                            order_date=d.isoformat(),
                            drug_name=pick(rng, "trastuzumab"),
                            dose_mg=int(6 * 58),
                        )
                    )
                    if r.hp and not pcr and rng.random() < 0.5:
                        orders.append(
                            dict(chart_no=cno, order_date=d.isoformat(), drug_name=pick(rng, "pertuzumab"), dose_mg=420)
                        )

        # follow-up (years measured from t0)
        loss = -np.log(rng.random()) / 0.02  # ~2%/yr loss to follow-up
        admin = (CUTOFF - t0).days / 365.25
        cens = min(loss, admin)
        t_rec, t_death = obs["t_rec"][i], obs["t_death"][i]
        rec_date = t0 + timedelta(days=int(t_rec * 365.25)) if t_rec <= cens else None
        death_date = t0 + timedelta(days=int(t_death * 365.25)) if t_death <= cens else None
        if death_date and rec_date and rec_date > death_date:
            rec_date = None
        last = death_date or (t0 + timedelta(days=int(cens * 365.25)))
        rtype = ""
        if rec_date:
            rtype = "Distant" if obs["distant"][i] else rng.choice(["Local", "Regional"])
            if prog:
                rtype = "Progression before surgery"
        follow.append(
            dict(
                chart_no=cno,
                last_contact_date=last.isoformat(),
                recurrence_date=rec_date.isoformat() if rec_date else "",
                recurrence_type=rtype,
                death_date=death_date.isoformat() if death_date else "",
                vital_status="Dead" if death_date else "Alive",
            )
        )

    # ---- ineligible records the registry query also returns -------------------
    extra = 0

    def new_cno():
        nonlocal extra
        extra += 1
        return f"{chart[n + extra]:07d}"

    def clone_row(i, **kw):
        row = dict(registry[i])
        row.update(kw)
        row["chart_no"] = new_cno()
        return row

    idx = rng.choice(n, 70, replace=False)
    k = 0

    def take():
        nonlocal k
        k += 1
        return int(idx[k - 1])

    def copy_followup(src_i, cno):
        f = dict(follow[src_i])
        f["chart_no"] = cno
        follow.append(f)

    for _ in range(14):  # metastatic at diagnosis
        i = take()
        row = clone_row(i, cM="M1", stage_ajcc8="IV")
        registry.append(row)
        for d, nm, ds in neo_cycles(True, False, date.fromisoformat(row["dx_date"]) + timedelta(days=20), rng):
            orders.append(dict(chart_no=row["chart_no"], order_date=d.isoformat(), drug_name=nm, dose_mg=ds))
        copy_followup(i, row["chart_no"])
    for _ in range(11):  # HER2 not confirmed positive (IHC 2+, ISH not amplified)
        i = take()
        row = clone_row(i, HER2_IHC="2+", HER2_ISH="Not amplified")
        registry.append(row)
        copy_followup(i, row["chart_no"])
    for _ in range(18):  # upfront surgery, no neoadjuvant therapy
        i = take()
        row = clone_row(i)
        registry.append(row)
        s = date.fromisoformat(row["dx_date"]) + timedelta(days=int(rng.integers(14, 30)))
        surgery.append(
            dict(chart_no=row["chart_no"], surgery_date=s.isoformat(), surgery_type="Mastectomy", ypT="", ypN="")
        )
        copy_followup(i, row["chart_no"])
    for _ in range(9):  # neoadjuvant chemotherapy without anti-HER2
        i = take()
        row = clone_row(i)
        registry.append(row)
        t0 = date.fromisoformat(row["dx_date"]) + timedelta(days=20)
        for c in range(4):
            d = t0 + timedelta(days=21 * c)
            orders += [
                dict(
                    chart_no=row["chart_no"], order_date=d.isoformat(), drug_name=pick(rng, "epirubicin"), dose_mg=150
                ),
                dict(
                    chart_no=row["chart_no"],
                    order_date=d.isoformat(),
                    drug_name=pick(rng, "cyclophosphamide"),
                    dose_mg=900,
                ),
            ]
        copy_followup(i, row["chart_no"])
    for _ in range(7):  # surgery done elsewhere: no pathology on file
        i = take()
        row = clone_row(i)
        registry.append(row)
        for d, nm, ds in neo_cycles(
            bool(df.hp.iloc[i]), False, date.fromisoformat(row["dx_date"]) + timedelta(days=20), rng
        ):
            orders.append(dict(chart_no=row["chart_no"], order_date=d.isoformat(), drug_name=nm, dose_mg=ds))
        copy_followup(i, row["chart_no"])
    registry.append(clone_row(take(), sex="M"))  # male patient
    copy_followup(int(idx[k - 1]), registry[-1]["chart_no"])

    # ---- data-quality defects -------------------------------------------------
    reg = pd.DataFrame(registry)
    reg = pd.concat([reg, reg.sample(3, random_state=1)], ignore_index=True)  # exact duplicate rows
    reg.loc[reg.sample(1, random_state=2).index, "birth_date"] = "1900-01-01"  # placeholder birth date
    reg = reg.sample(frac=1, random_state=3).reset_index(drop=True)

    surg = pd.DataFrame(surgery)
    bad = surg[surg.ypT != ""].sample(2, random_state=4).index  # surgery dated before chemo
    for j in bad:
        surg.loc[j, "surgery_date"] = (
            date.fromisoformat(surg.loc[j, "surgery_date"]) - timedelta(days=400)
        ).isoformat()

    ords = pd.DataFrame(orders).sort_values(["chart_no", "order_date"]).reset_index(drop=True)
    fu = pd.DataFrame(follow)
    return (
        reg,
        ords,
        surg.sample(frac=1, random_state=5).reset_index(drop=True),
        fu.sample(frac=1, random_state=6).reset_index(drop=True),
    )


def stage_group(ct: str, cn: str) -> str:
    if ct.startswith("T4") or cn == "N3":
        return "IIIC" if cn == "N3" else "IIIB"
    if cn == "N2" or (ct == "T3" and cn == "N1"):
        return "IIIA"
    if (ct == "T2" and cn == "N1") or (ct == "T3" and cn == "N0"):
        return "IIB"
    if (ct == "T1c" and cn == "N1") or (ct == "T2" and cn == "N0"):
        return "IIA"
    return "IA"


def neo_cycles(hp: bool, anthra: bool, t0: date, rng) -> list:
    out = []
    era_phesgo = t0 >= date(2021, 6, 1)

    def her2(d):
        if hp and era_phesgo and rng.random() < 0.35:
            out.append((d, pick(rng, "phesgo"), 1800))
            return
        out.append((d, pick(rng, "trastuzumab"), 348))
        if hp:
            out.append((d, pick(rng, "pertuzumab"), 420))

    if anthra:
        for c in range(4):
            d = t0 + timedelta(days=21 * c)
            out += [(d, pick(rng, "epirubicin"), 150), (d, pick(rng, "cyclophosphamide"), 900)]
        for c in range(4):
            d = t0 + timedelta(days=84 + 21 * c)
            out.append((d, pick(rng, "docetaxel" if rng.random() < 0.6 else "paclitaxel"), 120))
            her2(d)
    else:
        for c in range(6):
            d = t0 + timedelta(days=21 * c)
            out += [(d, pick(rng, "docetaxel"), 120), (d, pick(rng, "carboplatin"), 600)]
            her2(d)
    return out


def yp_stage(pcr: bool, r, rng) -> tuple[str, str]:
    if pcr:
        return (rng.choice(["ypT0", "ypTis"], p=[0.7, 0.3]), "ypN0")
    t = rng.choice(["ypT1mi", "ypT1a", "ypT1b", "ypT1c", "ypT2", "ypT3"], p=[0.08, 0.12, 0.15, 0.25, 0.3, 0.1])
    nn = rng.choice(["ypN0", "ypN0(i+)", "ypN1mi", "ypN1a", "ypN2a"], p=[0.25, 0.05, 0.1, 0.4, 0.2])
    if t in ("ypT0",):
        nn = "ypN1a"
    # residual nodal disease only
    if rng.random() < 0.08:
        t, nn = "ypT0", "ypN1a"
    return t, nn


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="demo/simulate/out")
    ap.add_argument("--seed", type=int, default=SEED)
    a = ap.parse_args()
    out = Path(a.out)
    (out / "export").mkdir(parents=True, exist_ok=True)

    rng = np.random.default_rng(a.seed)
    df = simulate_cohort(rng, N_ELIGIBLE)
    po = potential_outcomes(df, rng)
    reg, ords, surg, fu = build_export(df, po, rng)

    files = {
        "registry_breast_her2.csv": reg,
        "chemo_orders.csv": ords,
        "surgery_pathology.csv": surg,
        "followup.csv": fu,
    }
    for name, d in files.items():
        d.to_csv(out / "export" / name, index=False)

    truth = truth_summary(df, po)
    obs_hp = df.hp.mean()
    truth["_meta"] = {
        "seed": a.seed,
        "n_eligible_simulated": N_ELIGIBLE,
        "share_HP_observed": round(float(obs_hp), 3),
        "pcr_logit": PCR_LOGIT,
        "efs_loghr": EFS_LOGHR,
        "efs_base": EFS_BASE,
        "export_sha256": {k: sha256(out / "export" / k) for k in files},
    }
    (out / "truth.json").write_text(json.dumps(truth, indent=2, ensure_ascii=False))
    print(json.dumps({k: v for k, v in truth.items() if not k.startswith("_")}, indent=1))
    print("rows:", {k: len(v) for k, v in files.items()})


if __name__ == "__main__":
    main()
