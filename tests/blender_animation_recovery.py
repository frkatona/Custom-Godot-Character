"""Run in background Blender with --python-exit-code 1.

Example: blender --background SquirrelLady.blend --python-exit-code 1
         --python tests/blender_animation_recovery.py -- --report REPORT.json
The optional report verifies exact curve preservation from the recovery run.
"""

import argparse
import json
from pathlib import Path
import sys

import bpy

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from recover_slide import action_digest

parser = argparse.ArgumentParser()
parser.add_argument("--report")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
rig = bpy.data.objects["rigify_rig"]
idle = bpy.data.actions["idle1-loop"]
slide = bpy.data.actions["sliding-loop"]
tracks = {track.name: track for track in rig.animation_data.nla_tracks}
assert tracks["idle1-loop"].strips[0].action == idle
assert tracks["sliding-loop"].strips[0].action == slide
assert idle != slide, "Idle and slide must have independent Action data-blocks"
assert action_digest(idle) != action_digest(slide), "Idle and slide must contain different animation data"
assert sum(strip.action == idle for track in tracks.values() for strip in track.strips) == 1
assert sum(strip.action == slide for track in tracks.values() for strip in track.strips) == 1
assert list(slide.frame_range) == [1.0, 15.0]
assert slide.use_fake_user
if args.report:
    report = json.loads(Path(args.report).read_text())
    for name, digest in report["preserved_action_sha256"].items():
        assert action_digest(bpy.data.actions[name]) == digest, "Changed original Action: " + name
    assert action_digest(slide) == report["recovered_curve_sha256"]
    print("PASS: All original authored curves preserved; recovered curves match history")
print("PASS: Independent idle/slide Actions, correct NLA references, and short slide loop survive saving/reopening")
