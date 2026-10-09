"""Compare the agent's estimates (results/) with the simulation's known truth.

    uv run --no-project --with pandas python demo/truth_compare.py > demo/TRUTH.md

truth.json comes from `make demo-data` (demo/simulate/out/). Every patient was
simulated under BOTH regimens with the same random draws, so the true effects
are known exactly -- something a real study never has.
"""

import json
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
truth = json.loads((ROOT / "demo/simulate/out/truth.json").read_text())
pcr = pd.read_csv(ROOT / "results/outcomes_pcr.csv").set_index("analysis")
surv = pd.read_csv(ROOT / "results/outcomes_survival.csv")
main = {e: surv[(surv.endpoint == e) & (surv.analysis == "main")].iloc[0] for e in ("EFS", "OS")}
desc = pcr.loc["main"]
d = pd.read_csv(ROOT / "results/outcomes_descriptive.csv")
n_pcr = {g: float(d[(d.item == "pcr_n") & (d.group == g)].value.iloc[0]) for g in ("dual", "single")}
crude = n_pcr["dual"] / desc.n_dual - n_pcr["single"] / desc.n_single


def pct(x: float) -> str:
    return f"{100 * x:+.1f}%" if x == x else "—"


def covers(lo: float, hi: float, t: float) -> str:
    return "✅ 涵蓋" if lo <= t <= hi else "❌ 未涵蓋"


rows = [
    (
        "pCR 差異（雙標靶 − 單標靶）",
        "粗略比較（未調整）",
        f"{pct(crude)}（{int(n_pcr['dual'])}/{int(desc.n_dual)} vs {int(n_pcr['single'])}/{int(desc.n_single)}）",
        pct(truth["pcr_risk_difference_ATO"]),
        "差很多：被年代混淆",
    ),
    (
        "pCR 差異（雙標靶 − 單標靶）",
        "重疊加權（主分析）",
        f"{pct(desc.rd)}（95% CI {pct(desc.rd_lo)} 至 {pct(desc.rd_hi)}）",
        pct(truth["pcr_risk_difference_ATO"]),
        covers(desc.rd_lo, desc.rd_hi, truth["pcr_risk_difference_ATO"]),
    ),
    (
        "pCR 勝算比",
        "重疊加權（主分析）",
        f"{desc['or']:.2f}（{desc.or_lo:.2f}–{desc.or_hi:.2f}）",
        f"{truth['pcr_odds_ratio_marginal']:.2f}",
        covers(desc.or_lo, desc.or_hi, truth["pcr_odds_ratio_marginal"]),
    ),
]
for ep, key in (("EFS", "efs"), ("OS", "os")):
    m = main[ep]
    rows.append(
        (
            f"{ep} 風險比（HR）",
            "重疊加權（主分析）",
            f"{m.hr:.2f}（{m.hr_lo:.2f}–{m.hr_hi:.2f}）",
            f"{truth[f'{key}_marginal_HR_5y']:.2f}",
            covers(m.hr_lo, m.hr_hi, truth[f"{key}_marginal_HR_5y"]),
        )
    )
    rows.append(
        (
            f"5 年 {ep} 差異",
            "重疊加權（主分析）",
            pct(m.s5_dual - m.s5_single),
            pct(truth[f"{key}_5y_difference_ATO"]),
            "點估計（無 CI）",
        )
    )

print("# AI 估計值 vs. 模擬真值\n")
print("> 由 `demo/truth_compare.py` 產生。真值來自 `make demo-data` 的 `demo/simulate/out/truth.json`。\n")
print(
    "模擬資料時，每位病人都**同時**以兩種治療各模擬一次（共用同一組隨機數），所以「如果全部用雙標靶 vs. 全部用單標靶」"
)
print("的真正差別是已知的。真實研究永遠拿不到這個答案；教學示範拿得到，正好用來檢查 AI 選的方法有沒有估對。\n")
print("| 指標 | 方法 | AI 的估計（results/） | 真值 | 判讀 |")
print("|---|---|---|---|---|")
for r in rows:
    print("| " + " | ".join(r) + " |")
print("""
## 怎麼讀這張表

- **粗略比較會騙人。** 不調整時，雙標靶的 pCR 只比單標靶高一點點；真值約高 15 個百分點。
  原因是兩種治療用在不同年代，單標靶組又恰好「運氣比較好」——這正是第 14 章 AI 說「兩組本來就不一樣」的意思。
- **重疊加權把答案拉回來了。** 主分析的 pCR 差異與勝算比都很接近真值，95% 信賴區間涵蓋真值。
- **存活的信賴區間很寬。** EFS、OS 的點估計方向與真值一致，但事件數少、加權後有效樣本小，
  所以 AI 在論文裡寫「資料不足以評估存活」——這是正確的保守說法，不是失敗。
- 真值的「重疊加權母群」用模擬時的真實傾向分數計算，涵蓋模擬的全部 640 位符合條件者（含後來因第 I 期被排除者），
  與研究實際納入的 615 人略有不同；HR 的真值是 5 年內的邊際 HR（全體），僅供方向與量級比較。
""")
