#!/usr/bin/env bash
# FK8 Video Converter, Mac and Linux version.
# Needs FFmpeg installed first. On a Mac: brew install ffmpeg
# Usage: bash convert.sh startup "my clip.mp4"   or   bash convert.sh film "my film.mkv"

set -euo pipefail

# ----- SETTINGS (keep in step with convert.ps1) -----
W=800; H=480
SW=848; SH=480; STARTUP_SECS=20; STARTUP_MAX=30; STARTUP_KBPS=9500
FILM_CRF=20; FILM_MAX_KBPS=3000; AUDIO_KBPS=160
FAT32_LIMIT=3700000000
# ----------------------------------------------------

command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || {
  echo "FFmpeg isn't installed. On a Mac run: brew install ffmpeg"; exit 1; }

ask() { local a; read -r -p "$1 [$2]: " a || true; echo "${a:-$2}"; }

PRESET=""
case "${1:-}" in startup) PRESET=1; shift;; film) PRESET=2; shift;; esac
IN="${1:-}"
if [ -z "$IN" ]; then read -r -p "Drag the video into this window, then press Enter: " IN; fi
IN="${IN%\'}"; IN="${IN#\'}"; IN="${IN%\"}"; IN="${IN#\"}"
[ -f "$IN" ] || { echo "Can't find: $IN"; exit 1; }

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN" | head -1)
DUR=${DUR%.*}; DUR=${DUR:-0}
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$IN" | head -1)
FPS_INT=$(awk -F/ '{ if ($2+0 > 0) printf "%d", $1/$2; else printf "%d", $1 }' <<<"${FPS:-0}")
AUDIO_COUNT=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$IN" | wc -l | tr -d ' ')

echo; echo "Source: $(basename "$IN")  ($((DUR/60)) min $((DUR%60)) s)"; echo
if [ -n "$PRESET" ]; then MODE=$PRESET; else
echo "What are you making?"
echo "  1  Startup video (short clip that plays when the car starts)"
echo "  2  Film or long video (plays from USB when parked)"
MODE=$(ask "Type 1 or 2" 1)
fi
echo; echo "How should it fit the screen?"
echo "  1  Fill the screen (trims the edges if the shape is different)"
echo "  2  Show the whole picture (adds black bars)"
if [ "$MODE" = 2 ]; then FIT=$(ask "Type 1 or 2" 2); else FIT=$(ask "Type 1 or 2" 1); fi

[ "$MODE" = 2 ] || { W=$SW; H=$SH; }
if [ "$FIT" = 1 ]; then
  VF="scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,setsar=1"
else
  VF="scale=$W:$H:force_original_aspect_ratio=decrease,pad=$W:$H:(ow-iw)/2:(oh-ih)/2,setsar=1"
fi

BASE="${IN%.*}"
COMMON=(-sn -dn -map_chapters -1 -map_metadata -1 -movflags +faststart)
VCODEC=(-c:v libx264 -profile:v baseline -level 3.1 -pix_fmt yuv420p)

if [ "$MODE" = 2 ]; then
  OUT="${BASE}_car.mp4"
  PICK=-1
  if [ "$AUDIO_COUNT" -gt 0 ]; then
    PICK=0
    LANGS=$(ffprobe -v error -select_streams a -show_entries stream_tags=language -of csv=p=0 "$IN")
    i=0; while read -r lang; do [ "$lang" = eng ] && { PICK=$i; break; }; i=$((i+1)); done <<<"$LANGS"
    if [ "$AUDIO_COUNT" -gt 1 ]; then
      echo; echo "This file has more than one soundtrack:"
      ffprobe -v error -select_streams a -show_entries stream=codec_name,channels:stream_tags=language -of csv=p=0 "$IN" | nl
      N=$(ask "Which one" $((PICK+1)))
      if [[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le "$AUDIO_COUNT" ]; then PICK=$((N-1)); fi
    fi
  fi
  MAX=$FILM_MAX_KBPS
  if [ "$DUR" -gt 0 ]; then
    FITS=$(( FAT32_LIMIT * 8 / DUR / 1000 - AUDIO_KBPS ))
    if [ "$FITS" -lt "$MAX" ]; then MAX=$FITS; echo "Long film: lowering the bitrate to $MAX kbps so the file stays under 4 GB."; fi
  fi
  [ "$FPS_INT" -gt 30 ] && VF="$VF,fps=30"
  ARGS=(-i "$IN" -map 0:v:0)
  [ "$PICK" -ge 0 ] && ARGS+=(-map "0:a:$PICK")
  ARGS+=(-vf "$VF" "${VCODEC[@]}" -preset medium -crf "$FILM_CRF" -maxrate "${MAX}k" -bufsize "$((MAX*2))k")
  [ "$PICK" -ge 0 ] && ARGS+=(-c:a aac -b:a "${AUDIO_KBPS}k" -ac 2 -ar 48000)
else
  OUT="${BASE}_startup.mp4"
  echo
  START=$(ask "Start the clip at (seconds, or mm:ss)" 0)
  LEN=$(ask "Clip length in seconds (max $STARTUP_MAX)" $STARTUP_SECS)
  [[ "$LEN" =~ ^[0-9]+$ ]] && [ "$LEN" -gt 0 ] || LEN=$STARTUP_SECS
  [ "$LEN" -gt "$STARTUP_MAX" ] && LEN=$STARTUP_MAX
  SOUND=$(ask "Keep the sound? (y/n)" y)
  ARGS=(-ss "$START" -i "$IN" -t "$LEN" -map 0:v:0)
  KEEP=0; [[ "$SOUND" =~ ^[yY] ]] && [ "$AUDIO_COUNT" -gt 0 ] && KEEP=1
  [ "$KEEP" = 1 ] && ARGS+=(-map 0:a:0)
  [ "$FPS_INT" -gt 30 ] && VF="$VF,fps=30"
  ARGS+=(-vf "$VF" -c:v mpeg4 -vtag mp4v -bf 0 -pix_fmt yuv420p -b:v "${STARTUP_KBPS}k" -maxrate "$((STARTUP_KBPS*6/5))k" -bufsize "$((STARTUP_KBPS*2))k")
  [ "$KEEP" = 1 ] && ARGS+=(-c:a aac -b:a 192k -ac 2 -ar 44100)
fi

echo; echo "Converting..."
ffmpeg -hide_banner -loglevel warning -stats -y "${ARGS[@]}" "${COMMON[@]}" "$OUT" </dev/null

echo; echo "Done. Saved: $OUT"
echo "Copy it to a FAT32 USB stick and plug it into the car."
