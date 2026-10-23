# Custom ~Squirrel Character Model

Custom character modeled/rigged/animated in Blender (5.2.0) with Godot (4.7.1) glb scene, including project files.

## Movement playground

Press **F6** with `scenes/playground.tscn` open, or **F5** to run the project. The scene includes jump steps, a ramp/drop, a low slide tunnel, a holdable wall, and a zipline. All obstacles are ordinary scene nodes that can be moved in the editor.

| Control | Action |
| --- | --- |
| WASD / arrow keys | Move relative to the camera |
| Mouse | Orbit the camera |
| Space | Jump, then double jump in the air; release early for a shorter jump |
| Right mouse button | Hold to blend crossbow aim while idle, running, jumping, or sliding |
| Shift | Dash in the movement direction, or camera-forward when stationary |
| Hold Ctrl / C | Slide above the speed threshold; also queues a slide on landing |
| Move toward a wall while airborne | Grip automatically and fall slowly; Space bounces, moving away releases |
| E near the cable start above the teal platform | Ride the zipline; Space jumps off early |
| R | Reset position |
| Esc / left click | Release / capture the mouse |

The controller uses Deadlock-inspired momentum: dash-jumps, dash-slides, and slide-jumps carry horizontal speed. Default running speed is 5.5 m/s; sliding requires at least 6 m/s and adds no entry boost. Flat ground slows slides, while slopes affect their speed. Dashes start at 13 m/s for 0.2 seconds with a 0.65-second cooldown and a limit of one air dash per airtime. Landing restores the extra jump and air dash.

Automatic wall grips damp vertical velocity and cap descent at 1.5 m/s. Wall bounces preserve incoming dash speed, briefly protect the outward impulse from air steering, and work independently of the double jump. Consecutive bounces require a different wall normal or landing first. The capsule stays crouched under ceilings until there is room to stand.

`scenes/character.tscn` is a reusable `CharacterBody3D` with its own controller, collision capsules, camera arm, and animation tree. Movement, slide, dash, wall, and camera tuning is exposed in the root inspector. World geometry uses collision layer 1; the character uses layer 2. Any near-vertical solid wall supports airborne grips. Additional ziplines use `scripts/zipline.gd`, the `ziplines` group, and `Start`/`End` markers at cable height; `hang_offset` sets the character's distance below the cable.

The animation graph is built by `scripts/character_animation.gd` at runtime, leaving the imported GLB clips unchanged:

- The exported `idle1` loops while stationary; `idle` and `idle_loop` are also recognized. If no authored idle is exported, the controller supplies a small breathing cycle from `basis`. `run` follows movement speed.
- `jumpStart`, `falling`, and `jumpLand` follow takeoff, airborne motion, and ground contact.
- `wallHolding` and `zipping` correspond to their movement modes. Double jumps and wall bounces restart `jumpStart`.
- Dashes temporarily reuse `run` on the ground and `falling` in the air. Sliding plays the restored, authored `sliding` loop.
- `crossbow_aim` fades over locomotion through a filtered `AnimationNodeBlend2`. Its mask follows the `ORG-shoulder.R` subtree and the neck/head subtrees (`DEF-spine.004`, `neck`, `head`). Hips, legs, torso, tail, and left arm retain the movement animation. Wall holding and zipping fade aim out so their hand poses remain available.

The graph uses [Godot's animation track filtering](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html#blend2-blend3). The HUD shows the current movement clip and aim weight.

Run the movement and bone-isolation checks with:

```powershell
godot_console --headless --path . --fixed-fps 60 --script tests/playground_test.gd
```

For rendered verification images in `.godot/`, omit `--headless` and append `-- --screenshots`.

### Idle and slide recovery

`SquirrelLady.blend` now contains independent `idle1-loop` and `sliding-loop` Actions, and each NLA strip points to its own Action. The reconstructed idle's curves are preserved. The slide was recovered from commit `6633b19` (2026-10-22), where its curves were stored in the shared Action named `idle1-loop`. Its keyed loop is frames 1–15; the old frame-40 hold remains in the source curves outside its explicit export range. The GLB exports both clips separately, with duplicate idle channels removed.

`tools/recover_slide.py` performs the recovery through Blender's Python API and checks that every pre-existing Action's keyframes, handles, and interpolation stay unchanged. Pre-recovery working files and the validation report are retained locally in `.godot/animation_recovery/`. When creating another animation, give its NLA strip a separate Action data-block before editing keyframes.

## Rigged Blender Model (viewport)

![blender](readme/blender-character-screenshot.png)

## Godot Character Scene (run cycle v1)

![animation](readme/godot-character-animation.gif)

![crossbow aim](readme/godot-character-crossbowAim-screenshot.png)
## todo

- model fixes
  - [ ] finish decoupling bottom of shoulder belt from arm movements
  - [x] make bone weights uniform across the pouches(double checking the pouch buttons)
  - [x] add extra jiggle bones
- [x] implement pose library
- blender animations
  - [x] idle
  - [ ] walk
  - [x] run
  - [x] basic jump (start/cycle/land)
  - [ ] backflip
  - [ ] slide
  - [ ] rail-grind
- [ ] corresponding sound fx
- fur
  - [ ] polish tufts in Blender
  - [ ] try adding smaller hair cards and overlaying textures
    - [ ] scripting tufts, ear, and tail for wind sway
- [ ] polish godot outline shader
- [ ] shape key facial animations
- [x] basic godot character controller for testing
- [ ] evaluate bone export types for data/profiler overhead
  - [ ] clean keyframes

## External Resources

Codernunk 3D Character Guide ([YT link](https://youtu.be/dd6G2S6MQ6U))

## Vibe character toon material

Codernunk pipeline is a bit broken from the apparent disappearance of the github repo for hijacking the vertex color channels to control character outline settings from Blender to Godot, so the material was vibed out as a Godot shader material with a palette texture and outline pass.  Here is the llm description of the material:

`toon_material.tres` combines two passes:

- `toon.gdshader` draws the palette texture with a hard light/shadow split.
- `outline.gdshader` draws expanded back faces as a screen-space outline.

The material is already assigned to surface 0 of `anime_squirrel_test.tscn`.
When the GLB is re-exported from Blender, keep the imported mesh node named `model`,
or reassign `toon_material.tres` as that mesh's **Material Override**.

Useful material parameters:

- **Shadow Tint** controls the cool color on faces turned away from a light.
- **Shadow Threshold** moves the light/shadow boundary.
- **Shadow Softness** changes the edge from crisp to slightly feathered.
- **Ambient Strength** keeps the character readable outside direct light.
- In **Next Pass**, **Outline Width** is measured in screen pixels and
  **Outline Color** controls the ink color.

### todo

- fix idle and slide deleting each other
- move camera over the shoulder so crosshairs aren't blocked by the character
- make dedicated double jump jump animation
- same for wall bounce, dash, dash jump, quick melee, and heavy melee
