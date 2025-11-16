from flask import Flask, request, jsonify
import importlib
import inspect
import logging
from typing import Callable, Any, Optional

app = Flask(__name__)
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# intentos de nombres de clase/cliente que puede exportar la librería
CANDIDATE_CLIENT_NAMES = ('Y2Mate', 'Y2mate', 'Y2MateClient', 'Client', 'y2mate')

def load_y2mate_client() -> Optional[Callable[[], Any]]:
    """Carga el módulo y devuelve una fábrica de sesión/cliente o None.
    Se evita el unpack incorrecto de inspect y se hace una exploración simple.
    """
    try:
        mod = importlib.import_module('y2mate_api')
    except Exception as e:
        logger.debug("y2mate_api import failed: %s", e)
        return None

    # Intentos directos por nombre
    for name in CANDIDATE_CLIENT_NAMES:
        cls = getattr(mod, name, None)
        if cls and (inspect.isclass(cls) or callable(cls)):
            logger.debug("Using client %s from y2mate_api", name)
            return lambda: cls()

    # Recorrer atributos públicos buscando clases que contengan 'y2mate'
    for attr in dir(mod):
        obj = getattr(mod, attr)
        if inspect.isclass(obj) and 'y2mate' in attr.lower():
            logger.debug("Using discovered class %s from y2mate_api", attr)
            return lambda: obj()

    # Intentar submódulo client
    try:
        sub = importlib.import_module('y2mate_api.client')
        for attr in dir(sub):
            obj = getattr(sub, attr)
            if inspect.isclass(obj) and 'y2mate' in attr.lower():
                logger.debug("Using client %s from y2mate_api.client", attr)
                return lambda: obj()
    except Exception as e:
        logger.debug("No submodule client usable: %s", e)

    logger.debug("No usable y2mate client found in package")
    return None

_factory = load_y2mate_client()


def _call_if_exists(obj, candidates, *args, **kwargs):
    """Llama al primer método existente en candidates sobre obj."""
    for name in candidates:
        if hasattr(obj, name):
            fn = getattr(obj, name)
            if callable(fn):
                return fn(*args, **kwargs)
    raise AttributeError(f"No method in {candidates} on object {obj}")


@app.get('/resolve')
def resolve():
    if _factory is None:
        return jsonify({'error': 'y2mate-api not installed or incompatible', 'hint': 'pip install y2mate-api in this venv'}), 501

    q = (request.args.get('q') or '').strip()
    if not q:
        return jsonify({'error': 'q required'}), 400

    try:
        session = _factory()
    except Exception as e:
        logger.exception("Failed to instantiate y2mate client: %s", e)
        return jsonify({'error': 'client instantiation failed', 'detail': str(e)}), 500

    try:
        # resolver id heurístico
        vid = None
        if 'youtube' in q or 'youtu.be' in q:
            if 'v=' in q:
                vid = q.split('v=')[1].split('&')[0]
            elif 'shorts/' in q:
                vid = q.rsplit('/', 1)[-1].split('?')[0]
            elif 'youtu.be/' in q:
                vid = q.rsplit('/', 1)[-1].split('?')[0]

        if not vid:
            # intentar varios nombres para search
            results = _call_if_exists(session, ('search', 'search_videos', 'search_video', 'query'), q)
            # resultados pueden variar según API -> normalizar
            if not results:
                return jsonify({'error': 'no results'}), 404
            # intentar extraer video_id del primer resultado
            first = results[0]
            vid = getattr(first, 'video_id', None) or getattr(first, 'id', None) or getattr(first, 'videoId', None) or (first.get('id') if isinstance(first, dict) else None)

        if not vid:
            return jsonify({'error': 'unresolvable id'}), 404

        # obtener info: posibles métodos diferentes según versión
        info = _call_if_exists(session, ('get_info', 'video_info', 'get_video', 'info'), vid)

        # Normalizar salida básica
        title = getattr(info, 'title', None) or (info.get('title') if isinstance(info, dict) else None)
        # intentamos obtener listas de formatos (nombres distintos según versión)
        mp3_formats = getattr(info, 'mp3_formats', None) or getattr(info, 'audio_formats', None) or (info.get('mp3_formats') if isinstance(info, dict) else None) or (info.get('audio_formats') if isinstance(info, dict) else None)
        # convertir objetos a dicts simplificados
        formats = []
        if mp3_formats:
            for f in mp3_formats:
                if isinstance(f, dict):
                    formats.append({'quality': f.get('quality'), 'id': f.get('id'), 'format': f.get('format')})
                else:
                    formats.append({
                        'quality': getattr(f, 'quality', None),
                        'id': getattr(f, 'id', None),
                        'format': getattr(f, 'format', None)
                    })

        return jsonify({'video_id': vid, 'title': title, 'formats': formats}), 200
    except AttributeError as e:
        logger.exception("y2mate client missing expected methods: %s", e)
        return jsonify({'error': 'client missing methods', 'detail': str(e)}), 502
    except Exception as e:
        logger.exception("y2mate resolve error: %s", e)
        return jsonify({'error': 'internal', 'detail': str(e)}), 500
    finally:
        # cerrar si existe
        try:
            if hasattr(session, 'close'):
                session.close()
        except Exception:
            pass


if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001)