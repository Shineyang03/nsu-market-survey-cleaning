# ==============================================================================
# NSU_Price.R -- builds the PSPS price schedule the market survey was fielded on
#
# WHAT THIS PRODUCES
#   inputs/NSU_prices_march_reproduced.csv -- one row per
#   (province x municipality x item x raw NSU spelling x price type), with the
#   peso value the price-collection rules selected.
#
# NOT PART OF THE MASTER PIPELINE. Neither master_outcome1.do nor
# master_outcome2.do calls this file, and nothing reads it automatically. The
# CSV it writes is checked in as a pipeline INPUT. This script exists so that
# input is reproducible rather than a file of unknown provenance -- which is
# precisely the failure issue #42 documents.
#
# Run it only when the consumption extract changes, or to verify the input:
#
#   "C:\Program Files\R\R-4.5.1\bin\Rscript.exe" dofiles/price/NSU_Price.R
#
# It overwrites the CSV in place. On unchanged inputs the output is identical,
# so a clean `git diff` after running it is the verification.
#
# ------------------------------------------------------------------------------
# PROVENANCE
#
# This is the script that produced the 15 March 2026 price schedule. The market
# survey was fielded from that schedule, by way of the SurveyCTO case file
# (NSU Market Survey Launch/cases/nsu_cases_final.dta, 16 March): every one of
# the 366 distinct (cell, price type, amount) combinations in the market survey
# matches this script's output exactly, on all six price types.
#
# A LATER REVISION of this script produced NSU_prices_from_Makayla.csv (21 July
# 2026), which the build used until #42. That revision carries three defects
# this one does not:
#
#   1. unique_mun_price holds the household's EXPENDITURE, not Price/Quantity.
#      Of its 541 unique rows, 323 equal a household's total outlay and match no
#      unit price in the cell; none is a unit price that is not also an outlay.
#   2. uuid drops the province, giving 2,919 distinct uuids for 2,952 cells, so
#      33 cells shared a uuid and lost rows to `slice(1)`.
#   3. the quartile rule was changed from two PHP 20 half-gap tests to a single
#      PHP 40 test on the whole interquartile range. That is a methodological
#      change rather than a defect, but it travelled with the other two.
#
# The original lives at "01 Panel/NSU_Price.R". THE ANALYTICAL CODE BELOW IS
# UNCHANGED FROM IT -- no rule, threshold, grouping or column differs. Five
# things do, all marked `### REPO`:
#
#   1. paths are derived from the Windows username, as 00_globals.do does, so
#      the script runs for anyone with the Box tree mounted;
#   2. the consumption extract is read from 5_outputs/2_publication_data/. The
#      original names 3_publication_data/, which does not exist on disk;
#   3. the output goes to Data Cleaning/inputs/ under an explicit name, rather
#      than NSU_prices.csv in the working directory;
#   4. the trailing Beef_and_pork block is removed -- it references
#      Mun_data_sum_2, which the script never creates, and errors after the
#      file is written;
#   5. a composition report prints after the write, so a run is self-checking.
#
# ------------------------------------------------------------------------------
# THE RULES THIS IMPLEMENTS, for a reader who will not run it
#
# Prices are household unit values: Price_perunit = Price / Quantity, pooled
# across all three acquisition slots (fd_cons_2 purchased, 3 own production,
# 4 gift). Standard units are excluded by an exact-string blacklist before any
# quantile is taken. Then, within province x municipality x item x unit:
#
#   <= 2 distinct unit values  ->  the PROVINCE MEDIAN, plus any individual
#                                  household value sitting >= PHP 20 away from
#                                  it, recorded verbatim as `unique_mun_price`
#   >= 3 distinct unit values  ->  the MUNICIPALITY MEDIAN alone if both
#                                  (mp75 - mp50) and (mp50 - mp25) are <= PHP 20;
#                                  otherwise mp50 plus whichever quartile sits
#                                  more than PHP 20 from it
#
# Note the asymmetry: a unique price is kept at >= 20, a quartile at > 20.
#
# A `unique_mun_price` is therefore ONE HOUSEHOLD'S OWN unit value, kept as it
# stands -- the only price type here that is not an order statistic over
# households. See A16 and #42 for what follows from that.
# ==============================================================================

# Section 1: Load Libraries ----------------------------------------------------

library(dplyr)
library(tidyr)
library(stringr)
library(readxl)
library(ggplot2)
library(haven)   # For reading stata files


# Global file directory
### REPO 1: derived from the username, matching 00_globals.do, instead of a
### hard-coded "C:/Users/mab3351/Box/Philippines Panel/01 Panel/".
panel_root <- file.path("C:/Users", Sys.getenv("USERNAME"),
                        "Box/Philippines Panel/01 Panel")
stopifnot(dir.exists(panel_root))
setwd(panel_root)

out_csv <- file.path(panel_root, "14 NSU Market Survey/Data Cleaning/inputs",
                     "NSU_prices_march_reproduced.csv")

#-------------------------------------------------------------------------------
# Section 2: Load Data ---------------------------------------------------------
### REPO 2: 2_publication_data, not 3_publication_data.
Cons_Data_path <- "08 Analysis & Data/14 Wave 1_Pub/Household survey/5_outputs/2_publication_data/2_consumption/2_consumption.dta"
stopifnot(file.exists(Cons_Data_path))
Cons_data <- read_dta(Cons_Data_path)

# Load in Standard Units
cons_units_path <- "07 Questionnaires/03 Wave 1/04 Final instruments/Household_linked SCTO/Household_all_modules.xlsx"
cons_units <- read_excel(cons_units_path, sheet = 2) %>%
  filter(list_name == "cons_unit") %>%
  mutate(value = sub("\\.0$", "", value))

# Load in Municipality mapping data
municipality_path <- "08 Analysis & Data/14 Wave 1_Pub/Household survey/3_input_data/municipal_mapping.dta"

municipalities <- read_dta(municipality_path)

#-------------------------------------------------------------------------------
# Section 3: Data Cleaning ---------------------------------------------------------

Cons_data <- Cons_data %>%
               select(hhid, province, brgy_code, municipal_code, item, item_type, cons_name, starts_with("fd_cons")) %>%
               filter(item_type == 1) # Filter out non_food items. 1 = food, 2 = prepared food


Cons_data <- left_join(Cons_data, municipalities, by = "municipal_code")

# Removed prepped food variables, those are not part of the market survey
Cons_data <- Cons_data %>%
              select(-fd_cons_5a, -fd_cons_6a, -fd_cons_6b, -fd_cons_6c)

# Pivot data to consider at once all methods for acquiring item (purchase, gift, own production)

Cons_data <- Cons_data %>%
  pivot_longer(
    cols = matches("^fd_cons_[2-4](?:aunit_lbl|aunit|a|b)$"),
    names_to = c("Acquired_by", ".value"),
    names_pattern = "^fd_cons_([2-4])(aunit_lbl|aunit|a|b)$"
  ) %>%
  rename(
    Quantity = `a`,
    Unit = `aunit`,
    Unit_lbl = `aunit_lbl`,
    Price = b
  ) %>%
     filter(Quantity != 0)


# Get price per unit, create unique ID, filter out non-relevent item unit pairs
Cons_data <- Cons_data %>%
             mutate(Price_perunit = Price/Quantity,
                    uuid = paste(cons_name, Unit_lbl, province, pull_municipal_city, sep = "_" )) %>%
  filter(!Unit_lbl %in% c("Grams (g)", "Kilograms (Kg)", "Grams", "Kilo", "Kilograms", "Kilos", "5-gallon blue container",
                          "Litro (L)", "Liters", "Liters (L)", "Millileters (mL)", "Bote (330ml)", "Bote (500ml)",
                          "Botelya (330ml)", "Botelya (500ml)", "Gallons", "Gantang", "Lata (330 ml)", "Lata (500 ml)"))


# Get quantile prices at the municipality level
Mun_data_sum <-  Cons_data %>%
      group_by(province, municipal_code, pull_municipal_city, cons_name, Unit_lbl) %>%
      summarise(
        mn_item_unit_pairs = n(),
        mn_unique_price = n_distinct(Price_perunit, na.rm = TRUE),
        mp25_price = quantile(Price_perunit, 0.25, na.rm = TRUE, type = 7),
        mp50_price = quantile(Price_perunit, 0.50, na.rm = TRUE, type = 7),
        mp75_price = quantile(Price_perunit, 0.75, na.rm = TRUE, type = 7),
        .groups = "drop"
      )

# Check duplicates
check_dup <- Mun_data_sum %>%
            group_by(municipal_code, cons_name, Unit_lbl) %>%
            filter(n() > 1) %>%
            ungroup()


# Get median prices at the province level
Prov_data_sum <- Cons_data %>%
  group_by(province, cons_name, Unit_lbl) %>%
  summarise(
    pn_item_unit_pairs = n(),
    pn_unique_price = n_distinct(Price_perunit, na.rm = TRUE),
    pp50_price = quantile(Price_perunit, 0.50, na.rm = TRUE, type = 7),
    .groups = "drop"
  )

# Check duplicates
check_dup <- Prov_data_sum %>%
  group_by(province, cons_name, Unit_lbl) %>%
  filter(n() > 1) %>%
  ungroup()

full_sum <- right_join(Prov_data_sum, Mun_data_sum) %>%
            mutate(uuid = paste(cons_name, Unit_lbl, province, pull_municipal_city, sep = "_" ))

Cons_data_2 <- full_join(Cons_data, full_sum)

#-------------------------------------------------------------------------------
# Section 4: Implement Price Collection Rules ----------------------------------


# Rule 1: For municipalities with n<=2 unique prices

small_n_mun <- filter(Cons_data_2, mn_unique_price <= 2) %>%
               mutate(province_variance = abs(pp50_price - Price_perunit),
                      Collect_mun_prices = ifelse(province_variance < 20, FALSE, TRUE))


collect_mun_prices <- small_n_mun %>%
                       filter(Collect_mun_prices == "TRUE") %>%
                        mutate(price_type = "unique_mun_price") %>%
                        select(-Price, -pp50_price) %>%
                        rename(Price = Price_perunit) %>%
                        group_by(uuid, Price) %>%
                        slice(1)

 prov_med_prices <- small_n_mun %>%
                    mutate(price_type = "province median") %>%
                    select(-Price, -Price_perunit) %>%
                    rename(Price = pp50_price) %>%
                    group_by(uuid, Price) %>%
                    slice(1)

small_n_mun <- full_join(collect_mun_prices, prov_med_prices) %>%
               select(-mp25_price, -mp50_price, -mp75_price)

# Rule 2: For municipalities with n>=3 unique prices

#Identify item unit pairs where difference between 25th & 50th AND 50 th & 75th quantiles are sufficiently small
#  In this case we want median prices only.

large_n_med <- filter(full_sum, mn_unique_price > 2) %>%
               mutate(
               iqr_1 = mp75_price - mp50_price,
               iqr_2 = mp50_price - mp25_price,
               low_var_1 = iqr_1 <= 20,
               low_var_2 = iqr_2 <= 20)

large_n_med <- large_n_med %>%
               filter(low_var_1 == TRUE & low_var_2 == TRUE) %>%
               mutate(price_type = "municipality median") %>%
               #select(-Price) %>%
               rename(Price = mp50_price) %>%
               select(province, cons_name, Unit_lbl, pn_item_unit_pairs,
               pn_unique_price, pull_municipal_city, mn_item_unit_pairs, uuid, Price, price_type) %>%
               mutate(low_variance = TRUE)

#Identify item unit pairs where difference between 25th & 50th OR 50 th & 75th quantiles are sufficiently small
#  In these cases we only keep quantles with significant differences.

large_n_quantiles <-  filter(full_sum, mn_unique_price > 2) %>%
                     # select(-Price) %>%
                      pivot_longer(c(mp25_price, mp75_price),
                      names_to = "price_type",
                      values_to = "Price") %>%
                      mutate(
                      variance = abs(Price - mp50_price),
                      low_variance = variance <= 20) %>%
                      filter(low_variance == "FALSE")


med_only <- large_n_quantiles %>%
             select(province, cons_name, Unit_lbl, pn_item_unit_pairs,
                    pn_unique_price, pull_municipal_city, mn_item_unit_pairs, mn_unique_price, uuid, mp50_price, ) %>%
             distinct() %>%
             mutate(price_type = "mp50_price") %>%
            rename(Price = mp50_price)


large_n_quantiles <- large_n_quantiles %>%
                      select(-mp50_price) %>%
                      full_join(med_only)

large_n_mun <- full_join(large_n_quantiles, large_n_med) %>%
                 select(-pp50_price)


Final_price_data <- full_join(large_n_mun, small_n_mun) %>%
                   select(-hhid, -brgy_code, -item, -item_type, -pull_province, -Acquired_by, -Quantity, -Unit, -province_variance)

### REPO 3: an explicit path in Data Cleaning/inputs/, not NSU_prices.csv in the cwd.
write.csv(Final_price_data, out_csv)

### REPO 4: the original's trailing Beef_and_pork block is removed here. It read
### Mun_data_sum_2, which this script never creates, so it errored on every run
### -- after the file was written, which is why the output was unaffected.

### REPO 5: composition report, so a run is self-checking. Compare against the
### figures below; any movement means the consumption extract changed.
cat("\nwrote:", out_csv, "\n")
cat("rows:", nrow(Final_price_data), "  (expected 3665)\n\n")
print(table(Final_price_data$price_type, useNA = "ifany"))
cat("\nexpected, on the consumption extract as of 2026-10:\n")
cat("  mp25_price 191 | mp50_price 321 | mp75_price 234\n")
cat("  municipality median 1316 | province median 1262 | unique_mun_price 341\n")

stopifnot(!anyNA(Final_price_data$Price))
stopifnot(!anyNA(Final_price_data[c("province", "pull_municipal_city",
                                    "cons_name", "Unit_lbl")]))
cat("\nchecks passed: no missing price, no missing key on any row.\n")
