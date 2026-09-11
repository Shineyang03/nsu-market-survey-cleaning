r"""Proposed verdict for every no-group label whose translation group governs something.

WHAT THIS IS. A hand-written proposal, one entry per label, for the review in issue #36.
Nothing here is applied: harmonization_review.py reads this table, attaches the weight
evidence, runs the weight test where the weight test HAS standing, and writes the result
into the `to_review' sheet for a human to accept or reject.

THE CENTRAL DISTINCTION -- WHAT THE WEIGHT TEST MAY AND MAY NOT VETO.

Two different claims were previously gated the same way, and they are not the same claim:

  `per pack' vs `pack'      the SAME WORD with a preposition. Whether they denote the
                            same thing is settled by the string. If their measured
                            weights differ, that is variation WITHIN one unit -- or a
                            measurement problem -- and it is not evidence that there are
                            two units. The weight test has NO STANDING here.

  `putos' vs `pack',        DIFFERENT WORDS asserted to denote the same thing. That is a
  `piece' vs `bilog'        translation claim about the world, and the weight test can
                            and should veto it. This is why the pieces group already
                            carves out chicken and preserved-meat `bilog'.

So `fold_class' below decides whether the weight test is a gate at all:

    spelling      one word, differently spelled, spaced, punctuated or prepositioned.
                  FOLDS UNCONDITIONALLY. A weight divergence is reported as information
                  about the weighings, never as an objection.
    translation   different words claimed to share a referent. The weight test applies:
                  a within-item median ratio outside [1/RATIO_VETO, RATIO_VETO] is
                  reported as a veto and the proposal must not be accepted without a
                  stated reason to override.
    count         carries a leading count above 1. Never folds -- folding would divide
                  the implied weight by that count.
    size          carries a size qualifier with no size strata in the target group.
                  Never folds -- folding would pool two sizes.
    distinct      genuinely its own unit; nothing to fold into.
    notaunit      does not denote a quantity at all.
    field         underdetermined; needs someone who was there.

COMPARISONS ARE WITHIN ITEM, NEVER POOLED. A label used for two items has two medians
and they are not comparable -- `per pack' pools to 530 g across cabbage and fresh fish,
a number describing neither. An earlier draft flagged `per pack' on exactly that pooled
figure and was wrong twice over: the figure was an artefact, and the objection had no
standing to begin with.

THE PIECES FAMILY IS TWO SEPARATE DECISIONS, and they should be taken in order:
  1. `piece' / `pieces' / `pcs' / `per piece' are one word -- fold them together. This
     is `spelling' and is not contingent on anything.
  2. Does the resulting label join `pieces or units' alongside `bilog', `binilog' and
     `piraso'? That is `translation', per item, and the weight test applies.

`basis' -- what the proposal rests on, and therefore who should check it:

    measured    a weight comparison supports it. Check the ratio.
    structural  a fold key, the group table, or a count/size rule decides it.
    language    my reading of a Hiligaynon / Cebuano / Tagalog term, with no weight
                evidence. THIS IS THE CATEGORY TO CHECK -- being wrong here is
                undetectable from the data.
    field       needs someone who was there, or exclusion.

`action':
    group <g>   assign translation group <g>
    fold  <l>   harmonize onto another LABEL <l> (no suitable group exists)
    keep        leave ungrouped; genuinely its own unit
    notaunit    belongs in the dropped-label ledger
    manual      a count or an either/or label; handle case by case
"""

# Ratio beyond which the weight test reports a veto. Applies to `translation' rows only.
RATIO_VETO = 1.5

# label -> (action, target, fold_class, basis, why)
VERDICTS = {
    # ------------------------------------------------------------- the pieces family
    # Step 1 (spelling) is unconditional. Step 2 -- joining `pieces or units' -- is the
    # translation claim, and it is what the weight comparisons below speak to.
    "pieces": ("group", "pieces or units", "translation", "measured",
               "pork 215 g vs pieces or units 260 g (x1.21), inside the line. Drinks at "
               "restaurant carries 189 weighings and has NO other vocabulary, so nothing is "
               "pooled there. Prawns already fold. Loaf bread has no weighing of this "
               "spelling, so that item rests on step 1 alone."),
    "piece": ("group", "pieces or units", "translation", "measured",
              "pork 272.5 g (n=4) vs pieces or units 260 g (n=15), x1.05."),
    "pcs": ("group", "pieces or units", "spelling", "structural",
            "standard abbreviation of `pieces'."),
    "per piece": ("group", "pieces or units", "spelling", "structural",
                  "`per' is a preposition. Similarity to `piece' is 0.714, so no threshold "
                  "would have reached this -- it needs the word, not the score."),
    "1 pc. prawn": ("group", "pieces or units", "spelling", "structural",
                    "a leading count of 1 is redundant and `prawn' restates the item; the "
                    "fold key reduces this to `piece'."),

    # ------------------------------------------------------------- high impact
    "tama-tama nga putos": ("group", "medium packs", "translation", "measured",
                            "loaf bread, 23 weighings at median 450 g -- EXACTLY the medium "
                            "packs median (450 g, n=352); large is 640 g and small 370 g. "
                            "`tama-tama' = just right / moderate. Reading and weight agree."),
    "cone": ("keep", "small cup", "translation", "measured",
             "ice cream, 39 weighings at 110 g. NOTE HONESTLY: the weight test does NOT "
             "support keeping this apart -- 110 g against small cup's 100 g is x1.10. The "
             "separation rests on product form, a cone being a different object from a cup, "
             "and a reviewer who weights the measurement over the form should overrule me."),
    "slice": ("fold", "slice", "spelling", "structural",
              "canonical spelling of the slice/sliced pair. Chicken shows `slice' at 122.5 g "
              "(n=2) and `sliced' at 250 g (n=9) -- reported as a note on those weighings, "
              "NOT as an objection: one word does not become two because its weighings vary."),
    "sliced": ("fold", "slice", "spelling", "structural",
               "past-participle spelling of `slice'. See the note there."),
    "tub": ("keep", "small cup", "distinct", "measured",
            "ice cream, 10 weighings at 1000 g, an order of magnitude above small cup and cone."),
    "balde": ("fold", "bucket", "translation", "language",
              "`balde' is Spanish-derived Tagalog/Visayan for bucket, and `bucket' exists in "
              "the SAME item (crackers): 1500 g (n=5) vs 1065 g (n=2), x1.41 -- inside the line."),
    "per pack": ("fold", "pack", "spelling", "structural",
                 "`per pack' is `pack' with a preposition; identity is settled by the string. "
                 "Fresh fish 530 g vs pack 620 g (x0.85) is consistent but not the reason."),
    "putos (pack)": ("fold", "pack", "spelling", "structural", "already folds to `pack'."),
    "pack/ putos": ("fold", "pack", "spelling", "structural", "already folds to `pack'."),
    "putos /supot": ("fold", "pack", "spelling", "structural",
                     "already folds to `pack'; `supot' is a bag."),
    "cup": ("field", "", "field", "field",
            "2 weighings at 148 g across fresh fish, ice cream, liquor and prawns. Ice cream "
            "has a `small cup' group at 100 g, but a cup of prawns and a cup of liquor are "
            "not one object. Needs a per-item ruling."),
    "junior lapad": ("keep", "", "size", "language",
                     "`lapad' is a flat gin bottle and `junior' is the smaller format; folding "
                     "into lipid/lapad would pool two bottle sizes."),
    "big can": ("keep", "", "size", "structural",
                "`big' is a size qualifier and the cans group has no size strata."),
    "container": ("keep", "gallons", "distinct", "measured",
                  "ice cream 975 g vs gallons 950 g is close, but `container' is also used for "
                  "drinking water where it means something else. Per-item question first."),
    "patupa": ("fold", "patupa", "spelling", "language",
               "canonical spelling of patupa / patupong / patopung. 3 weighings at 935 g; the "
               "other two spellings have none."),
    "2bond": ("manual", "", "count", "structural",
              "a leading count of 2. Same class as 3bugkos and 100pcs of pandesal."),
    "pieces of fried chicken": ("keep", "pieces or units", "translation", "measured",
                                "compared against the pieces group precisely so the test can "
                                "speak: the ratio is what rejects the fold, not my say-so."),
    "refilled": ("keep", "", "distinct", "measured",
                 "drinking water, 4 weighings at 1000 g. A refill volume, not a container."),
    "papaya, mango, banana": ("notaunit", "", "notaunit", "structural",
                              "an item list, not a unit."),
    "half": ("keep", "pieces or units", "distinct", "measured",
             "cabbage, 13 weighings at 275 g vs pieces or units 655 g -- about half, which is "
             "what the label says."),

    # ------------------------------------------------------------- mid
    "sack of rice": ("keep", "", "distinct", "measured", "rice, 3 weighings at 25 kg."),
    "gin": ("keep", "", "field", "language",
            "names the drink, not a unit; 3 weighings at 350 g suggests a bottle."),
    "putos (mix vegetable)": ("keep", "", "distinct", "structural",
                              "the TARGET of the mixed-bag fold (MIX_CANON). Giving it a group "
                              "would break that fold for 10 rows of other spellings."),
    "tupperware": ("fold", "tupperware", "spelling", "structural",
                   "canonical spelling of tupperware / tupper ware."),
    "tupper ware": ("fold", "tupperware", "spelling", "structural", "spacing variant."),
    "plastic cup": ("keep", "", "field", "field",
                    "ice cream, 1 weighing at 485 g, five times the small cup median. Either a "
                    "large serving or a mis-weighing."),
    "case": ("keep", "", "distinct", "measured", "beer, 2 weighings at 4440 g."),
    "bowl": ("keep", "small cup", "distinct", "measured",
             "ice cream, 720 g vs small cup 100 g. A distinct serving vessel."),
    "baso": ("fold", "glass", "translation", "language",
             "`baso' is Tagalog/Visayan for drinking glass and `glass' exists in the same item "
             "(liquor). No co-occurring weighings, so this rests on the translation alone."),
    "glass": ("keep", "", "distinct", "language", "target of the baso fold."),
    "1 order": ("fold", "1 order", "spelling", "structural",
                "spacing variant of `1order'. `1 order' is the better spelling and should be "
                "the target; the mechanical election picks `1order' only because it is shorter."),
    "1order": ("fold", "1 order", "spelling", "structural", "run-together spelling."),
    "2 slice": ("manual", "", "count", "structural", "a leading count of 2."),
    "bucket": ("keep", "", "distinct", "language", "target of the balde fold."),
    "intestine": ("notaunit", "", "notaunit", "structural", "a cut of meat, not a unit."),
    "chicken wings": ("notaunit", "", "notaunit", "structural", "a cut, not a unit."),
    "distilled water": ("notaunit", "", "notaunit", "structural", "a product type, not a unit."),
    "1 serve": ("keep", "pieces or units", "distinct", "measured", "pork, 1 weighing at 515 g."),
    "stick": ("keep", "pieces or units", "distinct", "measured", "pork, 1 weighing at 25 g. A skewer."),
    "role": ("keep", "", "field", "language",
             "preserved meat, 250 g. Probably `roll', but the fold is untested."),
    "individual": ("keep", "small packs", "distinct", "measured",
                   "loaf bread, 60 g vs small packs 370 g. A single roll."),

    # ------------------------------------------------------------- singletons
    "1 chop": ("keep", "", "field", "language", "cabbage; a chopped portion. No weighings."),
    "1 k caltex(kabo)": ("fold", "caltex", "translation", "language",
                         "`kabo' is a dipper; `caltex' appears alone in the same item. Both "
                         "unweighed, so this rests entirely on the reading."),
    "caltex": ("keep", "", "distinct", "language", "target of the caltex(kabo) fold."),
    "1 bowl cooked": ("field", "", "field", "field",
                      "pork. `cooked' is a preparation state and cooked and raw weights differ, "
                      "so this must NOT be folded to `bowl' without a ruling."),
    "100pcs of pandesal": ("manual", "", "count", "structural", "a leading count of 100."),
    "14 tasa": ("manual", "", "count", "structural", "a leading count of 14."),
    "7 ball": ("manual", "", "count", "structural", "a leading count of 7."),
    "apa": ("fold", "cone", "translation", "language",
            "`apa' is the wafer cone in Visayan, and `cone' has 39 weighings in the same item. "
            "No weighing of `apa', so this rests on the translation."),
    "ball (tuba)": ("fold", "ball (tuba)", "spelling", "language",
                    "canonical spelling of the tuba ball family: ball (tuba) / boll / bul."),
    "boll": ("fold", "ball (tuba)", "spelling", "language",
             "misspelling of `ball'; similarity 0.571, below any usable threshold, which is "
             "why it needs a hand entry."),
    "bul": ("fold", "ball (tuba)", "spelling", "language", "misspelling of `ball'."),
    "black gallon": ("keep", "", "size", "structural",
                     "a colour qualifier distinguishing containers."),
    "4 later galon": ("manual", "", "count", "structural",
                      "a leading count of 4 plus a misspelt `litre'; a volume, not an NSU."),
    "can o lata": ("group", "cans", "translation", "language",
                   "`o' is `or': the label gives the English and Visayan names of one thing, "
                   "and `lata' is the canonical member of the cans group."),
    "cassava & malunggay leaves, paco or fern, squash leaves": (
        "notaunit", "", "notaunit", "structural", "an item list, not a unit."),
    "cassava leaves": ("notaunit", "", "notaunit", "structural", "an item, not a unit."),
    "coconut wine": ("notaunit", "", "notaunit", "structural", "the product, not a unit."),
    "cone ( dirty ice cream ) 10 pesos per cone": (
        "fold", "cone", "spelling", "structural",
        "reduces to `cone' once the parenthetical and the price are stripped."),
    "glass/shots": ("fold", "glass", "spelling", "language", "a glass or a shot; base `glass'."),
    "ice cream stick": ("keep", "", "distinct", "structural",
                        "a distinct product form; `stick' alone is used for pork."),
    "jr": ("fold", "junior lapad", "spelling", "language",
           "abbreviation of `junior' in the liquor item, where `junior lapad' has 6 weighings."),
    "mix vegetables (per tumbok)": ("fold", "mix vegetables (per tumpok)", "spelling", "language",
                                    "`tumbok' misspells `tumpok' (a heap). Similarity 0.947."),
    "mix vegetables (per tumpok)": ("keep", "", "distinct", "language",
                                    "target of the tumbok fold."),
    "mix slice of carrot": ("fold", "putos (mix vegetable)", "translation", "structural",
                            "a mixed-vegetable label; MIX_UNITS already covers the siblings "
                            "`mix slice of cabbage' and `putos /mix mix'."),
    "buskos": ("fold", "bugkos", "spelling", "language",
               "misspelling of `bugkos' (a bundle). Cabbage here, camote tops there, so they "
               "never co-occur and no weight test is possible."),
    "pack of slices": ("keep", "", "distinct", "structural",
                       "a pack OF slices is a container of portions; folding to either `pack' "
                       "or `slice' would lose one of the two."),
    "patopung": ("fold", "patupa", "spelling", "language", "spelling of `patupa'."),
    "patupong": ("fold", "patupa", "spelling", "language", "spelling of `patupa'."),
    "pieces barbeque": ("keep", "", "distinct", "structural",
                        "a barbeque stick is a distinct portion; pork already has `stick'."),
    "plastic": ("field", "", "field", "field",
                "bare `plastic', no weighing, in an item that also has `plastic bag' and "
                "`plastic cup'. Ambiguous between the two."),
    "plastic bag": ("keep", "", "distinct", "structural", "distinct from `plastic cup'."),
    "pitcher": ("keep", "bowl", "distinct", "measured", "ice cream; a vessel larger than a bowl."),
    "portion": ("field", "", "field", "field", "pork; undefined size and no weighing."),
    "putos or pack": ("manual", "", "field", "structural",
                      "an either/or label: sold by putos OR by pack. Not a spelling variant."),
    "puts or plastic": ("manual", "", "field", "structural",
                        "an either/or label, with `puts' misspelling `putos'."),
    "rice cooker cup (small)": ("fold", "small rice cooker cup", "spelling", "structural",
                                "one of three spellings with an IDENTICAL fold key; token-sorted "
                                "similarity between all three is 1.000."),
    "rice cooker cup, small": ("fold", "small rice cooker cup", "spelling", "structural",
                               "see `rice cooker cup (small)'."),
    "small rice cooker cup": ("keep", "", "distinct", "structural",
                              "target of the rice-cooker fold."),
    "small box": ("keep", "", "size", "structural",
                  "`small' is a size qualifier and no box group exists."),
    "small size plastic": ("keep", "", "size", "structural",
                           "camote; a size-qualified container with no group to join."),
    "takal ng tuba": ("keep", "", "distinct", "language",
                      "`takal' is a measure/ladle for tuba. Distinct from the ball family."),
    "tab": ("field", "", "field", "field", "drinking water; meaning unclear, no weighing."),
    "tingi tingi": ("keep", "", "field", "language",
                    "`tingi' is retail sale in small quantities -- a selling mode rather than a "
                    "fixed unit."),
    "tumpok / plastic": ("fold", "tumpok", "spelling", "structural", "already folds to `tumpok'."),
    "tumpok(pile)": ("fold", "tumpok", "spelling", "structural",
                     "already folds to `tumpok'; `(pile)' is the English gloss."),
}
