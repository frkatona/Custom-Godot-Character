"""Run with Blender --background --python tools/recover_slide.py -- [arguments].

Append the historical slide action into the latest character file and repair the
NLA strip's shared-action reference. Inputs are never overwritten by this tool.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy


def action_digest(action):
    """Fingerprint authored curves, including handles and interpolation."""
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    curves.append({
                        "path": curve.data_path,
                        "index": curve.array_index,
                        "extrapolation": curve.extrapolation,
                        "keys": [{
                            "co": list(key.co),
                            "left": list(key.handle_left),
                            "right": list(key.handle_right),
                            "interpolation": key.interpolation,
                            "left_type": key.handle_left_type,
                            "right_type": key.handle_right_type,
                            "easing": key.easing,
                        } for key in curve.keyframe_points],
                    })
    curves.sort(key=lambda curve: (curve["path"], curve["index"]))
    return hashlib.sha256(json.dumps(curves, sort_keys=True).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--current", required=True)
    parser.add_argument("--history-file", required=True)
    parser.add_argument("--source-action", default="idle1-loop")
    parser.add_argument("--source-commit", default="6633b19")
    parser.add_argument("--output", required=True)
    parser.add_argument("--export", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    current, output = Path(args.current).resolve(), Path(args.output).resolve()
    if output == current or output.exists() or Path(args.export).exists():
        raise RuntimeError("Use new output paths; the recovery tool preserves all inputs.")
    # Keeping the Blend beside the input preserves every relative asset path.
    if output.parent != current.parent:
        raise RuntimeError("The recovered Blend must be saved beside the current Blend.")

    bpy.ops.wm.open_mainfile(filepath=str(current))
    rig = bpy.data.objects["rigify_rig"]
    idle = bpy.data.actions["idle1-loop"]
    original_actions = {action.name: action_digest(action) for action in bpy.data.actions}
    original_objects = sorted(obj.name for obj in bpy.data.objects)
    if bpy.data.actions.get("sliding-loop") is not None:
        raise RuntimeError("A sliding-loop action already exists; inspect it before recovering again.")
    with bpy.data.libraries.load(str(Path(args.history_file).resolve()), link=False) as (available, loaded):
        if args.source_action not in available.actions:
            raise RuntimeError("Historical slide action not found.")
        loaded.actions = [args.source_action]
    slide = loaded.actions[0]
    recovered_digest = action_digest(slide)
    slide.name = "sliding-loop"
    slide.use_fake_user = True
    # The keyed slide cycle is 1 -> 8 -> 15. Frame 40 is an old held tail.
    # Keep every original curve/key, but export only the actual loop.
    slide.use_frame_range = True
    slide.frame_start = 1.0
    slide.frame_end = 15.0
    slide.use_cyclic = True
    track = next(track for track in rig.animation_data.nla_tracks if track.name == "sliding-loop")
    if len(track.strips) != 1:
        raise RuntimeError("Expected one slide strip; inspect this NLA track manually.")
    nla_strip = track.strips[0]
    nla_strip.action = slide
    nla_strip.action_slot = slide.slots[0]
    nla_strip.name = "sliding-loop"
    nla_strip.action_frame_start = 1.0
    nla_strip.action_frame_end = 15.0
    nla_strip.repeat = 1.0
    nla_strip.scale = 1.0
    nla_strip.frame_end = nla_strip.frame_start + 14.0
    idle_strip = next(track for track in rig.animation_data.nla_tracks if track.name == "idle1-loop").strips[0]
    assert idle_strip.action == idle and nla_strip.action != idle
    assert action_digest(slide) == recovered_digest

    # Match the character's stored glTF export choices: selected rig/mesh,
    # all actions, all bones, no embedded materials (Godot overrides those).
    export_settings = bpy.context.scene.get("glTF2ExportSettings").to_dict()
    export_settings.update(filepath=str(Path(args.export).resolve()), export_format="GLB")
    print("RECOVERY_EXPORT_SELECTION", [obj.name for obj in bpy.context.selected_objects])
    bpy.ops.export_scene.gltf(**export_settings)
    for name, digest in original_actions.items():
        assert action_digest(bpy.data.actions[name]) == digest, "Changed existing action: " + name
    assert sorted(obj.name for obj in bpy.data.objects) == original_objects
    assert action_digest(slide) == recovered_digest
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report = {
        "source_commit": args.source_commit,
        "source_action": args.source_action,
        "recovered_action": slide.name,
        "recovered_curve_sha256": recovered_digest,
        "idle_curve_sha256": original_actions[idle.name],
        "preserved_action_sha256": original_actions,
        "slide_export_frames": [slide.frame_start, slide.frame_end],
        "idle_export_frames": list(idle.frame_range),
        "independent_actions": nla_strip.action != idle_strip.action,
        "blend": str(output),
        "glb": str(Path(args.export).resolve()),
    }
    Path(args.export).with_suffix(".recovery.json").write_text(json.dumps(report, indent=2) + "\n")
    print("RECOVERY_VERIFIED", json.dumps(report))


if __name__ == "__main__":
    main()
