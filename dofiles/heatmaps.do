** Heatmaps: obs counts by prov_mun (rows) x nsu_item (cols) **
* Created by: Shine Yang
* Date Created: 15th July, 2026
* Overall + separately by market_type
***********************************************

********************************************************************************
**# Setting Globals
********************************************************************************

global data "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\NSU Market Survey Launch\data\PSPS NSU Market Survey Launch.dta"

global output "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey\Data Cleaning\outputs"

global graphs "${output}\graphs"
cap noi mkdir "${graphs}"

* dependencies
cap which heatplot
if _rc ssc install heatplot, replace
cap which colorpalette
if _rc ssc install palettes, replace
cap which colrspace.sthlp
if _rc ssc install colrspace, replace

********************************************************************************
**# Prep: counts by prov_mun x nsu_item (x market_type)
********************************************************************************

use "${data}", clear

gen prov_mun = pull_province + "_" + pull_municipal_city
gen nsu_item = pull_item + "_" + pull_nsu_unit

* shorten long item names for readable axis labels
replace nsu_item = subinstr(nsu_item, "Preserved or Processed Meat (Tocino, Tapa, Longaniza, etc)", "Processed Meat", .)
replace nsu_item = subinstr(nsu_item, "Ice cream, sorbet, edible ice (eg., ice-lolli, halo-halo)", "Ice cream", .)
replace nsu_item = subinstr(nsu_item, "Liquor (e.g, whisky, coconut wine)", "Liquor", .)
replace nsu_item = subinstr(nsu_item, "Prawns, Lobster, shrimp", "Prawns/Shrimp", .)

tempfile base
save `base'

********************************************************************************
**# Heatmap 1: overall
********************************************************************************

contract prov_mun nsu_item, freq(n)

encode prov_mun, gen(row)
encode nsu_item, gen(col)

sum n
local max = r(max)

heatplot n i.col i.row, ///
    values(format(%9.0f) size(*0.2)) ///
    color(viridis, reverse) cuts(0(2)`max') ///
    ylabel(, labsize(*0.17) nogrid) ///
    xlabel(, labsize(*0.17) angle(90) nogrid) ///
    ytitle("") xtitle("") ///
    title("Observations by prov_mun x nsu_item", size(small)) ///
    legend(off) ysize(30) xsize(20)

graph export "${graphs}\heatmap_prov_mun_by_nsu_item.png", replace width(4000)

********************************************************************************
**# Heatmaps 2-4: by market_type
********************************************************************************

use `base', clear
decode market_type, gen(mt_str)
levelsof mt_str, local(mtypes)

foreach mt of local mtypes {
    use `base', clear
    decode market_type, gen(mt_str)
    keep if mt_str == "`mt'"

    contract prov_mun nsu_item, freq(n)

    encode prov_mun, gen(row)
    encode nsu_item, gen(col)

    sum n
    local max = r(max)

    local fname = strlower(subinstr("`mt'", " ", "_", .))

    heatplot n i.col i.row, ///
        values(format(%9.0f) size(*0.2)) ///
        color(viridis, reverse) cuts(0(2)`max') ///
        ylabel(, labsize(*0.17) nogrid) ///
        xlabel(, labsize(*0.17) angle(90) nogrid) ///
        ytitle("") xtitle("") ///
        title("Observations by prov_mun x nsu_item: `mt'", size(small)) ///
        legend(off) ysize(30) xsize(20)

    graph export "${graphs}\heatmap_prov_mun_by_nsu_item_`fname'.png", replace width(4000)
}

