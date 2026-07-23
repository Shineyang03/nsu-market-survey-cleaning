********************************************************************************
**# Summary stats of corrected_weight by prov_mun_nsu_item x item_nsu_hetero_type
********************************************************************************
* Collapses corrected_weight to the cell prov_mun_nsu_item x item_nsu_hetero_type,
* computing mean / median / SD / min / max / N (non-missing). Exports one Excel
* workbook with 2 tabs: corrected_unit == "g" and corrected_unit == "mL".

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
local sheets   g   ml
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
