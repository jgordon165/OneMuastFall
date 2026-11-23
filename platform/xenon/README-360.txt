ONEMUASTFALL FOR THE XBOX 360 (XELL / LIBXENON)
===============================================

OneMuastFall (a Lua recompilation of One Must Fall: 2097) built with
LibXenon, for an Xbox 360 that boots XeLL (RGH/JTAG, or BadUpdate +
FreeMyXe launching XeLL).

No game data is included. You need your own copy of One Must Fall 2097; it
has been freeware since 1999.

1. Copy this whole "onemustfall" folder to the root of a FAT32 USB stick,
   so it holds  onemustfall.elf32  and  scripts/ ...
2. Copy all the files of your One Must Fall 2097 folder (INTRO.BK,
   FIGHTR0.AF ... FIGHTR10.AF, ARENA0.BK ..., SOUNDS.DAT, ENGLISH.DAT,
   *.PSM, *.PIC, ALTPALS.DAT, GRAPHCHR.DAT, CHARSMAL.DAT ...) into
   onemustfall/data/ .
3. Start XeLL with the stick plugged in and load onemustfall.elf32.

Controls
--------
  Controller 1 is player 1 and runs the menus; controller 2 is player 2.

  Left stick / D-pad   move, crouch, jump; move in menus
                       (back blocks, down-back blocks low)
  A or X               punch; choose in menus
  B or Y               kick
  START                choose in menus, skip the intro
  BACK                 back in menus, leave a fight

XeLL has no dashboard to go back to, so QUIT is greyed out: switch the
console off to leave.

If the data files aren't found, the screen says so and shows the folder it
looked in. A script error is shown on screen too. Both, and the folders
used, are written to onemustfall.log in the onemustfall folder.
