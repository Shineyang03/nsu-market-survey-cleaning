********************************************************************************
* 03a_block_reading.do -- the BLOCK READING, computed before anything harmonizes
*
* WHAT IT IS. The typed weight expressed in canonical units -- grams for mass,
* millilitres for volume -- with the kg/g/L tick treated as unreliable. It is a pure
* function of three things: the raw `weight', the raw `unit' tick, and `KGMAX'. It
* consults no other observation, no pool, no median, and no harmonized unit.
*
* WHY IT LIVES HERE, AND NOT WHERE IT USED TO. This computation was STEP 3a-3d of
* 04_unit_snap.do, which runs AFTER 03_clean_ms.do merges the harmonization crosswalk.
* Nothing about it depended on that merge, but its POSITION meant a reader had to trace
* the code to establish as much -- and one consumer of it, the fold test, exists
* precisely to answer a question that must not depend on the harmonization:
*
*     Do two raw labels folded into one harmonized_nsu_unit actually weigh the same?
*
* The published weight cannot answer that. 04_unit_snap.do snaps it toward the median of
* a pool keyed on harmonized_nsu_unit, so two labels folded TOGETHER are snapped toward
* one median -- which nudges the test toward "they weigh the same", which is what
* justified folding them. Measured: on the published weights the crackers
* bilog/`pieces or units' fold fails its own test (p=0.043); on block readings it passes
* (p=0.220) with an identical size-controlled ratio of 0.62. The failure was an artifact
* of the input, not a property of the fold.
*
* Keying the snap on the raw label instead does not fix this -- it swaps the bias for
* the opposite one, pooling each label separately and so pushing folded labels apart.
* Measured: fresh fish bilog/binilog, which IS folded, then fails at p=0.041 with the
* ratio dropping 0.74 -> 0.50. The block reading is the only input with no grouping bias
* in either direction, and the only one under which no folded group contradicts itself.
*
* So the order is now, and must stay:
*
*     00a  raw                       -> durable weighing ids
*     03   raw prep                  -> obs_type, hetero type, comments  (no folds yet)
*     03a  THIS FILE                 -> w_block          <- reads only weight, unit
*     ---- the fold evidence is complete at this line, and is provably independent ----
*     01   crosswalk + fold carve-outs -> harmonized_nsu_unit
*     03   merge, then 04 snap        -> published corrected_weight
*     05   hand corrections
*
* Everything above the line can be recomputed without knowing a single fold decision.
* That is the property the ordering exists to make visible; see dofiles/README.md,
* "Two different loops".
*
* CALLED BY   00_shared/03_clean_ms.do, immediately after the raw MS prep and BEFORE
*             the crosswalk merge. Parameters are passed as globals, mirroring
*             04_unit_snap.do:
*
*                 global block_in  "<dataset holding raw weight, unit and id>"
*                 global block_out "<where to save id + w_block>"
*                 do "00_shared/03a_block_reading.do"
*
* OUTPUT      ${block_out}.dta with one row per weighing: id, w_block.
*             04_unit_snap.do merges this in rather than recomputing it, so the rule has
*             exactly one definition. Diagnostics read w_block off the build for the same
*             reason -- see the note in 04's save block.
********************************************************************************

if "${block_in}" == "" {
	di as err "03a_block_reading.do: \${block_in} is not set."
	di as err "It must name a dataset holding id, weight and unit. See the header."
	exit 198
}
if "${block_out}" == "" {
	di as err "03a_block_reading.do: \${block_out} is not set."
	exit 198
}

use "${block_in}", clear

* The three columns this step is allowed to see. Asserting on them is not ceremony:
* the whole claim of this file is that it reads nothing else, and a silent rename
* upstream would turn that claim false without breaking anything visibly.
foreach v in id weight unit {
	capture confirm variable `v'
	if _rc {
		di as err "03a_block_reading.do: `v' not found in ${block_in}."
		exit 111
	}
}
isid id

* KGMAX LIVES HERE NOW, because this is the only place that uses it. It was a local in
* 04_unit_snap.do; moving the computation without moving the threshold would have left
* two files disagreeing about where the rule is defined.
*
* kg: at or below this a "kg" tick is believed; above it the number is read as grams
* mis-ticked as kg. Empirically clean on this data -- the only kg rows in (20,30] are
* three 25 kg rice sacks, and (30,50] is empty. That emptiness is an accident of the
* vintage and not a guarantee: see docs/implicit_assumptions.md.
local KGMAX = 30

* ---- A ZERO WEIGHT IS NOT A READING -------------------------------------------
* THIS GUARD IS NOT OPTIONAL, and getting it wrong is the one way moving this
* computation upstream can change a published number.
*
* When the block reading lived in 04_unit_snap.do it ran on data that 03_clean_ms.do had
* already passed through `replace weight = .c if weight == 0'. So a zero-weight row
* arrived as an extended missing, `!missing(weight)' was false, and its block reading
* stayed missing. Here -- upstream of that line -- the same row still holds a literal 0,
* `!missing(0)' is true, and the grams branch below would publish 0*1000 = 0.
*
* A w_block of 0 is not harmless. STEP 3e's plausibility gate rejects anything under
* WFLOOR and substitutes the other candidate, so a spurious zero silently rewrites
* corrected_weight. Measured when this guard was missing: 48 block readings moved and
* corrected_weight moved with them.
*
* Expressed as STEP 1 expresses it -- `!(weight>0 & weight<.)' also catches negatives and
* every flavour of missing, rather than testing for 0 alone.
gen byte _usable = (weight > 0 & weight < .)
count if !_usable
di as txt "03a: " r(N) " row(s) have no usable weight (zero, negative or missing)"

* --- unit==2 (grams): decimal / same-input-same-output consistency -------------
*   weight >= 10 : already plausible grams          -> read as typed
*   weight <  10 : kg-magnitude misentry            -> read as kg
gen double w_block = .
replace w_block = cond(weight>=10, weight, weight*1000) if unit==2 & _usable

* --- litres. Same premise in the volume dimension: a litre tick at 10 or above is
*   read as ALREADY millilitres. A genuine 20 L reading would become 20 mL here --
*   silently divided by a thousand, with no error and nothing downstream able to tell.
*   The band is guarded below; see the LITRE BAND GUARD after the decimal repair.
replace w_block = cond(weight>=10, weight, weight*1000) if unit==3 & _usable

* --- THE MISPLACED DECIMAL: a sub-0.01 litre entry is not a reading -----------------
* The rule above would turn 0.001215 L into 1.215 mL. There is no 1 mL bottle of
* liquor, no 2 mL glass of drink and no 1 mL tub of ice cream. The typed number is the
* intended value with the decimal point three places too far left, so the repair is to
* move it back and then apply the litre conversion -- one multiplication by 10^6.
*
*     0.001215  ->  1.215 L  ->  1,215 mL     (a long-neck bottle)
*     0.001175  ->  1.175 L  ->  1,175 g      (a whole chicken)
*     0.001250  ->  1.250 L  ->  1,250 mL     (an ice cream tub)
*
* WHY THIS BELONGS HERE AND NOT IN THE SNAP. These 41 rows used to reach 04 with an
* impossible block reading, and 04 repaired them by asking a local median which decade
* to use. That produced TWO answers for ONE pattern -- 26 rows multiplied by 10^5 and
* 14 by 10^6, decided by whichever decade the nearest pool median happened to sit in --
* and of the 34 with a comparable item range, the result landed inside it on exactly 1.
* A misplaced decimal is a property of the typed number, not of the neighbourhood, so it
* is repaired where the typed number is read. After this branch no block reading in the
* build falls outside the plausibility bounds.
*
* THE BOUND IS EMPIRICAL AND THE POPULATION IS HOMOGENEOUS. Every row below 0.01 in
* this vintage carries a litre tick -- there is not one gram or kilogram entry beneath
* it -- and the raw values run 0.00116 to 0.007 with the next litre entry at 0.010.
* The assert below fails if either of those stops being true, because a sub-0.01 GRAM
* entry would mean something different and must not be swept up by this rule.
* NOTE THE float() WRAPPER, and do not remove it. `weight' is a float, and 0.01 is not
* exactly representable: the float nearest 0.010 is 0.00999999977, so a bare
* `weight < 0.01' compares a float against a DOUBLE literal and is TRUE for every row
* that recorded 0.010. Those rows are the refilled water containers, which read 1 L and
* are handled by 05_manual_corrections.do sec 3 on the value 10. Swept up here they
* became 10,000 instead, sec 3 then matched nothing, and its own tripwire stopped the
* build -- which is the only reason this was caught rather than shipped.
count if _usable & weight < float(0.01) & unit != 3
if r(N) > 0 {
	di as err "03a_block_reading.do: " r(N) " sub-0.01 row(s) carry a non-litre tick."
	di as err "The misplaced-decimal repair is defined for litres only. Adjudicate them."
	exit 459
}
count if _usable & weight < float(0.01) & unit == 3
di as txt "03a misplaced decimal (sub-0.01 litres, read x10^6): " r(N) " row(s) matched"
replace w_block = weight * 1000000 if unit==3 & weight < float(0.01) & _usable

* ============ LITRE BAND GUARD ======================================================
* THE CLAIM: no litre-ticked reading at 10 or above is a GENUINE litre reading.
*
* WHY IT NEEDS A GUARD AT ALL. The litre branch above reads such a row as millilitres.
* If one is ever a real litre entry the published weight is a thousandth of the truth,
* and nothing else in the pipeline can notice: 20 mL is inside the plausibility bounds,
* inside every pool, and indistinguishable from a sachet. The failure is SILENT, which
* is the only kind worth a tripwire.
*
* THIS USED TO BE PROTECTED BY ACCIDENT. The one cell that held real litre readings --
* mineral water -- leaves the build later, at the non-NSU exclusion, for reasons that
* have nothing to do with this rule. A vintage that keeps it, or that adds bulk cooking
* oil, walks straight into the failure. Accidental protection is not protection.
*
* THE TEST, and why it is keyed on the item rather than on the number. There is no way
* to tell a real 20 L entry from a real 20 mL entry by looking at 20: packaging sizes
* and bulk volumes overlap in this band (ice cream is typed both as 0.045 and as 45,
* meaning 45 mL both times). What DOES separate them is the item's own scale, and the
* item supplies it for free -- its sub-10 litre rows are unambiguous, so their converted
* values say what a millilitre reading of that item looks like. A genuine litre entry
* read as millilitres lands orders of magnitude BELOW that; a real millilitre entry
* lands beside it.
*
* THE CONSTANT. 1.5 decades below the item's own median. Measured on this vintage the
* margin is wide in both directions, which is what makes the threshold safe rather than
* lucky:
*
*     item                      median of its <10 rows      lowest >=10 row      ratio
*     liquor                              375 mL                   335 mL        0.893
*     crackers                            215 mL                    85 mL        0.395
*     ice cream                           100 mL                    35 mL        0.350
*     preserved meat                      458 mL                   150 mL        0.328
*     ---- threshold 1/10^1.5 ------------------------------------------------- 0.0316
*     a 20 L mineral-water entry         6,800 mL                (20 mL)         0.0029
*
* The nearest real row sits a factor of ten ABOVE the threshold and the counter-example
* a factor of ten below it. Nothing fires today; see docs/implicit_assumptions.md A7.
*
* An item with NO sub-10 litre rows has no scale to be judged against -- beer is the
* only one -- so it is reported rather than tested. Reported, not silently skipped.
local LITDEC = 10^1.5

tempvar lhi llo lomed nlo lrat
gen byte `lhi' = (unit == 3 & _usable & weight >= 10)
gen byte `llo' = (unit == 3 & _usable & weight <  10)
egen double `lomed' = median(cond(`llo', w_block, .)), by(pull_item)
egen int    `nlo'   = total(`llo'), by(pull_item)
gen double  `lrat'  = w_block / `lomed' if `lhi' & `nlo' > 0 & `lomed' > 0

* THE COUNT HERE IS 68 AND THE PUBLISHED FIGURE IS 67, and they are both right. 03a runs
* BEFORE the non-NSU exclusion, so one row that later leaves the build is still present.
* verify_documented_claims.py measures the band on the restated file, after that exclusion.
count if `lhi'
di as txt "03a litre band (tick = L, typed >= 10, read as mL): " r(N) " row(s)"
count if `lhi' & `nlo' == 0
di as txt "03a litre band with no same-item baseline to test against: " r(N) " row(s)"

count if `lhi' & `nlo' > 0 & `lrat' < 1/`LITDEC'
if r(N) > 0 {
	di as err "03a_block_reading.do: " r(N) " litre-ticked row(s) at 10 or above read"
	di as err "as millilitres more than 1.5 decades below their own item's scale."
	di as err "That is what a GENUINE litre reading looks like here. Adjudicate them"
	di as err "before this build is used -- see docs/implicit_assumptions.md A7."
	list pull_item pull_nsu_unit weight w_block `lomed' `lrat' ///
		if `lhi' & `nlo' > 0 & `lrat' < 1/`LITDEC', noobs abbrev(16)
	exit 459
}
di as txt "03a litre band guard: no row reads as a genuine litre entry"
* ====================================================================================

* --- unit==1 (kg) sub-1 entries are true kg -> grams via x1000 -----------------
replace w_block = weight*1000 if unit==1 & weight<1 & _usable

* --- unit==1 (kg) plausible bulk kg entries: trust the reading (-> grams) ------
*   THE CEILING MATTERS. It used to be 20, which left (20,1000) handled by nothing:
*   three 25 kg rice sacks fell through to the anchor and published at 2,500 g.
count if inrange(weight,1,`KGMAX') & unit==1 & _usable
di as txt "03a kg-plausibility: " r(N) " row(s) matched"
replace w_block = weight*1000 if inrange(weight,1,`KGMAX') & unit==1 & _usable

* --- unit==1 (kg) but far too big for kg: grams mis-ticked as kg ---------------
*   A cabbage does not weigh 1,180 kg. Above `KGMAX' the typed number is already grams
*   and the UNIT tick is the error, so take the reading as it stands.
*
*   ONE THRESHOLD, NO INTERMEDIATE BAND. This rule used to halt the build on a kg-ticked
*   reading in [30, 50) so that the first row the threshold ever actually adjudicated
*   would be decided by a person. Simplified on 2026-09-17: `KGMAX' alone separates
*   "believe the kg tick" from "this number is already grams", and a reading above it is
*   read as grams whichever side of 50 it falls. The field photographs are what will
*   establish whether that reads the object correctly -- see docs/implicit_assumptions.md
*   A6 and the methodology's weight section.
count if weight > `KGMAX' & unit==1 & _usable
di as txt "03a kg-implausibility (read as grams): " r(N) " row(s) matched"
replace w_block = weight if weight > `KGMAX' & unit==1 & _usable

* An unmapped unit code means a fourth tick appeared and every branch above is now
* silently incomplete -- the row would carry a missing block reading and the snap would
* fall through to the anchor with nothing to check it against.
count if _usable & !inlist(unit,1,2,3)
if r(N) > 0 {
	di as err "03a_block_reading.do: " r(N) " row(s) carry a unit code outside 1/2/3."
	di as err "The block reading covers kg, g and litres only. Add the branch."
	exit 459
}

* DELIBERATELY NOT ROUNDED HERE. 04_unit_snap.do's STEP 3e scores the block reading
* against a referee median in log10 terms using the UNROUNDED value, and rounds only at
* the point of saving. Rounding here would feed a slightly different number into that
* comparison -- 105 where the computation gives 104.999997 -- which cannot flip a
* decade-scale log10 test but would change published weights in the last digit for no
* reason. The rounding stays where it was.
label var w_block "Block reading: typed weight in g/mL, kg-tick not taken literally"

drop _usable
keep id w_block
sort id
save "${block_out}", replace

di as res "03a_block_reading.do: wrote " _N " block reading(s) to ${block_out}"
