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

* --- litres. Same premise in the volume dimension. A genuine 20 L reading would
*   become 20 mL here; safe only because the one cell with real litre readings
*   (mineral water) is removed upstream by the non-NSU exclusion. Accidental
*   protection, not a guard -- reviewed and accepted, see issue #18 B2.
replace w_block = cond(weight>=10, weight, weight*1000) if unit==3 & _usable

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
