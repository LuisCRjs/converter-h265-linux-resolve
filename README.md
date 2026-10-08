# converter-h265-linux-resolve

Convierte en lote videos **H.265 HEVC 4:2:2 10-bit de Sony a6700 (XAVC HS)** a un formato nativo editable en **DaVinci Resolve Free en Linux**, manteniendo 4K y 10-bit.

> Tu caso: `HEVC 3840x2160 23.98p yuv422p10le ~98 Mbps + PCM 48 kHz` con `S-Log3 / S-Gamut3.Cine`.
> Resolve Free en Linux no decodifica H.265 (Studio-only) ni AAC, por eso los `.MP4` no importan o entran sin video.
> Este script los pasa a **DNxHR HQX 10-bit + PCM en `.mov`**, que Resolve sí lee en Linux.

## Requisitos

- `ffmpeg` + `ffprobe` (probado con ffmpeg 8.1.3, Fedora)
  ```bash
  sudo dnf install ffmpeg
  ```
- Opcional para ventanas visuales: `zenity` (ya viene en GNOME). Sin `DISPLAY` usa terminal.

## Uso

```bash
chmod +x convert-to-resolve.sh
./convert-to-resolve.sh
```

1. Elige **carpeta de entrada** (tus `.MP4` de la a6700).
2. Elige **calidad** (recomendado: `hqx`).
3. Elige **carpeta destino** (Cancelar = crea `ENTRADA/RESOLVE_READY/`).
4. Espera la barra de progreso. Mismo nombre: `C0055.MP4` → `C0055.mov`.

Sin ventanas / automatizable:

```bash
./convert-to-resolve.sh /ruta/videos /ruta/salida hqx --no-gui
./convert-to-resolve.sh /ruta/videos /ruta/salida sq --no-gui   # más liviano
```

## Perfiles (calidad vs peso, para 4s de prueba de 65 MB)

| Perfil | Comando | Peso aprox | Cuándo usar |
|---|---|---|---|
| `hqx` (defecto) | DNxHR HQX 10-bit 4:2:2 | ~335 MB (~5-7x) | Gradear S-Log3, máxima calidad |
| `hq` | DNxHR HQ 8-bit 4:2:2 | ~3-4x | Edición fluida, buena calidad |
| `sq` | DNxHR SQ 8-bit 4:2:2 | ~2x | Previews / disco lleno |
| `lb` | DNxHR LB 8-bit 4:2:2 | proxy | Solo montaje |
| `prores-lt` | ProRes 422 LT 10-bit | ~2-3x | Alternativo liviano |

No se puede mantener el peso original sin perder 10-bit/422: los intermedios intraframe son grandes por diseño. Conserva los originales y usa los `.mov` solo para editar.

## Importar en Resolve

1. Media Pool → importar los `.mov` de `RESOLVE_READY/`.
2. Si grabaste S-Log3: click derecho al clip → `Input Color Space` → `S-Gamut3.Cine / S-Log3`, o asigna en Project Settings → Color Management.
3. Timeline a `3840x2160 23.976`. Los XML `C0055M01.XML` se copian al destino como referencia (no los necesita Resolve).

## Notas

- Solo procesa nivel superior de la carpeta (`*.mp4/*.mov/*.mxf/*.mts/*.m2ts`), ordenados. No renombra.
- Si el `.mov` ya existe se omite (reanudable). Fallos no detienen el lote; quedan en `conversion_*.log`.
- Descarta la pista `rtmd` de giroscopio/timecode (Resolve no la usa).
- Audio siempre a `pcm_s16le 48 kHz stereo`, compatible con Fairlight en Linux.
