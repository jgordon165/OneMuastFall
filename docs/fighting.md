# How a fight works

The fighting code is Lua: `scripts/game/har.lua` (the robots),
`scripts/scenes/arena.lua` (the match), `scripts/game/ai.lua` (the computer
opponent), on top of `scripts/core/player.lua` (the animation player every
object shares). The rules follow OpenOMF's `har.c` / `arena.c`, which were
matched against the original program; numbers below are theirs.

## Everything is an animation

A HAR always plays one of its AF moves. Idle (11), walking (10), jumping
(1), crouching (4), blocking (5, 6), getting hit (9), standing up (2),
stunned (3), victory (48), defeat (49) are moves like the attacks. The
move's animation script drives the sprites, the sounds, the forward
motion (`x+`, `v`), when it can hit (`q`), what can chain from it (`j*`
tags) and what it spawns (`m`: projectiles, effects).

When a HAR is hit, it plays its damage move with the **attacker's move's
footer string** as the script: each attack carries its victim's reaction.
Throws work the same way: the footer holds the victim at the thrower
(`e`) while the thrower's script carries them.

## A tick

Arena ticks are 8 + 60 − rate × 4 ms, where rate is the SPEED setting
(0..10 in GAMEPLAY, default 5) plus 5, as in OpenOMF: 28 ms at the
default. Each tick:

1. the arena: push overlapping HARs apart, round state (fade in, READY /
   ROUND n, FIGHT at tick 90; after a KO, victory pose, YOU WIN / LOSE,
   fade out)
2. input: each controller gives its HAR the stick (a numpad digit) and
   whether punch / kick were pressed
3. every object advances its script
4. physics: HARs walk, jump (gravity from the AF's fall speed), land, hit
   the walls (x 20..300) and the floor (y 190); projectiles fly
5. collisions: HAR against HAR, projectiles against the enemy HAR
6. every object applies its frame

A hit with the `cp` tag pauses the game for 4 ticks; a KO slows the next
12 ticks to rate − 10 (68 ms).

## Moves from the stick

Each tick the stick direction goes into a 10-entry buffer (newest first,
only when it changes); positions the stick passed through between two
ticks go in too, so a fast motion isn't lost. A move string like `P6321` means: punch, with the
newest directions being 6, 3, 2, 1 (a quarter circle forward from back,
then punch), relative to where the HAR faces. Moves are tried in id order;
punch and kick stay "pressed" for 3 ticks, and the motion has to be
entered with no more than 9 ticks between directions. A move can start
from standing / crouching / in the air by its category, or from inside
another move when that frame allows it (`jl`, `jm`, `jh`, `jj`, `jn`...).

Without a move, the stick moves the HAR: 4/6 walk, 1/2/3 crouch (1 also
blocks), 7/8/9 jump. Jumping out of a crouch goes higher.

## Hits

A move's collision points belong to its sprites. A hit is a point of the
attacker's current sprite landing on a solid pixel of the defender's
current sprite (only the HAR's own colours, indices below 96, count).
Throws (category CLOSE) hit when the enemy is within the move's reach.

Holding back (4) blocks high and mid attacks, down-back (1) low ones;
throws can't be blocked. A block plays the block move for the move's
block stun and pushes the defender back.

Damage = base × (20 + pilot power) / 30 + 1; juggling hits (in the air
after a hit) do two thirds more. Stun ("endurance") fills with every hit and drains over time,
fastest while idle; over the limit the HAR is knocked down and comes up
dizzy, and mashing buttons wakes it sooner. Health and stun scale with the
pilot's endurance, speeds and jumps with agility.

## The HUD

Health (8 px) and stun (4 px, flashes under half) bars at the top, pilot
and HAR names under them, round tokens beside them (BK animation 27).

## Not done yet

* the original's HAR select (MELEE.BK), the vs screen, tournament mode,
  scrap/destruction finishing moves' full flow, score and points
* arena hazards (the stadium's lights, the power plant's walls, the
  desert's planes...) and wall damage
* HAR shadows, screen shake, the stadium's positional lighting,
  HAR palette flashes (`ptd`/`ptr`/`ptp`)
* rehit/juggle settings, hyper mode, the pause menu
* an AI as clever as the original's
