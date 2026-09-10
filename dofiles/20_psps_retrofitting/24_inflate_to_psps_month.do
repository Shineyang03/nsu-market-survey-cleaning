********************************************************************************
* 24_inflate_to_psps_month.do -- put Branch P's weights in the household's price frame
*
* WHAT THIS OWNS. One branch, and one column. On the price-quantity branch w_g is "what a
* fixed peso amount bought AT THE PRICE LEVEL OF THE MONTH IT WAS SPENT", so it is the
* only weight in this project that is not a property of an object. Comparing it with a
* household interviewed in a different month means restating it. This file does that, for
* every month that actually occurs in the municipality.
*
* THE OTHER TWO BRANCHES ARE NOT TOUCHED, and that is a statement rather than an omission.
* A size-based or conventional weight is the mass of a thing the enumerator was handed --
* a medium mango weighs what it weighs -- so there is no price level inside the
* measurement and nothing for an index to adjust. `cpi_factor' is exactly 1 on those rows
* by construction, asserted in 07_cpi_factor.do. Inflation here is a BRANCH PROPERTY, not
* a global step: it reaches 368 of the 2,530 groups in the lookup.
*
* ==============================================================================
* THE ARITHMETIC, and the direction, which inverts easily
*
*   cpi_factor_g = CPI(m_ms) / CPI(REF)          built by 07_cpi_factor.do, REF = 2026m4
*
*   w_g_m = w_g * CPI(m_ms) / CPI(m_psps)
*         = w_g * cpi_factor_g * CPI(REF) / CPI(m_psps)
*
* REF cancels algebraically, which is why it is a bookkeeping anchor and not a modelling
* choice: any reference month gives the same w_g_m.
*
* DIRECTION CHECK, spelled out because getting it backwards is silent. PSPS ran
* 2023m12-2025m1 and the market survey 2026m3-m5, so CPI(m_psps) < CPI(m_ms) for almost
* every cell. The ratio therefore EXCEEDS 1, w RISES, and v = p/w FALLS: the same peso
* bought MORE grams when prices were lower. If a run shows w_g_m below w_g across the
* board, the ratio is upside down.
*
* THE ADJUSTMENT IS APPLIED TO THE WEIGHT, NEVER TO A PRICE, and every p_g in the system
* stays at its nominal PSPS-round value. Adjusting the weight up by (1+pi) and deflating
* the price by (1+pi) are the same operation, but putting it on the weight means no column
* needs a frame label and no two rows can be silently compared across frames. Two ways to
* get this wrong, both recorded in the methodology: adjusting the size-based price points
* (which are a PSPS statistic joined on afterwards, so deflating them corrupts the MATCH
* as well as the level), and adjusting one side of a comparison but not the other.
*
* pi CANNOT BE SET TO ZERO, and #11 is the sensitivity that measures what it is worth.
* The median correction across province x group is +7.4% and the range runs -18.1% to
* +58.1%; six of sixteen groups moved the OTHER WAY over this window, and signs flip
* within a group across provinces -- leafy vegetables fell 9.4% in Iloilo and rose 58.1%
* in Antique. So no scalar can stand in for it, and dropping it is not the neutral choice:
* it biases every price-quantity household in a cell in a KNOWN direction that differs by
* item. 25_lookup.do builds the no-inflation variant so the two can be compared.
*
* ==============================================================================
* INPUTS  ${btemp}\branch_price_quantity.dta   Branch P groups, with cpi_factor_g
*         ${btemp}\psps_months.dta             months occurring in each municipality (20a)
*         ${tables}\cpi_level_panel.csv        province x item-group x month CPI
* OUTPUT  ${btemp}\branch_price_quantity_m.dta   one row per group x PSPS month
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\24_inflate_to_psps_month.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

local ref_month = tm(2026m4)


********************************************************************************
**# 1. Every Branch P group, crossed with the months of its own municipality
********************************************************************************
* NOT every month in the sample. A group only needs restating to months in which a
* household in that municipality was actually interviewed, and PSPS fielding is bimodal
* and province-dependent -- Aklan appears only in the early wave, Negros Occidental only
* in the late one. Crossing with all 12 months would triple the table with rows no
* household can ever join to.

use "${btemp}\branch_price_quantity", clear
qui count
di as res _n "Branch P groups in: " r(N)

joinby pull_province pull_municipal_city using "${btemp}\psps_months", unmatched(master) _merge(_m_mon)

* A municipality with market-survey weighings but no PSPS interviews has no household to
* convert. Reported, not dropped silently, because the reverse -- a PSPS municipality with
* no weighings -- is the fallback's business and this is its mirror image.
qui count if _m_mon == 1
if r(N) > 0 {
	di as res "groups in a municipality with no PSPS interview month: " r(N)
	preserve
		keep if _m_mon == 1
		egen byte _t = tag(pull_province pull_municipal_city)
		qui count if _t
		di as res "  municipalities: " r(N)
	restore
	drop if _m_mon == 1
}
drop _m_mon

qui count
di as res "group x month rows: " r(N)


********************************************************************************
**# 2. The CPI at REF and at the household's month
********************************************************************************
* ASCII-SAFE JOIN KEY, the same fix 07_cpi_factor.do made and for the same reason. 189
* weighings carry an item_group whose label contains an e-acute; it used to be the merge
* key, both sides were written by the same step so they matched byte for byte, and nothing
* made that robust. Every item_group begins with a distinct COICOP code containing only
* digits and dots, so the code is the key and no non-ASCII character is in it at all.

gen str24 item_group_code = ""
quietly replace item_group_code = ustrregexs(1) if ustrregexm(item_group, "^([0-9]+(\.[0-9]+)*)")
qui count if mi(item_group_code)
if r(N) > 0 {
	di as err "ERROR: " r(N) " row(s) have an item_group with no leading COICOP code."
	di as err "Fix the label in cpi_item_crosswalk.csv; do not merge on the label."
	exit 459
}

preserve
	import delimited "${tables}\cpi_level_panel.csv", clear varnames(1) encoding("utf-8")
	gen str24 item_group_code = ""
	quietly replace item_group_code = ustrregexs(1) if ustrregexm(item_group, "^([0-9]+(\.[0-9]+)*)")
	assert !mi(item_group_code)
	isid province item_group_code mdate
	rename province pull_province
	keep pull_province item_group_code mdate cpi
	tempfile cpipanel
	save "`cpipanel'"
restore

* --- CPI at the household's interview month ---
gen mdate = psps_month
format mdate %tm
merge m:1 pull_province item_group_code mdate using "`cpipanel'", keep(1 3) ///
	keepusing(cpi) generate(_m_psps)
rename cpi cpi_at_psps
* Every month that reaches here came from a PSPS interview, and the panel covers
* 2023m12-2026m5, so a non-match is a coverage hole in the CPI rather than a stray month.
assert _m_psps == 3
drop mdate _m_psps

* --- CPI at REF ---
gen mdate = `ref_month'
format mdate %tm
merge m:1 pull_province item_group_code mdate using "`cpipanel'", keep(1 3) ///
	keepusing(cpi) generate(_m_ref)
rename cpi cpi_at_ref
assert _m_ref == 3
drop mdate _m_ref item_group_code


********************************************************************************
**# 3. Restate
********************************************************************************

gen double w_g_m = w_g * cpi_factor_g * cpi_at_ref / cpi_at_psps
gen double v_g_m = p_g / w_g_m

* The composed factor, kept so the size of the adjustment stays visible on the row rather
* than only in this log.
gen double infl_factor = cpi_factor_g * cpi_at_ref / cpi_at_psps

label var w_g_m       "grams that peso amount would have bought at the household's month"
label var v_g_m       "PHP per gram at the household's month"
label var infl_factor "w_g_m / w_g -- the whole MS -> PSPS restatement, CPI(m_ms)/CPI(m_psps)"
label var psps_month  "PSPS interview month this row is for"

* DIRECTION, ASSERTED. PSPS ran 2023m12-2025m1 and the market survey 2026m3-m5, so the
* CPI at the household's month is below the CPI at the weighing's month for all but a
* handful of province x group series that fell. The factor is therefore above 1 in the
* large majority, and if it were below 1 across the board the ratio would be inverted.
* Asserted as a MAJORITY rather than universally, because six of sixteen COICOP groups
* genuinely moved the other way over this window and rice fell 6.8% -- a universal
* assertion here would fire on real deflation.
qui count if infl_factor > 1
local n_up = r(N)
qui count
local n_all = r(N)
di as res _n "restatement factor above 1 (weights rise): `n_up' of `n_all'"
if `n_up' * 2 < `n_all' {
	di as err "ERROR: the restatement lowers the weight on most rows."
	di as err "PSPS precedes the market survey, so it should raise it. The ratio is inverted."
	exit 459
}

qui su infl_factor, detail
di as res "  factor -- min " %5.3f r(min) "  p25 " %5.3f r(p25) "  median " %5.3f r(p50) ///
	"  p75 " %5.3f r(p75) "  max " %5.3f r(max)
qui count if infl_factor < 1
di as res "  rows where it FALLS (real deflation for that province x group): " r(N)

* A restated weight must still be a weight.
assert w_g_m > 0 & !missing(w_g_m)

compress
sort pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit ///
	group_id psps_month
save "${btemp}\branch_price_quantity_m", replace

di as res _n "{hline 78}"
di as res "24_inflate_to_psps_month.do done -- " _N " group x month row(s)"
di as res "  w_g is kept alongside w_g_m so 25_lookup.do can build #11's"
di as res "  no-inflation variant from the same file."
di as res "{hline 78}"
