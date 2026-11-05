#!/usr/bin/env python3
"""Generates the character SVGs (menu bar template images) into the given directory.

Usage: scripts/generate-characters.py Sources/Hanare/Resources/Characters
The artwork is licensed under CC BY-NC-SA 4.0 (see LICENSE-ASSETS.md).
"""
import os
import sys

out = sys.argv[1]

HEAD = '<circle cx="14" cy="8.4" r="2.1"/>'
# Side-view ponytail tied at the back of the head with a visible narrow root, then flaring into a hanging tuft.
PONYTAIL = ('<path d="M15.3 7.0 L16.4 6.9" fill="none" stroke="#000" stroke-width="0.7" stroke-linecap="round"/>'
            '<path d="M16.3 6.4 C18.5 6.0 19.6 8.6 19.0 11.2 C18.7 12.3 18.4 13.0 18.0 13.7 '
            'C17.9 11.9 17.6 10.2 17.1 8.9 C16.9 8.3 16.6 7.8 16.3 7.5 Z"/>')
FEMALE_HEAD = '<circle cx="13.9" cy="8.3" r="2.3"/>'
TORSO = '<path d="M12.3 10.9 H15.7 L16.2 15.7 H11.8 Z"/>'
HAKAMA = '<path d="M11.7 15.4 H16.3 L18.2 21.6 H9.8 Z"/>'


def line(d, w):
    return f'<path d="{d}" fill="none" stroke="#000" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round"/>'


BOW_UP = line("M7.4 0.6 Q1.6 11 7.4 20.8", 1.3)  # strung bow held upright
STRING_REST = line("M7.4 0.6 V20.8", 0.6)
LEFT_ARM_OUT = line("M12.6 12 L4.8 11.9", 1.5)

poses = {
    # 弓構え: the bow stands in front of the body, both hands at the belly with the arrow lying
    # across them, pointing at the target. The bow's top leans away from the target.
    "yugamae": [line("M19.6 0.8 Q22 11 16.2 21", 1.3), line("M19.6 0.8 L16.2 21", 0.6),
                line("M12.6 12 L10.4 13.8 L13.8 13.4", 1.5), line("M15.4 12 L17.6 13.8 L14.8 13.4", 1.5),
                line("M14.6 13.4 H1.6", 0.8), '<path d="M0.4 13.4 L2.4 12.4 V14.4 Z"/>'],
    # 会: full draw, arrow at the mouth, right elbow drawn far back
    "kai": [BOW_UP, line("M7.4 0.6 L16.6 10.6 L7.4 20.8", 0.6), LEFT_ARM_OUT,
            line("M15.4 12 L19.8 10.4 L16.6 10.6", 1.5),
            line("M16.6 10.6 H1.8", 0.8), '<path d="M0.6 10.6 L2.6 9.6 V11.6 Z"/>'],
    # 離れ: release, the arrow leaves to the left and the right arm springs back
    "hanare": [BOW_UP, STRING_REST, LEFT_ARM_OUT, line("M15.4 12 L21.2 11.2", 1.5),
               line("M1.6 10.6 H5.2", 0.8), '<path d="M0.2 10.6 L2.2 9.6 V11.6 Z"/>',
               line("M4.4 9.6 L5.4 10.6 L4.4 11.6", 0.5)],
    # 残心: holding the form after the shot
    "zanshin": [BOW_UP, STRING_REST, LEFT_ARM_OUT, line("M15.4 12 L20.8 12.8", 1.5)],
}

for style in ["male", "female"]:
    for pose, parts in poses.items():
        body = ([FEMALE_HEAD, PONYTAIL] if style == "female" else [HEAD]) + [TORSO, HAKAMA] + parts
        svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22">\n'
               + "\n".join("  " + p for p in body) + "\n</svg>\n")
        with open(os.path.join(out, f"{style}-{pose}.svg"), "w") as f:
            f.write(svg)
print("ok")
