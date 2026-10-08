#!/usr/bin/env bash
# converter-h265-linux-resolve — Convierte lote XAVC HS H.265 4:2:2 10-bit (Sony a6700)
# a DNxHR / ProRes editable en DaVinci Resolve Free (Linux).
#
# Uso:
#   ./convert-to-resolve.sh [CARPETA_ENTRADA] [CARPETA_SALIDA] [--profile hqx|hq|sq|lb|prores-lt] [--no-gui]
#   Sin argumentos abre seleccion visual (zenity si hay DISPLAY, si no terminal).
#
# Reglas:
#   - Procesa toda la carpeta de entrada (*.MP4, *.mov, *.MXF...).
#   - Mantiene el nombre original: C0055.MP4 -> C0055.mov
#   - Si no eliges salida, crea ENTRADA/RESOLVE_READY/
#   - Copia los XML laterales de Sony (C0055M01.XML) como referencia.
#
# Requisitos: ffmpeg + ffprobe. Opcional: zenity (Fedora/GNOME).
set -u

DEFAULT_PROFILE="hqx"

profile_from_arg() {
  case "${1:-}" in
    hqx|dnxhr_hqx|hqx10) echo "hqx" ;;
    hq|dnxhr_hq) echo "hq" ;;
    sq|dnxhr_sq) echo "sq" ;;
    lb|dnxhr_lb) echo "lb" ;;
    prores-lt|prores_lt|plt) echo "prores-lt" ;;
    *) echo "" ;;
  esac
}

PROFILE="$DEFAULT_PROFILE"
NO_GUI=0
INPUT_DIR=""
OUTPUT_DIR=""

for arg in "$@"; do
  case "$arg" in
    --no-gui) NO_GUI=1; continue ;;
    --profile=*|--*) continue ;;
  esac
  [ -n "$(profile_from_arg "$arg")" ] && { PROFILE="$(profile_from_arg "$arg")"; continue; }
  if [ -z "$INPUT_DIR" ]; then INPUT_DIR="$arg";
  elif [ -z "$OUTPUT_DIR" ]; then OUTPUT_DIR="$arg";
  fi
done
for arg in "$@"; do
  case "$arg" in
    --profile=*) q="$(profile_from_arg "${arg#--profile=}")"; [ -n "$q" ] && PROFILE="$q" ;;
  esac
done
# Valida: si INPUT no es dir, era un flag mal puesto -> reset para preguntar visual
[ -n "$INPUT_DIR" ] && [ ! -d "$INPUT_DIR" ] && [ ! -e "$INPUT_DIR" ] && {
  # Podria ser OUTPUT inexistente pasado como 1er arg; si no es dir, lo ignoramos y preguntamos
  case "$INPUT_DIR" in --*) INPUT_DIR="" ;; *) [ ! -d "$INPUT_DIR" ] && INPUT_DIR="" ;; esac
}

HAS_ZENITY=0
if [ "$NO_GUI" -eq 0 ] && command -v zenity >/dev/null 2>&1 && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  HAS_ZENITY=1
fi

msg_info()  { if [ "$HAS_ZENITY" -eq 1 ]; then zenity --info --width=440 --text="$1" 2>/dev/null; else printf '%s\n' "$1"; fi; }
msg_error() { if [ "$HAS_ZENITY" -eq 1 ]; then zenity --error --width=460 --text="$1" 2>/dev/null; else printf 'ERROR: %s\n' "$1" >&2; fi; }

ask_dir() {
  local title="$1" start="${2:-$HOME}"
  if [ "$HAS_ZENITY" -eq 1 ]; then
    zenity --file-selection --directory --title="$title" --filename="$start/" 2>/dev/null || true
  else
    printf '%s\n  [Ruta, o Enter para usar: %s]\n> ' "$title" "$start" >&2
    read -r ans || true
    if [ -z "${ans:-}" ]; then printf '%s' "$start"; else printf '%s' "$ans"; fi
  fi
}

ask_profile() {
  if [ "$HAS_ZENITY" -eq 1 ]; then
    zenity --list --radiolist --title="Calidad de conversion" --width=580 --height=380 \
      --text="Original: HEVC 4:2:2 10-bit. Resolve Free Linux NO lee H.265.\nElige intermedio:" \
      --column="" --column="Perfil" --column="Detalle" \
      TRUE  "hqx"       "DNxHR HQX 10-bit 422 - max calidad S-Log3 - ~5-7x peso (recomendado)" \
      FALSE "hq"        "DNxHR HQ 8-bit 422 - alta calidad - ~3-4x peso" \
      FALSE "sq"        "DNxHR SQ 8-bit 422 - estandar - ~2x peso" \
      FALSE "lb"        "DNxHR LB 8-bit 422 - proxy liviano" \
      FALSE "prores-lt" "ProRes 422 LT 10-bit - alternativo liviano - ~2-3x peso" 2>/dev/null || echo "$PROFILE"
  else
    echo "Perfil actual: $PROFILE (hqx=10-bit max calidad, hq/sq/lb=8-bit livianos, prores-lt=alternativo)" >&2
    printf 'Enter para aceptar, o escribe hqx|hq|sq|lb|prores-lt:\n> ' >&2
    read -r ans || true
    q="$(profile_from_arg "${ans:-}")"
    if [ -n "$q" ]; then echo "$q"; else echo "$PROFILE"; fi
  fi
}

if ! command -v ffmpeg >/dev/null 2>&1; then msg_error "No se encontro ffmpeg. Instalalo: sudo dnf install ffmpeg"; exit 1; fi
if ! command -v ffprobe >/dev/null 2>&1; then msg_error "No se encontro ffprobe (viene con ffmpeg)."; exit 1; fi

# Si el perfil vino por CLI no preguntar; si no, preguntar visual.
PROFILE_FROM_CLI=0
for arg in "$@"; do
  [ -n "$(profile_from_arg "$arg")" ] && PROFILE_FROM_CLI=1
  case "$arg" in --profile=*) PROFILE_FROM_CLI=1 ;; esac
done
if [ "$PROFILE_FROM_CLI" -eq 0 ]; then
  if [ "$HAS_ZENITY" -eq 1 ] || [ -t 0 ]; then
    chosen="$(ask_profile)"
    q="$(profile_from_arg "$chosen")"
    [ -n "$q" ] && PROFILE="$q"
  fi
fi

if [ -z "$INPUT_DIR" ]; then
  INPUT_DIR="$(ask_dir "1/2 - Carpeta con los videos H.265 de la a6700" "$HOME")"
fi
[ -z "${INPUT_DIR:-}" ] && { msg_error "Cancelado: sin carpeta de entrada."; exit 1; }
INPUT_DIR="$(realpath "$INPUT_DIR" 2>/dev/null || echo "$INPUT_DIR")"
[ -d "$INPUT_DIR" ] || { msg_error "No existe la carpeta de entrada: $INPUT_DIR"; exit 1; }

if [ -z "$OUTPUT_DIR" ]; then
  if [ "$HAS_ZENITY" -eq 1 ]; then
    OUTPUT_DIR="$(zenity --file-selection --directory --title="2/2 - Carpeta destino (Cancelar = crear RESOLVE_READY dentro de origen)" --filename="$INPUT_DIR/" 2>/dev/null || true)"
  else
    OUTPUT_DIR="$(ask_dir "2/2 - Carpeta destino (Enter = crear RESOLVE_READY dentro de origen)" "")"
    [ "$OUTPUT_DIR" = "" ] && OUTPUT_DIR=""
  fi
fi
if [ -z "${OUTPUT_DIR:-}" ]; then
  OUTPUT_DIR="$INPUT_DIR/RESOLVE_READY"
fi
mkdir -p "$OUTPUT_DIR" 2>/dev/null || { msg_error "No se pudo crear: $OUTPUT_DIR"; exit 1; }
OUTPUT_DIR="$(realpath "$OUTPUT_DIR" 2>/dev/null || echo "$OUTPUT_DIR")"
if [ "$INPUT_DIR" = "$OUTPUT_DIR" ]; then
  msg_error "La carpeta destino no puede ser la misma que la de entrada (se sobrescribirian). Se usara RESOLVE_READY."
  OUTPUT_DIR="$INPUT_DIR/RESOLVE_READY"
  mkdir -p "$OUTPUT_DIR"
fi

# Archivos de entrada (solo nivel superior, ordenados)
mapfile -t FILES < <(find "$INPUT_DIR" -maxdepth 1 -type f \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.mxf" -o -iname "*.mts" -o -iname "*.m2ts" \) | sort)
if [ "${#FILES[@]}" -eq 0 ]; then msg_error "No se encontraron videos (.mp4/.mov/.mxf/.mts) en: $INPUT_DIR"; exit 1; fi

LOG="$OUTPUT_DIR/conversion_$(date +%Y%m%d_%H%M%S).log"
{
  echo "converter-h265-linux-resolve"
  echo "fecha: $(date -Is)"
  echo "entrada: $INPUT_DIR"
  echo "salida: $OUTPUT_DIR"
  echo "perfil: $PROFILE"
  echo "ffmpeg: $(ffmpeg -version 2>/dev/null | head -n1)"
  echo "archivos: ${#FILES[@]}"
  echo "---"
} | tee "$LOG"

# Flags ffmpeg por perfil
case "$PROFILE" in
  hqx)       VCODEC=(-c:v dnxhd -profile:v dnxhr_hqx -pix_fmt yuv422p10le); TAG="DNxHR HQX 10-bit" ;;
  hq)        VCODEC=(-c:v dnxhd -profile:v dnxhr_hq -pix_fmt yuv422p);      TAG="DNxHR HQ 8-bit" ;;
  sq)        VCODEC=(-c:v dnxhd -profile:v dnxhr_sq -pix_fmt yuv422p);      TAG="DNxHR SQ 8-bit" ;;
  lb)        VCODEC=(-c:v dnxhd -profile:v dnxhr_lb -pix_fmt yuv422p);      TAG="DNxHR LB 8-bit" ;;
  prores-lt) VCODEC=(-c:v prores_ks -profile:v 1 -pix_fmt yuv422p10le -vendor ap10); TAG="ProRes 422 LT" ;;
  *)         VCODEC=(-c:v dnxhd -profile:v dnxhr_hqx -pix_fmt yuv422p10le); TAG="DNxHR HQX 10-bit" ;;
esac

ok=0; skipped=0; failed=0
FAILED_LIST=()

convert_one() {
  local src="$1"
  local base out xml_base
  base="$(basename "$src")"
  base="${base%.*}"
  out="$OUTPUT_DIR/$base.mov"
  if [ -f "$out" ]; then echo "OMITIDO (ya existe): $out" | tee -a "$LOG"; return 2; fi
  echo ">>> $base : $TAG" | tee -a "$LOG"
  # -map 0:v:0 + 0:a:0? (algunos clips no traen audio), -dn descarta data rtmd/giroscopio
  if ffmpeg -hide_banner -loglevel warning -stats -y -i "$src" \
      -map 0:v:0 -map 0:a:0? -dn \
      "${VCODEC[@]}" -c:a pcm_s16le -ar 48000 -ac 2 \
      -movflags +faststart -map_metadata 0 \
      "$out" >>"$LOG" 2>&1; then
    # Copia XML lateral Sony si existe (C0055M01.XML, etc.)
    for pat in "$INPUT_DIR/$base"*.XML "$INPUT_DIR/$base"*.xml; do
      [ -f "$pat" ] || continue
      xml_base="$(basename "$pat")"
      cp -n "$pat" "$OUTPUT_DIR/$xml_base" 2>/dev/null || true
      echo "  + XML copiado: $xml_base" | tee -a "$LOG"
    done
    echo "OK: $out" | tee -a "$LOG"
    return 0
  else
    echo "FALLO: $src (ver log)" | tee -a "$LOG"
    rm -f "$out"
    return 1
  fi
}

TOTAL="${#FILES[@]}"
RESULTS_FILE="$(mktemp)"
if [ "$HAS_ZENITY" -eq 1 ]; then
  # Un solo pase: el subshell convierte y reporta progreso a zenity,
  # y deja el resultado (0/1/2) por archivo en $RESULTS_FILE.
  : > "$RESULTS_FILE"
  (
    i=0
    for f in "${FILES[@]}"; do
      i=$((i+1)); pct=$(( (i-1)*100/TOTAL ))
      echo "$pct"
      echo "# [$i/$TOTAL] $(basename "$f")"
      convert_one "$f" >/dev/null 2>&1; rc=$?
      echo "$rc:$(basename "$f")" >> "$RESULTS_FILE"
      echo "$pct"
    done
    echo "100"; echo "# Terminado"
  ) | zenity --progress --title="Convirtiendo a $TAG ($TOTAL archivos)" --width=500 --auto-close --time-remaining 2>/dev/null || true
  ok=0; skipped=0; failed=0; FAILED_LIST=()
  while IFS= read -r line; do
    rc="${line%%:*}"
    nm="${line#*:}"
    if [ "$rc" = "0" ]; then ok=$((ok+1));
    elif [ "$rc" = "2" ]; then skipped=$((skipped+1));
    else failed=$((failed+1)); FAILED_LIST+=("$nm"); fi
  done < "$RESULTS_FILE"
else
  i=0
  : > "$RESULTS_FILE"
  for f in "${FILES[@]}"; do
    i=$((i+1))
    printf '\n[%d/%d] %s\n' "$i" "$TOTAL" "$(basename "$f")"
    convert_one "$f"; rc=$?
    echo "$rc:$(basename "$f")" >> "$RESULTS_FILE"
    [ "$rc" -eq 0 ] && ok=$((ok+1)) || { [ "$rc" -eq 2 ] && skipped=$((skipped+1)) || { failed=$((failed+1)); FAILED_LIST+=("$(basename "$f")"); }; }
  done
fi
rm -f "$RESULTS_FILE"

{
  echo "---"
  echo "listo: ok=$ok omitidos=$skipped fallos=$failed total=$TOTAL"
  [ "$failed" -gt 0 ] && printf 'fallaron: %s\n' "${FAILED_LIST[*]}"
  echo "salida: $OUTPUT_DIR"
  du -sh "$OUTPUT_DIR" 2>/dev/null || true
} | tee -a "$LOG"

SUMMARY="Listo: $ok/$TOTAL convertidos a $TAG.\nDestino: $OUTPUT_DIR\nLog: $(basename "$LOG")"
[ "$failed" -gt 0 ] && SUMMARY="$SUMMARY\nFallaron: ${FAILED_LIST[*]}"
if [ "$HAS_ZENITY" -eq 1 ]; then
  if [ "$failed" -gt 0 ]; then zenity --warning --width=500 --text="$SUMMARY" 2>/dev/null;
  else zenity --info --width=500 --text="$SUMMARY\n\nYa puedes importar los .mov en Resolve (Media Pool). Si grabaste en S-Log3, aplica el Input Color Space S-Gamut3.Cine / S-Log3 en el clip." 2>/dev/null; fi
else
  printf '\n%s\n' "$(echo -e "$SUMMARY")"
  echo "Tip Resolve: Media Pool -> importar .mov. Si es S-Log3: click derecho clip -> Input Color Space -> S-Gamut3.Cine / S-Log3."
fi

[ "$failed" -gt 0 ] && exit 2 || exit 0
