********************************************************************************
* 25_lookup.do -- append the three branches into the Outcome 2 conversion table
*
* WHAT THIS OWNS. Nothing but the append and the two column names a household join needs.
* Every decision was made upstream: 21 cut the size-based weights onto price points, 22
* took the price-quantity groups as the field built them, 23 gave each conventional case
* one weight, and 24 restated Branch P into each household month. This file puts them in
* one table and does not reason about any of them.
*
* ==============================================================================
* IT APPENDS RATHER THAN UNIFYING THE GRAIN, and that is deliberate
*
* Only Branch P has a month dimension: its grams are "what a fixed peso amount bought", so
* they move with the price level. Size-based and conventional grams are properties of an
* object and are the same in every month.
*
* A uniform case x month grain would repeat every size-based and conventional row once per
* month -- 12 times over -- and invite a reader to believe those rates were month-specific
* when 86% of them are not. The join is on case and month either way, so uniformity would
* buy nothing but redundant rows. `psps_month' is therefore MISSING on branches 1 and 3,
* and that missing is informative.
*
* ==============================================================================
* w_use AND v_use: the two columns a household is actually converted at
*
* Each branch supplies its weight under a different name because each earned it
* differently, and collapsing those names upstream would have hidden the difference. Here
* they become one pair, once:
*
*   branch 2  w_use = w_g_m   the restated weight, at the household's own month
*   branch 3  w_use = w_g     the group's median, no restatement (assumption 3)
*   branch 1  w_use = w_g     the case median, no price dimension at all
*
* v_use = p_g / w_use, PHP per gram. 28_match_and_convert.do converts at p_h / v_use and
* breaks ties on v_use rather than on the price point -- see the methodology, Step B2: the
* two coincide only if v falls monotonically across the ladder, and nothing guarantees
* that, because v is a ratio of two independently measured quantities.
*
* ==============================================================================
* TWO FILES, and the second one is issue #11
*
*   outcome2_lookup.dta               inflation applied on Branch P
*   outcome2_lookup_noinflation.dta   Branch P at its measured weight, NO month dimension
*
* #11 asks how much the PSPS households' grams move if inflation is not accounted for.
* Answering it needs a lookup built the other way, not a switch inside the main one -- so
* the variant is a file, and comparing them is a diagnostic rather than a build step.
*
* The no-inflation variant DROPS the month dimension rather than keeping it and setting
* the factor to 1: without a restatement there is nothing month-specific left on any
* branch, so a month column would be 12 copies of one number. That makes the variant a
* genuinely case-level table, which is what #11 asks for.
*
* ==============================================================================
* INPUTS  ${btemp}\branch_size_based.dta         21
*         ${btemp}\branch_price_quantity.dta     22   (for the no-inflation variant)
*         ${btemp}\branch_price_quantity_m.dta   24   (for the main one)
*         ${btemp}\branch_conventional.dta       23
* OUTPUTS ${bdeliv}\outcome2_lookup.dta
*         ${bdeliv}\outcome2_lookup_noinflation.dta
*         ${bdeliv}\outcome2_lookup.csv
*
* RUN, from the dofiles/ folder:
*   "C:\Program Files\StataNow19\StataSE-64.exe" -e do 20_psps_retrofitting\25_lookup.do
********************************************************************************

clear all
do "00_shared/00_globals.do"

local keyvars pull_province pull_municipal_city pull_item harmonized_nsu_unit corrected_unit


********************************************************************************
**# 1. The main lookup
********************************************************************************

use "${btemp}\branch_price_quantity_m", clear
gen double w_use = w_g_m
gen double v_use = v_g_m
keep `keyvars' branch group_id psps_month p_g w_g w_use v_use n_g n_points ///
     n_disputed n_uncertain ///
     hetero_code infl_factor n_cpi_vals
gen byte d_point_usable = 1
gen byte d_reclassified = 0
tempfile lk_p
save "`lk_p'"

use "${btemp}\branch_size_based", clear
gen double w_use = w_g
gen double v_use = v_g
keep `keyvars' branch group_id p_g w_g w_use v_use n_g n_points ///
     n_disputed n_uncertain ///
     d_point_usable unusable_why d_reclassified k_use n_filled n_empty conv_rank
tempfile lk_s
save "`lk_s'"

use "${btemp}\branch_conventional", clear
gen double w_use = w_g
gen double v_use = .
keep `keyvars' branch group_id p_g w_g w_use v_use n_g n_points d_reclassified ///
     n_disputed n_uncertain
gen byte d_point_usable = 1
tempfile lk_c
save "`lk_c'"

use "`lk_s'", clear
append using "`lk_p'"
append using "`lk_c'"

replace d_point_usable = 1 if missing(d_point_usable)
replace unusable_why   = "" if d_point_usable == 1

* ---- invariants, the same discipline as 12_publish_reference_set.do section 5c --------
* Every claim the table makes about itself, asserted on every row that carries it.

* The month dimension belongs to Branch P and to nothing else.
assert missing(psps_month) if branch != 2
assert !missing(psps_month) if branch == 2

* A conventional row has no price dimension. Not "happens to be missing" -- there is
* nothing for a price point to be a point OF on that branch.
assert missing(p_g) & missing(v_use) if branch == 1
assert !missing(p_g) if branch != 1

* A usable row converts; an unusable one is a matchable price with no weight, and must
* carry a reason so a household can be told why rather than just given nothing.
assert !missing(w_use) & w_use > 0 if d_point_usable == 1
assert missing(w_use) & unusable_why != "" if d_point_usable == 0
assert d_point_usable == 1 if branch != 3

* v_use is the rate the conversion actually runs at, so it must agree with the two columns
* it is built from wherever both exist. A drift here would convert at one number and
* report another.
assert reldif(v_use, p_g / w_use) < 1e-9 if !missing(v_use)

* Only Branch S can hold a reclassified case: #28 moves cells from conventional to
* size-based and nowhere else.
assert branch == 3 if d_reclassified == 1

* ---- the uncertainty counts arrived from all three branches (#35) --------------------
* THIS ASSERTION IS THE POINT OF THE THREE `keep' EDITS ABOVE. `append' fills a column
* absent from one of the appended files with MISSING, silently -- so dropping
* n_uncertain from one branch's keep list would not error, and every row of that branch
* would arrive with no uncertainty recorded. Downstream that reads as "nothing behind
* this weight was questioned", which is the strongest possible claim, made by accident,
* about a third of the table.
*
* So: wherever there is a weight, there must be a count of how much of it was questioned.
assert !missing(n_uncertain) if !missing(n_g)
assert !missing(n_disputed)  if !missing(n_g)

* And the converse. A row with no weighings behind it -- Branch S's unusable points --
* must NOT carry a zero, which would read as "none of its weighings was questioned"
* about a set of weighings that does not exist.
assert missing(n_uncertain) if missing(n_g)

* Bounded by the weighings they count within, and the OR is between the max of its parts
* and their sum. Re-stated here because the append is what could break it.
assert n_uncertain <= n_g if !missing(n_g)
* n_uncertain counts exactly the disputed weighings since d_step1_flagged was retired in
* 08_branch.do. Left as two bounds rather than one equality so a future third component
* is caught here rather than silently absorbed.
assert n_uncertain >= n_disputed if !missing(n_g)
assert n_uncertain <= n_disputed if !missing(n_g)

gen double share_uncertain = n_uncertain / n_g
assert inrange(share_uncertain, 0, 1) if !missing(share_uncertain)
format share_uncertain %5.3f

* Read per branch, because that is the cut at which a column lost in a `keep' would show
* up as a suspiciously clean zero.
di as res _n "share of weighings questioned, by branch (#35):"
table branch, statistic(frequency) statistic(mean share_uncertain) nformat(%9.3f)

* One row per (case x group), plus a month on Branch P. If this is not unique, a household
* join will multiply rows and every total built on it will be wrong.
*
* `missok' IS REQUIRED, and the missings in this key are the table's structure rather than
* a defect: psps_month is missing off Branch P, p_g is missing on Branch C, and group_id
* is missing on a matchable point that has no group. Without missok, isid refuses the key
* outright and says nothing about uniqueness.
*
* p_g IS IN THE KEY because group_id alone does not separate the unusable rows: two refused
* points in one sub-cell both carry group_id missing. Their prices are distinct -- the
* PHP 20 merge collapsed equal values -- and a point's price is disjoint from every group's,
* since an unusable row is by definition a point no group took.
isid `keyvars' branch group_id psps_month p_g, missok

label var w_use "grams (or mL) per NSU this row converts at -- restated on Branch P only"
label var v_use "PHP per gram; a household receives p_h / v_use grams per NSU"
label var branch "1 conventional, 2 price-quantity, 3 size-based (see 08_branch.do)"
label var n_disputed      "weighings behind w_g where the two snap rules disagreed"
label var n_uncertain     "weighings behind w_g that are disputed or anchor-flagged"
label var share_uncertain "n_uncertain / n_g; 1 = nothing behind this weight went unquestioned"

* THE THIN FLAG, on the count that stands behind w_g. Published rather than acted on:
* a thin point is kept and marked, never sent up the ladder (#31, 2026-09-16). Missing on
* an unusable point, which has no weight to be thin about. One definition, in 00_globals.
gen_d_thin n_g

def_hetero
label values hetero_code hetero
label define branchlbl 1 "conventional" 2 "price-quantity" 3 "size-based", replace
label values branch branchlbl

compress
sort `keyvars' branch group_id psps_month
save "${bdeliv}\outcome2_lookup", replace
export delimited using "${bdeliv}\outcome2_lookup.csv", replace

di as res _n "rows by branch:"
tab branch, m
di as res _n "rows a household can convert at:"
tab d_point_usable, m
di as res _n "the unusable ones:"
tab unusable_why if d_point_usable == 0


********************************************************************************
**# 2. The no-inflation variant (#11)
********************************************************************************
* Identical except that Branch P supplies its MEASURED weight and loses its month
* dimension. Built from 22's output rather than from 24's, so it is not a filtered copy of
* a restated table -- there is no month to filter to.

use "${btemp}\branch_price_quantity", clear
gen double w_use = w_g
gen double v_use = v_g
keep `keyvars' branch group_id p_g w_g w_use v_use n_g n_points hetero_code ///
     n_disputed n_uncertain
gen byte d_point_usable = 1
gen byte d_reclassified = 0
tempfile nk_p
save "`nk_p'"

use "`lk_s'", clear
append using "`nk_p'"
append using "`lk_c'"
replace d_point_usable = 1 if missing(d_point_usable)
replace unusable_why   = "" if d_point_usable == 1

assert !missing(w_use) & w_use > 0 if d_point_usable == 1
isid `keyvars' branch group_id p_g, missok

* The counts must survive into this variant too, and for a sharper reason than symmetry:
* #11 compares the household grams the two lookups produce, and a comparison in which one
* side carries the uncertainty and the other does not would attribute a difference in
* bookkeeping to the inflation adjustment.
assert !missing(n_uncertain) if !missing(n_g)
gen double share_uncertain = n_uncertain / n_g
format share_uncertain %5.3f

label var w_use "grams per NSU, NO inflation adjustment anywhere -- issue #11's variant"
label var n_disputed      "weighings behind w_g where the two snap rules disagreed"
label var n_uncertain     "weighings behind w_g that are disputed or anchor-flagged"
label var share_uncertain "n_uncertain / n_g; 1 = nothing behind this weight went unquestioned"
gen_d_thin n_g
label values branch branchlbl
compress
sort `keyvars' branch group_id
save "${bdeliv}\outcome2_lookup_noinflation", replace
export delimited using "${bdeliv}\outcome2_lookup_noinflation.csv", replace

qui count
di as res _n "{hline 78}"
di as res "25_lookup.do done"
di as res "  ${bdeliv}\outcome2_lookup.dta              (with inflation, month dimension)"
di as res "  ${bdeliv}\outcome2_lookup_noinflation.dta  " r(N) " row(s), case-level (#11)"
di as res ""
di as res "  The two differ ONLY on Branch P. Comparing the household grams they"
di as res "  produce is what #11 asks for, and it is a diagnostic, not a build step."
di as res "{hline 78}"
