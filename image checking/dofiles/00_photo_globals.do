********************************************************************************
* 00_photo_globals.do -- paths for the photograph-checking subsystem
*
* Every do-file under "image checking/dofiles" starts by running this file. It runs
* the build's own 00_globals.do first, so ${data}, ${tables}, def_hetero and
* mkdir_missing all mean here exactly what they mean in the pipeline, and then adds
* the four paths that only this subsystem needs.
*
* WHY A SEPARATE GLOBALS FILE, rather than adding these to dofiles/00_shared/00_globals.do.
* That file states the rule that every external input path is defined there, and on a
* build input that rule is right. These are not build inputs: nothing under
* dofiles/ reads a photograph, and the checks here never write a build artifact. Adding
* two globals to a file that every step of both masters runs would put a subsystem's
* paths in front of 40 do-files that have no use for them. Three files under
* 90_diagnostics/ already define their own paths for the same reason.
*
* THE PHOTOGRAPHS ARE NOT COPIED INTO ${inputs}, and that is deliberate. 00_globals.do
* explains that the raw inputs were moved inside the project so a fresh clone is
* self-contained. That reasoning does not carry here: the picture folder is ~30 GB of
* JPEG, it is gitignored wherever it sits, and copying it would double the Box
* footprint of the project to no benefit. It is read where the survey team left it.
*
* CALLED BY   every do-file in this folder
*
* RUN         not directly -- it only defines paths
********************************************************************************

* The build's globals. Absolute, because these do-files do not run from dofiles/ and
* so cannot reach 00_globals.do by the relative path the pipeline's own steps use.
* `c(username)' rather than a hardcoded user, matching 00_globals.do.
global root "C:\Users\\`c(username)'\Box\Philippines Panel\01 Panel\14 NSU Market Survey"
do "${root}\Data Cleaning\dofiles\00_shared\00_globals.do"

* ---- this subsystem ------------------------------------------------------------
global imgchk    "${proj}\image checking"
global imgdo     "${imgchk}\dofiles"
global imgout    "${imgchk}\outputs"

* bridge   the id <-> filename join, and nothing else. One file, read by everything.
* tables   target lists, contact-sheet manifests, and the reconciliation output.
* qc       the hand-read verdict ledger and its validation report.
global imgbridge "${imgout}\bridge"
global imgtables "${imgout}\tables"
global imgqc     "${imgout}\qc"

foreach d in "${imgchk}" "${imgout}" "${imgbridge}" "${imgtables}" "${imgqc}" {
	mkdir_missing "`d'"
}

* ---- the photographs -----------------------------------------------------------
* Left where the survey team put them; see the header. ${photodir} holds 11,506 JPEGs
* named by the code the crosswalk keys on, ${photocw} maps that code to a submission
* KEY and a photo slot.
global photodir "${root}\NSU Market Survey Launch\data\pictures"
global photocw  "${root}\NSU Market Survey Launch\data\PSPS_NSU_Market_Survey_Photo_Crosswalk.xlsx"

confirm file "${photocw}"
