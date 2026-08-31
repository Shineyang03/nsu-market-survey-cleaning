********************************************************************************
**# Summary stats of corrected_weight: prov_mun_nsu_item x hetero (+ province rollup)
********************************************************************************
* One sheet "cleaned nsu mean weights", one flat table: g and mL rows are
* appended together, distinguished by a corrected_unit column (filterable
* in Excel) rather than separate panels.
*
* Row layout: for each (province, nsu_item, hetero) block, all municipality-
* level rows are listed first (alphabetically), followed by one appended
* "PROVINCE (all municipalities)" rollup row aggregating across municipality.
* Hetero rows are displayed in a natural reading order (small->medium->large,
* mp25->mp50->mp75), not alphabetical.
*
* Two one-sided rank-sum test columns, computed separately within each row's
* own unit (that municipality, or the whole province for rollup rows).
* H1 is the INVERSION direction (preceding tier's median > this row's median),
* so p < 0.05 lets you reject the null IN FAVOR OF a monotonicity violation --
* not merely "insufficient evidence the expected order holds":
*   p_size_inversion  : H1 = the PRECEDING size tier's median > this row's
*                        median (i.e. small>medium, or medium>large). Missing
*                        unless hetero is medium_size or large_size (nothing
*                        precedes small).
*   p_price_inversion : same idea for price points (mp25->mp50->mp75).
* Both are always missing for conventional_nsu, municipality_median,
* province_median, unique_mun_price6/7.

global output "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs"
global temp    "${output}\temp"
global tables  "${output}\tables"

use "${temp}\nsu_data", clear

decode item_nsu_hetero_type, gen(item_nsu_hetero_type_lbl)
decode corrected_unit,       gen(corrected_unit_lbl)

keep if !missing(corrected_weight) & corrected_weight > 0

tempfile base
save `base'

local unitvals g   mL
local nunits : word count `unitvals'

local size_seq  small_size medium_size large_size
local price_seq mp25_price mp50_price mp75_price

forvalues u = 1/`nunits' {
    local unitval : word `u' of `unitvals'

    use `base', clear
    keep if corrected_unit_lbl == "`unitval'"
    qui count
    if r(N) == 0 continue

    tempfile unit_base
    save `unit_base'

    * ================================================================================
    * Winsorized (2nd/98th pctile) and MAD-trimmed (Iglewicz-Hoaglin, |M_i|>=3.5)
    * stats -- computed separately per cell definition, matching the two collapses
    * below (municipality-level cell, and province-level cell aggregated across
    * municipality). Winsorizing caps values at the group's 2nd/98th percentile;
    * MAD-trim excludes rows with modified Z-score M_i = 0.6745*(x_i-median)/MAD
    * at or beyond 3.5 in absolute value before computing stats. Cells where
    * MAD==0 are left untrimmed (a zero MAD makes the modified Z-score undefined).
    * ================================================================================
    local mun_grp  pull_province nsu_item pull_municipal_city item_nsu_hetero_type_lbl
    local prov_grp pull_province nsu_item item_nsu_hetero_type_lbl

    * -- municipality-level cell --
    use `unit_base', clear
    bysort `mun_grp': egen double p2_m  = pctile(corrected_weight), p(2)
    bysort `mun_grp': egen double p98_m = pctile(corrected_weight), p(98)
    gen double w_m = min(max(corrected_weight, p2_m), p98_m)

    preserve
        collapse (mean) mean_winsor=w_m (median) median_winsor=w_m (sd) sd_winsor=w_m ///
            (min) min_winsor=w_m (max) max_winsor=w_m, by(`mun_grp')
        gen str15 level = "Municipality"
        tempfile mun_winsor
        save `mun_winsor'
    restore

    bysort `mun_grp': egen double med_m = median(corrected_weight)
    gen double absdev_m = abs(corrected_weight - med_m)
    bysort `mun_grp': egen double mad_m = median(absdev_m)
    gen double Mi_m = 0.6745 * (corrected_weight - med_m) / mad_m
    gen byte outlier_m = mad_m > 0 & abs(Mi_m) >= 3.5

    preserve
        keep if outlier_m == 0
        collapse (mean) mean_mad=corrected_weight (median) median_mad=corrected_weight ///
            (sd) sd_mad=corrected_weight (min) min_mad=corrected_weight (max) max_mad=corrected_weight ///
            (count) n_mad=corrected_weight, ///
            by(`mun_grp')
        gen str15 level = "Municipality"
        tempfile mun_mad
        save `mun_mad'
    restore

    * -- province-level cell (aggregate across municipality) --
    use `unit_base', clear
    bysort `prov_grp': egen double p2_p  = pctile(corrected_weight), p(2)
    bysort `prov_grp': egen double p98_p = pctile(corrected_weight), p(98)
    gen double w_p = min(max(corrected_weight, p2_p), p98_p)

    preserve
        collapse (mean) mean_winsor=w_p (median) median_winsor=w_p (sd) sd_winsor=w_p ///
            (min) min_winsor=w_p (max) max_winsor=w_p, by(`prov_grp')
        gen str35 pull_municipal_city = "PROVINCE (all municipalities)"
        gen str15 level = "Province"
        tempfile prov_winsor
        save `prov_winsor'
    restore

    bysort `prov_grp': egen double med_p = median(corrected_weight)
    gen double absdev_p = abs(corrected_weight - med_p)
    bysort `prov_grp': egen double mad_p = median(absdev_p)
    gen double Mi_p = 0.6745 * (corrected_weight - med_p) / mad_p
    gen byte outlier_p = mad_p > 0 & abs(Mi_p) >= 3.5

    preserve
        keep if outlier_p == 0
        collapse (mean) mean_mad=corrected_weight (median) median_mad=corrected_weight ///
            (sd) sd_mad=corrected_weight (min) min_mad=corrected_weight (max) max_mad=corrected_weight ///
            (count) n_mad=corrected_weight, ///
            by(`prov_grp')
        gen str35 pull_municipal_city = "PROVINCE (all municipalities)"
        gen str15 level = "Province"
        tempfile prov_mad
        save `prov_mad'
    restore

    use `mun_winsor', clear
    append using `prov_winsor'
    rename item_nsu_hetero_type_lbl item_nsu_hetero_type
    tempfile winsor_all
    save `winsor_all'

    use `mun_mad', clear
    append using `prov_mad'
    rename item_nsu_hetero_type_lbl item_nsu_hetero_type
    tempfile mad_all
    save `mad_all'

    * ---- municipality-level collapse ----
    use `unit_base', clear
    collapse (mean) mean_weight=corrected_weight (median) median_weight=corrected_weight ///
             (sd) sd_weight=corrected_weight (min) min_weight=corrected_weight ///
             (max) max_weight=corrected_weight (count) n_weight=corrected_weight, ///
             by(pull_province nsu_item pull_municipal_city item_nsu_hetero_type_lbl)
    gen str15 level = "Municipality"
    tempfile muni_stats
    save `muni_stats'

    * ---- province-level collapse (aggregate across municipality) ----
    use `unit_base', clear
    collapse (mean) mean_weight=corrected_weight (median) median_weight=corrected_weight ///
             (sd) sd_weight=corrected_weight (min) min_weight=corrected_weight ///
             (max) max_weight=corrected_weight (count) n_weight=corrected_weight, ///
             by(pull_province nsu_item item_nsu_hetero_type_lbl)
    gen str35 pull_municipal_city = "PROVINCE (all municipalities)"
    gen str15 level = "Province"

    append using `muni_stats'
    rename item_nsu_hetero_type_lbl item_nsu_hetero_type

    * ---- natural display order for hetero rows (not alphabetical) ----
    gen byte hetero_order = .
    replace hetero_order = 1  if item_nsu_hetero_type=="conventional_nsu"
    replace hetero_order = 2  if item_nsu_hetero_type=="small_size"
    replace hetero_order = 3  if item_nsu_hetero_type=="medium_size"
    replace hetero_order = 4  if item_nsu_hetero_type=="large_size"
    replace hetero_order = 5  if item_nsu_hetero_type=="mp25_price"
    replace hetero_order = 6  if item_nsu_hetero_type=="mp50_price"
    replace hetero_order = 7  if item_nsu_hetero_type=="mp75_price"
    replace hetero_order = 8  if item_nsu_hetero_type=="municipality_median"
    replace hetero_order = 9  if item_nsu_hetero_type=="province_median"
    replace hetero_order = 10 if item_nsu_hetero_type=="unique_mun_price6"
    replace hetero_order = 11 if item_nsu_hetero_type=="unique_mun_price7"
    assert !missing(hetero_order)

    gen byte sort_lvl = (level=="Province")
    sort pull_province nsu_item hetero_order sort_lvl pull_municipal_city
    drop sort_lvl hetero_order

    tempfile summary_stage
    save `summary_stage'

    * ---- build unit list (level, province, nsu_item, municipality) ----
    preserve
        keep pull_province nsu_item pull_municipal_city level
        duplicates drop
        local n_units = _N
        forvalues r = 1/`n_units' {
            local prov_`r' = pull_province[`r']
            local item_`r' = nsu_item[`r']
            local muni_`r' = pull_municipal_city[`r']
            local lvl_`r'  = level[`r']
        }
    restore

    tempname ph
    tempfile ranksum_results
    postfile `ph' str15 level str30 pull_province str90 nsu_item str35 pull_municipal_city ///
        str25 item_nsu_hetero_type double(p_size_inversion p_price_inversion) using `ranksum_results', replace

    forvalues r = 1/`n_units' {
        local prov "`prov_`r''"
        local item "`item_`r''"
        local muni "`muni_`r''"
        local lvl  "`lvl_`r''"

        foreach cat in `size_seq' `price_seq' {
            local psize_`cat'  = .
            local pprice_`cat' = .
        }

        preserve
            use `unit_base', clear
            keep if pull_province=="`prov'" & nsu_item=="`item'"
            if "`lvl'"=="Municipality" {
                keep if pull_municipal_city=="`muni'"
            }

            * -- size sequence: small -> medium -> large --
            local prevcat ""
            foreach cat of local size_seq {
                qui count if item_nsu_hetero_type_lbl=="`cat'"
                local n_this = r(N)
                if `n_this' > 0 & "`prevcat'" != "" {
                    qui count if item_nsu_hetero_type_lbl=="`prevcat'"
                    if r(N) > 0 {
                        qui su corrected_weight if item_nsu_hetero_type_lbl=="`prevcat'", detail
                        local med_prev = r(p50)
                        qui su corrected_weight if item_nsu_hetero_type_lbl=="`cat'", detail
                        local med_this = r(p50)
                        qui ranksum corrected_weight if inlist(item_nsu_hetero_type_lbl,"`prevcat'","`cat'"), by(item_nsu_hetero_type_lbl)
                        local p_two = r(p)
                        * H1 = inversion (prevcat's median > this cat's median)
                        local psize_`cat' = cond(`med_prev' > `med_this', `p_two'/2, 1 - `p_two'/2)
                    }
                }
                if `n_this' > 0 local prevcat "`cat'"
            }

            * -- price sequence: mp25 -> mp50 -> mp75 --
            local prevcat ""
            foreach cat of local price_seq {
                qui count if item_nsu_hetero_type_lbl=="`cat'"
                local n_this = r(N)
                if `n_this' > 0 & "`prevcat'" != "" {
                    qui count if item_nsu_hetero_type_lbl=="`prevcat'"
                    if r(N) > 0 {
                        qui su corrected_weight if item_nsu_hetero_type_lbl=="`prevcat'", detail
                        local med_prev = r(p50)
                        qui su corrected_weight if item_nsu_hetero_type_lbl=="`cat'", detail
                        local med_this = r(p50)
                        qui ranksum corrected_weight if inlist(item_nsu_hetero_type_lbl,"`prevcat'","`cat'"), by(item_nsu_hetero_type_lbl)
                        local p_two = r(p)
                        * H1 = inversion (prevcat's median > this cat's median)
                        local pprice_`cat' = cond(`med_prev' > `med_this', `p_two'/2, 1 - `p_two'/2)
                    }
                }
                if `n_this' > 0 local prevcat "`cat'"
            }
        restore

        foreach cat in `size_seq' `price_seq' {
            post `ph' ("`lvl'") ("`prov'") ("`item'") ("`muni'") ("`cat'") (`psize_`cat'') (`pprice_`cat'')
        }
    }
    postclose `ph'

    use `summary_stage', clear
    merge 1:1 level pull_province nsu_item pull_municipal_city item_nsu_hetero_type ///
        using `ranksum_results', keep(master match) nogen
    merge 1:1 level pull_province nsu_item pull_municipal_city item_nsu_hetero_type ///
        using `winsor_all', keep(master match) nogen
    merge 1:1 level pull_province nsu_item pull_municipal_city item_nsu_hetero_type ///
        using `mad_all', keep(master match) nogen

    * merge re-sorts by the (string) merge keys, which clobbers the intended
    * display order -- reapply the same custom hetero order + muni-then-province sort
    gen byte hetero_order = .
    replace hetero_order = 1  if item_nsu_hetero_type=="conventional_nsu"
    replace hetero_order = 2  if item_nsu_hetero_type=="small_size"
    replace hetero_order = 3  if item_nsu_hetero_type=="medium_size"
    replace hetero_order = 4  if item_nsu_hetero_type=="large_size"
    replace hetero_order = 5  if item_nsu_hetero_type=="mp25_price"
    replace hetero_order = 6  if item_nsu_hetero_type=="mp50_price"
    replace hetero_order = 7  if item_nsu_hetero_type=="mp75_price"
    replace hetero_order = 8  if item_nsu_hetero_type=="municipality_median"
    replace hetero_order = 9  if item_nsu_hetero_type=="province_median"
    replace hetero_order = 10 if item_nsu_hetero_type=="unique_mun_price6"
    replace hetero_order = 11 if item_nsu_hetero_type=="unique_mun_price7"
    assert !missing(hetero_order)
    gen byte sort_lvl2 = (level=="Province")
    sort pull_province nsu_item hetero_order sort_lvl2 pull_municipal_city
    drop hetero_order sort_lvl2

    gen str2 corrected_unit = "`unitval'"

    order pull_province nsu_item pull_municipal_city level item_nsu_hetero_type corrected_unit ///
        n_weight mean_weight median_weight sd_weight min_weight max_weight ///
        p_size_inversion p_price_inversion ///
        mean_winsor median_winsor sd_winsor min_winsor max_winsor ///
        mean_mad median_mad sd_mad min_mad max_mad n_mad

    tempfile final_`u'
    save `final_`u''
}

* ================================================================================
* Export: one sheet, one flat table (g and mL appended, filter on corrected_unit)
* ================================================================================
use `final_1', clear
append using `final_2'

export excel using "${tables}\summary_corrected_weight_by_cell.xlsx", ///
    sheet("cleaned nsu mean weights") sheetreplace firstrow(variables)
