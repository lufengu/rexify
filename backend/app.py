import io
import re
import subprocess
from urllib.parse import quote
from flask import Flask, request, Response, jsonify, stream_with_context
from flask_cors import CORS
from yt_dlp import YoutubeDL
from functools import lru_cache
import time
import logging
import os
import requests
import tempfile
import shutil
import random
try:
    # y2mate-api (opcional). Si no está, el endpoint devolverá 501.
    from y2mate_api import Y2Mate  # type: ignore
except Exception:  # pragma: no cover
    Y2Mate = None

# configuración de logging para ver errores en consola
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)
FFMPEG_BIN = os.getenv('FFMPEG_BINARY', 'ffmpeg')
logger.debug("Using ffmpeg binary: %s", FFMPEG_BIN)

# Lista de instancias Piped para fallback alternativo (se puede override con env)
DEFAULT_PIPED_INSTANCES = [
    'https://pipedapi.kavin.rocks',
    'https://piped.video',
    'https://pipedapi-libre.kavin.rocks',
    'https://piped.palveluntarjoaja.eu',
]

def _get_piped_instances():
    env = os.getenv('PIPED_INSTANCES', '').strip()
    if env:
        parts = [p.strip() for p in env.split(',') if p.strip()]
        return parts if parts else DEFAULT_PIPED_INSTANCES
    return DEFAULT_PIPED_INSTANCES


def sanitize_filename(name: str) -> str:
    # Remueve caracteres problemáticos para headers
    return re.sub(r'[\n\r\t\\/:*?"<>|]+', '_', name).strip() or 'audio'


def search_youtube_top_flat(query: str):
    """Realiza búsqueda plana y devuelve primer resultado (info mínima)."""
    opts = {
        'quiet': True,
        'skip_download': True,
        'extract_flat': True,
        'noplaylist': True,
        'nocheckcertificate': True,
        'socket_timeout': 10,
        'retries': 1,
        'http_headers': {"User-Agent": "Mozilla/5.0"},
    }
    try:
        with YoutubeDL(opts) as ydl:
            res = ydl.extract_info(f"ytsearch1:{query}", download=False)
            if not res:
                return None
            entries = res.get('entries') or []
            if not entries:
                return None
            return entries[0]
    except Exception as e:
        logger.debug("search_youtube_top_flat error: %s", e)
        return None


def is_url(text: str) -> bool:
    return text.startswith('http://') or text.startswith('https://')


def extract_youtube_id(s: str) -> str | None:
    """Extrae el ID de YouTube de varias formas de URL. Devuelve None si no encuentra."""
    try:
        if not s:
            return None
        s = s.strip()
        if 'youtu.be/' in s:
            return s.rsplit('youtu.be/', 1)[-1].split('?')[0].split('&')[0]
        if 'youtube.com/' in s:
            if '/watch' in s and 'v=' in s:
                # v param
                after_v = s.split('v=', 1)[1]
                return after_v.split('&')[0]
            if '/shorts/' in s:
                return s.rsplit('/shorts/', 1)[-1].split('?')[0]
        # Si parece un ID ya
        if len(s) in (11,):
            return s
    except Exception:
        return None
    return None


@lru_cache(maxsize=128)
def resolve_video_info(q: str):
    """Obtiene metadatos completos del video (con formatos)."""
    # Configuración base para extracción completa.
    def _full_opts(player_client: str | None = None):
        opts = {
            'quiet': True,
            'skip_download': True,
            'extract_flat': False,
            'noplaylist': True,
            'nocheckcertificate': True,
            'socket_timeout': 15,
            'retries': 1,
            'http_headers': {"User-Agent": "Mozilla/5.0"},
            # Forzar IPv4 puede ayudar cuando hay 403 por ip param
            'source_address': '0.0.0.0',
            'geo_bypass': True,
        }
        if player_client:
            opts['extractor_args'] = {
                'youtube': {
                    'player_client': [player_client],
                }
            }
        return opts

    try:
        # Intentar con varios clientes para maximizar compatibilidad
        candidates = ['android', 'web', 'ios']
        target = q
        if not is_url(q):
            flat = search_youtube_top_flat(q)
            if not flat:
                return None
            target = flat.get('webpage_url') or flat.get('url') or flat.get('id') or q
        for client in candidates:
            try:
                with YoutubeDL(_full_opts(client)) as ydl:
                    info = ydl.extract_info(target, download=False)
                    if info:
                        return info
            except Exception as e:
                logger.debug("resolve with client %s failed: %s", client, e)
        return None
    except Exception as e:
        logger.exception("resolve_video_info failed: %s", e)
        return None


@app.get('/download')
def download():
    q = request.args.get('q', '').strip()
    if not q:
        return jsonify({'error': 'q parameter required'}), 400

    video = resolve_video_info(q)
    if not video:
        return jsonify({'error': 'video not found'}), 404

    title = sanitize_filename(video.get('title') or 'audio')
    formats = video.get('formats') or []
    requested_format = (request.args.get('format') or 'mp3').lower()
    force_mp3 = (request.args.get('force_mp3') or '0') in ('1', 'true', 'yes')
    want_video = (request.args.get('video') or '0') in ('1', 'true', 'yes')

    # Selección simple de formato: preferir audio-only para mp3; para mp4/stream proxy usar mejor formato disponible
    chosen = None
    if requested_format == 'mp3' or force_mp3:
        # elegir mejor audio (por bitrate)
        audio_formats = [f for f in formats if (f.get('vcodec') in (None, 'none') or f.get('acodec') and f.get('vcodec') in (None, 'none'))]
        audio_formats.sort(key=lambda f: (f.get('abr') or 0), reverse=True)
        if audio_formats:
            chosen = audio_formats[0]
    else:
        # mp4 solicitado: preferir video if want_video, else prefer audio m4a/webm
        if want_video:
            vids = [f for f in formats if f.get('vcodec') and f.get('ext') in ('mp4', 'webm')]
            vids.sort(key=lambda f: (f.get('height') or 0), reverse=True)
            if vids:
                chosen = vids[0]
        else:
            aud = [f for f in formats if (f.get('ext') in ('m4a', 'webm', 'mp4')) and (f.get('vcodec') in (None, 'none'))]
            aud.sort(key=lambda f: (f.get('abr') or 0), reverse=True)
            if aud:
                chosen = aud[0]

    # Fallback: si no elegimos nada, tomar el 'url' del info directo (bestaudio/best)
    if not chosen and formats:
        chosen = formats[-1]

    if not chosen or not chosen.get('url'):
        return jsonify({'error': 'no suitable format found'}), 404

    upstream_url = chosen.get('url')
    # recolectar headers sugeridos por yt-dlp (si los hay)
    upstream_headers = {}
    if isinstance(chosen.get('http_headers'), dict):
        upstream_headers.update({k: v for k, v in chosen['http_headers'].items()})
    # asegurar User-Agent y Referer por si el servidor upstream lo exige
    upstream_headers.setdefault('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)')
    if 'webpage_url' in video and video.get('webpage_url'):
        upstream_headers.setdefault('Referer', video.get('webpage_url'))
    # Si el cliente nos envía Cookie, propagarla (opcional)
    if 'Cookie' in request.headers:
        upstream_headers.setdefault('Cookie', request.headers.get('Cookie'))

    # Permitir forzar el fallback
    force_fallback = (request.args.get('force_fallback') or '0') in ('1', 'true', 'yes')
    # Permitir elegir explícitamente el player_client para yt-dlp en el fallback
    fallback_client = (request.args.get('client') or '').strip().lower() or None

    logger.debug("Proxying upstream url: %s", upstream_url)
    logger.debug("Upstream headers: %s", upstream_headers)

    # Intento 1: proxy directo (stream desde la URL que devuelve yt-dlp)
    if not force_fallback:
        try:
            # Soporte de Range: si el cliente pide un rango, propagarlo
            req_headers = dict(upstream_headers)
            if 'Range' in request.headers:
                req_headers['Range'] = request.headers['Range']
            with requests.get(
                upstream_url,
                headers=req_headers,
                stream=True,
                timeout=(5, 30),
                allow_redirects=True,
            ) as r:
                logger.debug("Proxy MP4 status: %s", r.status_code)
                if r.status_code in (200, 206):
                    # determinar extensión y disposition
                    ext = chosen.get('ext') or 'mp3'
                    disposition_name = f"{title}.{ext}"
                    # Encabezados a traspasar del upstream
                    passthrough = {}
                    for h in ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges'):
                        if h.lower() in r.headers:
                            passthrough[h] = r.headers.get(h)
                    passthrough['Content-Disposition'] = f'attachment; filename="{disposition_name}"'

                    return Response(
                        stream_with_context(r.iter_content(chunk_size=64 * 1024)),
                        headers=passthrough,
                        status=r.status_code,
                    )
                else:
                    logger.error("Proxy upstream returned status %s, will fallback to yt-dlp download", r.status_code)
        except requests.RequestException as e:
            logger.exception("requests proxy failed, falling back to yt-dlp: %s", e)

    # Fallback: usar yt-dlp para descargar en servidor y luego stream al cliente (temporal)
    tmpdir = tempfile.mkdtemp(prefix='rexify_')
    try:
        ydl_opts_base = {
            'format': 'bestaudio/best',
            'outtmpl': os.path.join(tmpdir, '%(id)s.%(ext)s'),
            'nocheckcertificate': True,
            'quiet': True,
            'no_warnings': True,
            # Pasar headers que funcionaron en el proxy (User-Agent, Referer, ...)
            'http_headers': upstream_headers,
            # Intentos y timeout adicionales
            'retries': 3,
            'socket_timeout': 30,
            # Forzar uso de IPv4 (evita problemas con IPs/param ip firmadas que den 403)
            'source_address': '0.0.0.0',
            # Bypass geo si fuese necesario
            'geo_bypass': True,
        }
        if requested_format == 'mp3' or force_mp3:
            # convierte a mp3 (requiere ffmpeg)
            ydl_opts_base['postprocessors'] = [{
                'key': 'FFmpegExtractAudio',
                'preferredcodec': 'mp3',
                'preferredquality': '192',
            }]

        # descarga con yt-dlp (debe resolver firmas si existieran)
        try:
            # Probar varios clientes si no se especifica uno
            clients = [fallback_client] if fallback_client else ['android', 'web', 'ios']
            last_exc: Exception | None = None
            info = None
            target = video.get('webpage_url') or q
            for client in clients:
                opts = dict(ydl_opts_base)
                opts['extractor_args'] = {'youtube': {'player_client': [client]}}
                try:
                    with YoutubeDL(opts) as ydl:
                        info = ydl.extract_info(target, download=True)
                        if info:
                            break
                except Exception as e:
                    last_exc = e
                    logger.debug("fallback yt-dlp with client %s failed: %s", client, e)
            if info is None and last_exc:
                raise last_exc
        except Exception as e:
            logger.exception("yt-dlp server-side download failed: %s", e)
            shutil.rmtree(tmpdir, ignore_errors=True)
            return jsonify({'error': 'yt-dlp download failed', 'detail': str(e)}), 502

        # encontrar archivo descargado
        files = [f for f in os.listdir(tmpdir) if os.path.isfile(os.path.join(tmpdir, f))]
        if not files:
            shutil.rmtree(tmpdir, ignore_errors=True)
            return jsonify({'error': 'no file after yt-dlp download'}), 502
        # prefer first matching
        file_path = os.path.join(tmpdir, files[0])
        ext = os.path.splitext(file_path)[1].lstrip('.')
        mimetype = 'audio/mpeg' if ext == 'mp3' else ('audio/mp4' if ext in ('m4a','mp4') else 'application/octet-stream')
        disposition_name = f"{title}.{ext}"

        def generate():
            try:
                with open(file_path, 'rb') as fh:
                    while True:
                        chunk = fh.read(64 * 1024)
                        if not chunk:
                            break
                        yield chunk
            finally:
                try:
                    os.remove(file_path)
                except Exception:
                    pass
                try:
                    shutil.rmtree(tmpdir, ignore_errors=True)
                except Exception:
                    pass

        headers = {
            'Content-Type': mimetype,
            'Content-Disposition': f'attachment; filename="{disposition_name}"',
        }
        return Response(stream_with_context(generate()), headers=headers, status=200)
    except Exception as e:
        logger.exception("Fallback stream failed: %s", e)
        try:
            shutil.rmtree(tmpdir, ignore_errors=True)
        except Exception:
            pass
        return jsonify({'error': 'internal error', 'detail': str(e)}), 500


@app.get('/download_piped')
def download_piped():
    """Alternativa: Resuelve y proxea audio usando la API de Piped.
    Parámetros:
      q: url o id de YouTube
      format: mp3|mp4 (se usará el mejor audio disponible; sin conversión por defecto)
      video: 0/1 (actualmente sólo audio)
    """
    q = request.args.get('q', '').strip()
    if not q:
        return jsonify({'error': 'q parameter required'}), 400

    vid = extract_youtube_id(q)
    if not vid:
        # Si es texto, intentar resolver vía búsqueda plana
        flat = search_youtube_top_flat(q)
        if not flat:
            return jsonify({'error': 'could not resolve video id'}), 404
        vid = flat.get('id') or extract_youtube_id(flat.get('url') or '')
        if not vid:
            return jsonify({'error': 'could not resolve video id'}), 404

    instances = _get_piped_instances()
    random.shuffle(instances)
    last_error = None
    streams_json = None
    chosen_instance = None
    for base in instances:
        try:
            url = f"{base.rstrip('/')}/streams/{vid}"
            r = requests.get(url, timeout=10)
            if r.status_code == 200:
                streams_json = r.json()
                chosen_instance = base
                break
            else:
                last_error = f"{base} status {r.status_code}"
        except Exception as e:
            last_error = str(e)

    if not streams_json:
        return jsonify({'error': 'piped fetch failed', 'detail': last_error}), 502

    title = sanitize_filename(streams_json.get('title') or 'audio')
    requested_format = (request.args.get('format') or 'mp3').lower()

    audio_streams = streams_json.get('audioStreams') or []
    if not audio_streams:
        return jsonify({'error': 'no audio streams from piped'}), 404

    # Preferir m4a si se pidió mp3/mp4 (mejor para conversión posterior), si no, tomar la de mayor bitrate
    def score(s):
        ext = 'm4a' if 'mp4' in (s.get('mimeType') or '') or (s.get('format') or '').lower() == 'm4a' else 'webm'
        bitrate = s.get('bitrate') or s.get('bitrateKbps') or 0
        return (1 if ext == 'm4a' else 0, int(bitrate))

    audio_streams.sort(key=score, reverse=True)
    chosen = audio_streams[0]
    upstream_url = chosen.get('url')
    mime = chosen.get('mimeType') or 'application/octet-stream'
    ext = 'm4a' if 'mp4' in mime else ('webm' if 'webm' in mime else 'bin')

    if not upstream_url:
        return jsonify({'error': 'invalid audio stream from piped'}), 502

    logger.debug("Piped(%s) upstream: %s", chosen_instance, upstream_url)

    # Soporte Range: propagar al upstream
    req_headers = {}
    if 'Range' in request.headers:
        req_headers['Range'] = request.headers['Range']

    try:
        with requests.get(upstream_url, headers=req_headers, stream=True, timeout=(5, 30), allow_redirects=True) as r:
            if r.status_code not in (200, 206):
                return jsonify({'error': 'piped stream bad status', 'status': r.status_code}), 502

            disposition_name = f"{title}.{ext}"
            passthrough = {}
            for h in ('Content-Type', 'Content-Length', 'Content-Range', 'Accept-Ranges'):
                if h.lower() in r.headers:
                    passthrough[h] = r.headers.get(h)
            passthrough.setdefault('Content-Type', mime)
            passthrough['Content-Disposition'] = f'attachment; filename="{disposition_name}"'

            return Response(
                stream_with_context(r.iter_content(chunk_size=64 * 1024)),
                headers=passthrough,
                status=r.status_code,
            )
    except requests.RequestException as e:
        return jsonify({'error': 'piped stream failed', 'detail': str(e)}), 502


@app.get('/health')
def health():
    return jsonify({'status': 'ok', 'version': '1.0'}), 200


@app.get('/ping')
def ping():
    return jsonify({'pong': True}), 200


@app.get('/info')
def info():
    return jsonify({'server': 'rexify-backend', 'yt_dlp': True}), 200


@app.get('/y2mate/resolve')
def y2mate_resolve():
    """Devuelve formatos disponibles usando y2mate (lib o microservicio).
    Respuesta: { video_id, title, formats: [{id, quality, format}] }
    """
    q = (request.args.get('q') or '').strip()
    if not q:
        return jsonify({'error': 'q parameter required'}), 400

    def normalize_formats(title, vid, mp3_list, mp4_list):
        formats = []
        def _iter(lst, fmt):
            if not lst:
                return
            for f in lst:
                if isinstance(f, dict):
                    quality = f.get('quality') or f.get('q') or f.get('label') or ''
                    fid = f.get('id') or f"{fmt}:{quality}"
                else:
                    quality = getattr(f, 'quality', None) or getattr(f, 'q', None) or ''
                    fid = getattr(f, 'id', None) or f"{fmt}:{quality}"
                formats.append({'id': str(fid), 'quality': str(quality), 'format': fmt})
        _iter(mp3_list, 'mp3')
        _iter(mp4_list, 'mp4')
        return {'video_id': vid, 'title': sanitize_filename(title or 'audio'), 'formats': formats}

    # Camino 1: librería instalada
    if Y2Mate is not None:
        session = Y2Mate()
        try:
            vid = extract_youtube_id(q)
            if not vid:
                results = session.search(q)
                if not results:
                    return jsonify({'error': 'no results'}), 404
                vid = getattr(results[0], 'video_id', None) or getattr(results[0], 'id', None)
            if not vid:
                return jsonify({'error': 'unresolvable id'}), 404
            info = session.get_info(vid)
            if not info:
                return jsonify({'error': 'no info from y2mate'}), 502
            mp3_list = getattr(info, 'mp3_formats', None) or getattr(info, 'audio_formats', None) or []
            mp4_list = getattr(info, 'mp4_formats', None) or []
            out = normalize_formats(getattr(info, 'title', None), vid, mp3_list, mp4_list)
            return jsonify(out), 200
        except Exception as e:
            logger.exception('y2mate/resolve error: %s', e)
            return jsonify({'error': 'internal y2mate error', 'detail': str(e)}), 500
        finally:
            try:
                if hasattr(session, 'close'):
                    session.close()
            except Exception:
                pass

    # Camino 2: microservicio local opcional
    try:
        url = 'http://127.0.0.1:5001/resolve'
        r = requests.get(url, params={'q': q}, timeout=20)
        if r.status_code == 200:
            data = r.json()
            # asumir salida con {video_id,title,formats}
            if isinstance(data, dict) and 'formats' in data:
                return jsonify(data), 200
            return jsonify({'error': 'invalid microservice response'}), 502
        return jsonify({'error': 'microservice resolve failed', 'status': r.status_code}), 502
    except Exception as e:
        return jsonify({'error': 'resolve not available', 'detail': str(e)}), 501


@app.get('/download_y2mate')
def download_y2mate():
    """Descarga/convierte usando y2mate-api.
    Parámetros:
      q: búsqueda o URL de YouTube (requerido)
      format: mp3|mp4 (default mp3)
      quality: opcional (ej: 128, 192, 320 para mp3; 144,240,360,480,720 para mp4)
      format_id: opcional id devuelto por /y2mate/resolve (p.ej. mp3:128)
    """
    q = (request.args.get('q') or '').strip()
    if not q:
        return jsonify({'error': 'q parameter required'}), 400
    req_format = (request.args.get('format') or 'mp3').lower()
    desired_quality = (request.args.get('quality') or '').strip()
    format_id = (request.args.get('format_id') or '').strip()
    # Si la librería no está, intentar con microservicio directo
    if Y2Mate is None:
        try:
            r = requests.get('http://127.0.0.1:5001/resolve', params={'q': q}, timeout=20)
            if r.status_code != 200:
                return jsonify({'error': 'y2mate not available'}), 501
            data = r.json()
            vid = data.get('video_id')
            title = sanitize_filename(data.get('title') or 'audio')
            # elegir formato
            chosen = None
            if format_id:
                for f in data.get('formats') or []:
                    if str(f.get('id')) == format_id:
                        chosen = f
                        break
            if chosen is None:
                # match por format + quality
                for f in data.get('formats') or []:
                    if f.get('format') == req_format and (not desired_quality or desired_quality in str(f.get('quality'))):
                        chosen = f
                        break
            if chosen is None:
                return jsonify({'error': 'no suitable y2mate format'}), 404
            # El microservicio no provee link directo; pedirlo al propio sitio no implementado -> 501
            return jsonify({'error': 'download via microservice not implemented', 'hint': 'use library y2mate-api in this environment'}), 501
        except Exception as e:
            return jsonify({'error': 'y2mate not available', 'detail': str(e)}), 501

    session = Y2Mate()
    try:
        # Determinar si es URL o búsqueda
        video_id = None
        if is_url(q):
            video_id = extract_youtube_id(q)
        if not video_id:
            # búsqueda -> primer resultado
            results = session.search(q)
            if not results:
                return jsonify({'error': 'no results'}), 404
            video_id = results[0].video_id
        if not video_id:
            return jsonify({'error': 'unresolvable id'}), 404

        # Obtener metadatos de conversión
        info = session.get_info(video_id)
        if not info:
            return jsonify({'error': 'no info from y2mate'}), 502

        title = sanitize_filename(info.title or 'audio')
        # Elegir lista según formato
        if req_format == 'mp4':
            candidates = info.mp4_formats
        else:
            candidates = info.mp3_formats or info.audio_formats or []
            req_format = 'mp3'

        if not candidates:
            return jsonify({'error': 'no formats available'}), 404

        def quality_key(f):
            import re as _re
            m = _re.search(r'(\d+)', f.quality or '')
            return int(m.group(1)) if m else 0

        candidates.sort(key=quality_key, reverse=True)

        chosen = None
        if format_id:
            for c in candidates:
                cid = getattr(c, 'id', None)
                if cid and str(cid) == format_id:
                    chosen = c
                    break
        if desired_quality:
            try:
                dq = int(''.join([c for c in desired_quality if c.isdigit()]))
                filtered = [c for c in candidates if quality_key(c) >= dq]
                if chosen is None:
                    chosen = filtered[0] if filtered else candidates[0]
            except ValueError:
                if chosen is None:
                    chosen = candidates[0]
        if chosen is None:
            chosen = candidates[0]

        download_url = session.get_download_link(chosen)
        if not download_url:
            return jsonify({'error': 'failed to obtain download link'}), 502

        logger.debug('y2mate chosen format=%s quality=%s url=%s', req_format, chosen.quality, download_url)

        headers_out = {}
        if 'Range' in request.headers:
            headers_out['Range'] = request.headers['Range']
        try:
            with requests.get(download_url, headers=headers_out, stream=True, timeout=(10, 60)) as r:
                if r.status_code not in (200, 206):
                    return jsonify({'error': 'download upstream failed', 'status': r.status_code}), 502
                ext = 'mp3' if req_format == 'mp3' else 'mp4'
                disp_name = f'{title}.{ext}'
                passthrough = {}
                for h in ('Content-Length', 'Content-Range', 'Accept-Ranges', 'Content-Type'):
                    if h.lower() in r.headers:
                        passthrough[h] = r.headers.get(h)
                passthrough.setdefault('Content-Type', 'audio/mpeg' if ext == 'mp3' else 'video/mp4')
                passthrough['Content-Disposition'] = f'attachment; filename="{disp_name}"'

                return Response(stream_with_context(r.iter_content(64 * 1024)), headers=passthrough, status=r.status_code)
        except requests.RequestException as e:
            return jsonify({'error': 'stream failure', 'detail': str(e)}), 502
    except Exception as e:
        logger.exception('y2mate endpoint error: %s', e)
        return jsonify({'error': 'internal y2mate error', 'detail': str(e)}), 500
    finally:
        try:
            if hasattr(session, 'close'):
                session.close()
        except Exception:
            pass


if __name__ == '__main__':
    port = int(os.getenv('PORT', '5000'))
    app.run(host='0.0.0.0', port=port, debug=False, threaded=True)
