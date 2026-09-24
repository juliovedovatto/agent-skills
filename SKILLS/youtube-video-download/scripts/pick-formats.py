"""Read yt-dlp -J JSON from stdin, print one pipe-delimited line: video_id|video_fmt|short_edge|video_codec|video_width|video_real_height|audio_fmt|audio_lang|audio_note|audio_warn."""
import json, sys

data = json.load(sys.stdin)
vid = data.get("id", "unknown")
formats = data.get("formats", [])

def short_edge(f):
    w = f.get("width") or 0
    h = f.get("height") or 0
    return min(w, h) if (w and h) else (w or h or 0)

best = None
for f in formats:
    if f.get("ext") == "mp4" and str(f.get("vcodec", "")).startswith("avc1"):
        s = short_edge(f)
        if s <= 1080 and (best is None or s > short_edge(best)):
            best = f

warn_avc = best is None
if best is None:
    for f in formats:
        s = short_edge(f)
        if s <= 1080 and (best is None or s > short_edge(best)):
            best = f

vfmt = best.get("format_id", "") if best else ""
vshort = ""
vwidth = ""
vrealheight = ""
if best:
    _s = short_edge(best)
    vshort = str(_s) if _s else ""
    vwidth = str(best.get("width") or "")
    vrealheight = str(best.get("height") or "")
vcodec = best.get("vcodec", "") if best else ""
if warn_avc and best:
    vcodec = vcodec + "+WARN:no-avc1"

# "original" marks the original (default) track, not an auto-dub.
# Some player APIs omit the note — fall back to the video's own language,
# highest bitrate, which is the original track there too (dubs carry other langs).
afmt = ""
alang = ""
anote = ""
awarn = ""
orig = None
for f in formats:
    if f.get("ext") == "m4a":
        note = f.get("format_note", "") or ""
        if "original" in note:
            orig = f
            break
video_lang = (data.get("language") or "").split("-")[0]
if orig is None and video_lang:
    for f in formats:
        if f.get("ext") == "m4a" and (f.get("language") or "").split("-")[0] == video_lang:
            if orig is None or (f.get("abr") or 0) > (orig.get("abr") or 0):
                orig = f
if orig:
    afmt = orig.get("format_id", "")
    alang = orig.get("language", "") or ""
    anote = orig.get("format_note", "") or ""
else:
    awarn = "WARN:no-original-audio"

# Pipe-delimited to survive spaces in note/codec fields.
print("|".join([vid, vfmt, vshort, vcodec, vwidth, vrealheight, afmt, alang, anote, awarn]))