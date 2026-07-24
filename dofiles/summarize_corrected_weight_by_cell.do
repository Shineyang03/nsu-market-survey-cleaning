********************************************************************************
**# Summary stats of corrected_weight by prov_mun_nsu_item x item_nsu_hetero_type
********************************************************************************
* Collapses corrected_weight to the cell prov_mun_nsu_item x item_nsu_hetero_type,
* computing mean / median / SD / min / max / N (non-missing). Exports one Excel
* workbook with 2 tabs: corrected_unit == "g" and corrected_unit == "mL".

global output "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs"
global temp    "${output}\temp"
global tables  "${output}\tables"
global graphs  "${output}\graphs"

use "${temp}\nsu_data", clear

decode item_nsu_hetero_type, gen(item_nsu_hetero_type_lbl)
decode corrected_unit,       gen(corrected_unit_lbl)

keep if !missing(corrected_weight) & corrected_weight > 0

tempfile base
save `base'

local unitvals g   mL
local sheets   raw_g   raw_ml
local nunits : word count `unitvals'

forvalues i = 1/`nunits' {
    local unitval : word `i' of `unitvals'
    local sheet   : word `i' of `sheets'

    use `base', clear
    keep if corrected_unit_lbl == "`unitval'"

    collapse (mean)   mean_weight   = corrected_weight ///
             (median) median_weight = corrected_weight ///
             (sd)     sd_weight     = corrected_weight ///
             (min)    min_weight    = corrected_weight ///
             (max)    max_weight    = corrected_weight ///
             (count)  n_weight      = corrected_weight ///
             , by(prov_mun_nsu_item item_nsu_hetero_type_lbl)

    rename item_nsu_hetero_type_lbl item_nsu_hetero_type

    order prov_mun_nsu_item item_nsu_hetero_type n_weight mean_weight median_weight sd_weight min_weight max_weight

    sort prov_mun_nsu_item item_nsu_hetero_type

    export excel using "${tables}\summary_corrected_weight_by_cell.xlsx", ///
        sheet("`sheet'") sheetreplace firstrow(variables)
}


use `base', clear


********************************************************************************
**# Forest dot-plot: one graph per pull_province x nsu_item
********************************************************************************
* Axis (one graph) = pull_province x nsu_item. On that single graph:
*   - PROVINCE row      : province-wide median (large black diamond) + hetero-
*                         type medians POOLED ACROSS all municipalities in the
*                         province (small hollow diamonds, colored by hetero type)
*   - municipality rows : that municipality's overall median (large navy circle)
*                         + hetero-type medians computed WITHIN that
*                         municipality only (small filled circles, same hetero
*                         color scheme as the province row)
* Every marker is labeled with its underlying sample size (n=).
* A one-time legend-key image (hetero type -> color) is exported separately
* since 22 possible layers would make a per-graph legend unreadable.

* ---- sample toggle: set to 0 to loop over every province x nsu_item ----------
local SAMPLE_ONLY   = 1
local SAMPLE_ITEMS  "Cabbage_Bilog"

* ---- fixed hetero type -> color assignment (consistent across all graphs) ----
local hetlist  conventional_nsu large_size medium_size mp25_price mp50_price ///
               mp75_price municipality_median province_median small_size ///
               unique_mun_price6 unique_mun_price7
local collist  navy maroon forest_green dkorange purple ///
               teal magenta olive brown gray ///
               pink
local nhet : word count `hetlist'

cap mkdir "${graphs}\forest_dotplot"

* ---- one-time legend key: hetero type -> color -------------------------------
preserve
    clear
    set obs `nhet'
    gen long y = `nhet' - _n + 1
    gen str40 hetero_lbl = ""
    gen str10 col        = ""
    forvalues i = 1/`nhet' {
        local het : word `i' of `hetlist'
        local col : word `i' of `collist'
        replace hetero_lbl = "`het'" if _n==`i'
        replace col        = "`col'" if _n==`i'
    }
    local layers
    forvalues i = 1/`nhet' {
        local het : word `i' of `hetlist'
        local col : word `i' of `collist'
        local layers `layers' (scatter y y if hetero_lbl=="`het'", msymbol(O) msize(large) mcolor(`col'))
    }
    local ylabellist
    forvalues i = 1/`nhet' {
        local het : word `i' of `hetlist'
        local yv = `nhet' - `i' + 1
        local ylabellist `ylabellist' `yv' "`het'"
    }
    twoway `layers', ///
        ylabel(`ylabellist', angle(0) labsize(small)) ytitle("") ///
        xlabel(none) xtitle("") legend(off) ///
        title("Hetero type -> color key (used in forest_dotplot graphs)", size(small)) ///
        scheme(s2color)
    graph export "${graphs}\forest_dotplot\_legend_key.png", replace width(900)
restore

* ---- build the 4 stacked levels: (province, municipality) x (main, hetero) ---
tempfile long
local first = 1
foreach lvl in prov muni {
    foreach agg in main hetero {
        use `base', clear
        local rowvar
        local hetvar
        if "`lvl'"=="muni"   local rowvar pull_municipal_city
        if "`agg'"=="hetero" local hetvar item_nsu_hetero_type_lbl

        collapse (median) value=corrected_weight (count) n=corrected_weight, ///
            by(pull_province nsu_item `rowvar' `hetvar')

        gen str10 level = "`lvl'"
        gen str10 agg   = "`agg'"
        if "`lvl'"=="prov" {
            gen str60 row_label = "PROVINCE"
        }
        else {
            gen str60 row_label = pull_municipal_city
            drop pull_municipal_city
        }
        if "`agg'"=="hetero" {
            rename item_nsu_hetero_type_lbl hetero_lbl
        }
        else {
            gen str40 hetero_lbl = ""
        }

        keep pull_province nsu_item row_label level agg hetero_lbl value n
        if `first' {
            save `long', replace
            local first = 0
        }
        else {
            append using `long'
            save `long', replace
        }
    }
}

use `long', clear

if `SAMPLE_ONLY' {
    keep if inlist(nsu_item, "`SAMPLE_ITEMS'")
}

* ---- loop over every pull_province x nsu_item combo present ------------------
preserve
    keep pull_province nsu_item
    duplicates drop
    local ncombo = _N
    forvalues c = 1/`ncombo' {
        local prov_`c' = pull_province[`c']
        local item_`c' = nsu_item[`c']
    }
restore

forvalues c = 1/`ncombo' {
    local province "`prov_`c''"
    local item     "`item_`c''"

    preserve
        keep if pull_province=="`province'" & nsu_item=="`item'"

        * ---- rank municipalities by their main-level median (desc); PROVINCE on top
        tempfile combo muniorder
        save `combo'

        keep if level=="muni" & agg=="main"
        gsort -value
        gen long muni_rank = _n
        keep row_label muni_rank
        save `muniorder', replace

        use `combo', clear
        merge m:1 row_label using `muniorder', nogenerate
        replace muni_rank = 0 if row_label=="PROVINCE"
        sum muni_rank, meanonly
        local nmuni = r(max)
        gen double y = `nmuni' + 1 - muni_rank

        * ---- vertical jitter for hetero markers, ranked by the fixed hetlist ---------
        gen double yjit = y
        forvalues i = 1/`nhet' {
            local het : word `i' of `hetlist'
            replace yjit = y + (`i' - (`nhet'+1)/2)*0.07 if agg=="hetero" & hetero_lbl=="`het'"
        }

        * ---- y-axis labels: one per unique row_label (municipality or PROVINCE) ------
        local ylabellist
        levelsof y if agg=="main", local(yvals)
        foreach yv of local yvals {
            qui levelsof row_label if y==`yv' & agg=="main", local(rlv) clean
            local ylabellist `ylabellist' `yv' "`rlv'"
        }

        * ---- assemble twoway layers ---------------------------------------------------
        local layers
        local layers `layers' (scatter y value if agg=="main" & level=="prov", ///
            msymbol(D) msize(vlarge) mcolor(black) mlabel(n) mlabpos(12) mlabsize(vsmall))
        local layers `layers' (scatter y value if agg=="main" & level=="muni", ///
            msymbol(O) msize(large) mcolor(navy) mlabel(n) mlabpos(12) mlabsize(vsmall))

        forvalues i = 1/`nhet' {
            local het : word `i' of `hetlist'
            local col : word `i' of `collist'
            qui count if agg=="hetero" & hetero_lbl=="`het'" & level=="prov"
            if r(N) > 0 {
                local layers `layers' (scatter yjit value if agg=="hetero" & level=="prov" & hetero_lbl=="`het'", ///
                    msymbol(Dh) msize(small) mcolor(`col'))
            }
            qui count if agg=="hetero" & hetero_lbl=="`het'" & level=="muni"
            if r(N) > 0 {
                local layers `layers' (scatter yjit value if agg=="hetero" & level=="muni" & hetero_lbl=="`het'", ///
                    msymbol(O) msize(vsmall) mcolor(`col'))
            }
        }

        twoway `layers', ///
            ylabel(`ylabellist', angle(0) labsize(small)) ///
            ytitle("") xtitle("corrected_weight") ///
            title("`province' | `item'", size(medium)) ///
            subtitle("diamond=province, circle=municipality; large=overall median, small=hetero-type median" ///
                     " (hollow=pooled across province, filled=within municipality); see _legend_key.png for hetero colors", ///
                     size(vsmall)) ///
            legend(off) scheme(s2color)

        local safe_prov = subinstr("`province'"," ","_",.)
        local safe_item = subinstr("`item'"," ","_",.)
        local fname = "`safe_prov'_`safe_item'.png"
        graph export "${graphs}/forest_dotplot/`fname'", replace width(1400)
    restore
}
