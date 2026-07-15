# Character toon material

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
