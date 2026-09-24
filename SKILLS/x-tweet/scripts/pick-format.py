#!/usr/bin/env python3
"""pick-format.py — stdin: yt-dlp -j JSON → stdout: yt-dlp format selector.

Outputs a single format selector string for the best video ≤1080p
plus the best audio. Video and audio are selected independently so
yt-dlp merges them into a single mp4 with both tracks.
"""
import json, sys

try:
    data = json.load(sys.stdin)
except Exception:
    print("best[ext=mp4][height<=1080]/best")
    sys.exit(0)

formats = data.get("formats", [])

# Best video ≤1080p — vcodec must be present and not 'none' (covers avc1, h264, etc.)
best_v = None
for f in formats:
    vc = f.get("vcodec")
    if not vc or vc == "none":
        continue
    h = f.get("height") or 0
    if h > 1080:
        continue
    tbr = f.get("tbr") or f.get("vbr") or 0
    if best_v is None:
        best_v = f
    else:
        bh = best_v.get("height") or 0
        btbr = best_v.get("tbr") or best_v.get("vbr") or 0
        if h > bh or (h == bh and tbr > btbr):
            best_v = f

# Best audio — vcodec == 'none' (audio-only stream), pick highest abr
# acodec may be null for HLS audio-only fragments; vcodec=='none' is the reliable signal
best_a = None
for f in formats:
    vc = f.get("vcodec")
    if vc != "none":
        continue
    ac = f.get("acodec")
    if ac == "none":
        continue
    abr = f.get("abr") or f.get("tbr") or 0
    if best_a is None or abr > (best_a.get("abr") or best_a.get("tbr") or 0):
        best_a = f

v_id = best_v.get("format_id", "") if best_v else ""
a_id = best_a.get("format_id", "") if best_a else ""

if v_id and a_id:
    print(f"{v_id}+{a_id}")
elif v_id:
    print(v_id)
else:
    print("best[ext=mp4][height<=1080]/best")