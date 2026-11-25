ONEMUASTFALL FOR THE XBOX 360 (.XEX)
====================================

OneMuastFall (a Lua recompilation of One Must Fall: 2097) built as an Xbox
360 title (onemustfall.xex) with xsdk (openpak/x360-sdk). It runs on a
console that runs unsigned code: BadUpdate with FreeMyXe (or XeUnshackle),
an RGH or a JTAG. Launch it from the dashboard, Aurora or a file manager.

No game data is included. You need your own copy of One Must Fall 2097; it
has been freeware since 1999.

1. Copy this whole "onemustfall" folder to a USB stick (FAT32) or the hard
   drive, so it holds  onemustfall.xex  and  scripts/ ...
2. Copy all the files of your One Must Fall 2097 folder (INTRO.BK,
   FIGHTR0.AF ... FIGHTR10.AF, ARENA0.BK ..., SOUNDS.DAT, ENGLISH.DAT,
   *.PSM, *.PIC, ALTPALS.DAT, GRAPHCHR.DAT, CHARSMAL.DAT ...) into
   onemustfall/data/ . A DOSBox copy of the game has them in its game folder.
3. Launch onemustfall.xex.

Controls
--------
  Controller 1 is player 1 and runs the menus; controller 2 is player 2.

  Left stick / D-pad   move, crouch, jump; move in menus
                       (back blocks, down-back blocks low)
  A or X               punch; choose in menus
  B or Y               kick
  START                choose in menus, skip the intro
  BACK                 back in menus, leave a fight

Special moves are entered as in the original: a stick motion, then punch
or kick.

To leave, choose QUIT on the main menu (BACK there jumps to it). The title
stops its sound and ends; the console goes to its default dashboard (Aurora
or FreeStyle if DashLaunch makes it the default).

To leave to a particular dashboard or program instead, put its .xex path in
dashboard.txt (next to onemustfall.xex), e.g.  Usb0:\Aurora\default.xex  or
Hdd:\Aurora\default.xex . Drives: Usb0:, Usb1:, Usb2:, Hdd:, game: (the
onemustfall folder) or a full \Device\... path. "default" (as shipped), an
empty file or no file means the default dashboard; so does a path whose
file isn't there (the log says so).

Aurora art
----------
The aurora/ folder has OneMuastFall's own pictures at Aurora's asset sizes:
icon.png (64x64), banner.png (420x96), boxart.png (900x600) and
background.png (1280x720). OneMuastFall has its own title ID (4F4D4632,
"OMF2"), so in Aurora you can give it these as its assets (from the game's
asset options, loading the images from the USB stick) without them showing
on other homebrew titles.

If something goes wrong
-----------------------
If the data files aren't found, the screen says so and shows the folder it
looked in. A script error is shown on screen too (START or BACK exits).
Both, and the folders used, are written to onemustfall.log next to
onemustfall.xex.
