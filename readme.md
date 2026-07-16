# Custom ~Squirrel Character Model

Custom character modeled/rigged/animated in Blender (5.2.0) with Godot (4.7.1) glb scene, including project files.

## Rigged Blender Model (viewport)

![blender](readme/blender-character-screenshot.png)

## Godot Character Scene (run cycle v1)

![animation](readme/godot-character-animation.gif)

## todo

- model fixes
  - [ ] decouple bottom of shoulder belt from arm movements
  - [ ] make bone weights uniform across the pouches (double checking the pouch buttons)
- [x] implement pose library
- blender animations
  - [x] idle
  - [ ] walk
  - [x] run
  - [x] basic jump (start/cycle/land)
  - [ ] backflip
  - [ ] slide
  - [ ] rail-grind
- [ ]corresponding sound fx
- fur
  - [ ] polish tufts in Blender
  - [ ] try adding smaller hair cards and overlaying textures
    - [ ] scripting tufts, ear, and tail for wind sway
- [ ] polish godot outline shader
- [ ] shape key facial animations
- [ ] basic godot character controller for testing
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
