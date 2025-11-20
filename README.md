# Rexify - Reproductor de Música Local y Streaming YouTube

Un reproductor de música temática (dinosaurio bailando) para Android/Flutter que reproduce archivos de audio locales y ahora permite buscar y descargar audio desde YouTube mediante un backend Flask en streaming (sin almacenar el archivo en el servidor).

##  Características

###  Gestión y carga de canciones locales
-  Escanea todas las canciones locales almacenadas en el dispositivo (memoria interna o tarjeta SD)
-  Lee metadatos usando `on_audio_query`:
  - Título
  - Artista
  - Álbum
  - Duración
  - Carátula del álbum (cover art)
-  Lista automáticamente todas las pistas de audio compatibles (.mp3, .wav, .m4a, etc.)

###  Reproducción de audio local
-  Reproduce canciones locales directamente desde la memoria del dispositivo
-  Control de reproducción básico:
  - Play / Pause
  - Siguiente / Anterior
  - Deslizar barra de progreso para adelantar o retroceder
-  Reproducción continua (pasa automáticamente a la siguiente canción)
-  Permite detener y reiniciar la reproducción
-  Control de volumen integrado

###  Interfaz y control del usuario
-  Pantalla principal con lista de canciones y su respectiva información
-  Al tocar una canción, abre una pantalla de reproducción detallada con:
  - Imagen del álbum (con animación de rotación)
  - Título, artista y álbum
  - Barra de progreso animada
  - Botones de control (play, pause, siguiente, anterior)
  - Control de volumen deslizante
-  Compatible con modo oscuro según el tema del sistema
-  Diseño moderno con colores suaves y animaciones simples
-  Mini reproductor persistente en la parte inferior

### Navegador embebido tipo Chrome (descargas YouTube)
- WebView migrado a `flutter_inappwebview` con User-Agent desktop Chrome
- Soporte de JavaScript completo, ventanas, cookies de terceros y DOM Storage
- Inyección de script para limpiar anuncios y bloquear popups intrusivos
- Intercepta enlaces de descarga directa (`onDownloadStartRequest`) para guardar audio/video localmente
- Headers personalizados (Accept-Language, User-Agent, Sec-Fetch-*) para mejorar compatibilidad con sitios como y2mate
- Modo "limpio" con eliminación dinámica de iframes y overlays publicitarios

###  Integración con el sistema
-  Muestra el estado de reproducción (título, artista, progreso)
-  Compatible con Android 13+ (permiso de lectura de archivos multimedia)
-  Puede seguir reproduciendo mientras la pantalla está apagada

##  Instalación y uso (Modo local)

### Requisitos previos
- Flutter SDK instalado
- Android Studio o VS Code con extensiones de Flutter
- Un dispositivo Android o emulador

### Pasos de instalación

1. **Clonar el repositorio**
   ```bash
   git clone <url-del-repositorio>
   cd reproductor_musica
   ```

2. **Instalar dependencias**
   ```bash
   flutter pub get
   ```

3. **Ejecutar la aplicación**
   ```bash
   flutter run
   ```

### Permisos requeridos

La aplicación solicitará automáticamente permisos para:
- Leer archivos de audio del almacenamiento (Android 13+)
- Mantener el dispositivo activo durante la reproducción

##  Dependencias principales (local)

- `on_audio_query`: ^2.9.0 - Consulta y gestión de metadatos de audio
- `just_audio`: ^0.9.40 - Motor de reproducción de audio
- `permission_handler`: ^11.3.1 - Gestión de permisos
- `audio_video_progress_bar`: ^2.0.3 - Barra de progreso interactiva
- `hive` y `hive_flutter`: ^2.2.3 - Almacenamiento local (preparado para futuras mejoras)

## Estructura del proyecto (local)

```
lib/
├── main.dart                 # Punto de entrada de la aplicación
├── screens/
│   ├── home_screen.dart      # Pantalla principal con lista de canciones
│   └── player_screen.dart    # Pantalla de reproducción detallada
└── services/
    └── audio_player_service.dart  # Servicio singleton para gestión de audio
```

## Capturas de pantalla

### Pantalla principal
- Lista de todas las canciones con portadas
- Mini reproductor en la parte inferior
- Soporte para tema claro/oscuro

### Pantalla de reproducción
- Carátula del álbum con animación de rotación
- Información completa de la canción
- Controles de reproducción intuitivos
- Barra de progreso interactiva
- Control de volumen

## Funcionalidades futuras

Mejoras planificadas para futuras versiones:
- Creación de playlists personalizadas
- Búsqueda y filtrado de canciones
- Ecualizador
- Modo de repetición y aleatorio
- Estadísticas de reproducción

## Notas técnicas

## Búsqueda y descarga vía Web + Backend

Se añadió una pantalla `SearchWebScreen` para:
1. Buscar canciones en YouTube (WebView embebida).
2. Enviar el término de búsqueda al backend Flask (`/download?q=...`).
3. Recibir el MP3 por streaming sin que el servidor lo guarde en disco.
4. Guardar temporalmente el archivo en la app y reproducirlo con `just_audio`.

### Backend Flask (opcional)

Requisitos:
- Python 3.10+
- ffmpeg instalado y accesible en PATH.

Instalación y ejecución (PowerShell):
```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

Endpoint principal:
```
GET /download?q=<termino>
```
Devuelve `audio/mpeg` con encabezado `Content-Disposition: attachment; filename*=UTF-8''<nombre>.mp3`.

Endpoint de salud:
```
GET /health -> {"status": "ok"}
```
Útil para probar conectividad y que ffmpeg/yt-dlp no han roto el entorno antes de descargar.

### Cómo funciona el streaming
- `yt-dlp` se usa para resolver la mejor URL de audio del video.
- `ffmpeg` transcodifica esa URL a MP3 en tiempo real y escribe a stdout.
- Flask envía los chunks al cliente (transferencia sin archivo temporal persistente en servidor).
 - Se añaden cabeceras seguras: `X-Content-Type-Options: nosniff` y `Cache-Control: no-store`.

### App Flutter (integración remota)

Dependencias nuevas en `pubspec.yaml`:
```yaml
http
webview_flutter
path_provider
```

Archivos añadidos:
- `lib/services/backend_client.dart`: cliente HTTP para descargar y guardar el MP3 temporalmente.
- `lib/screens/search_web_screen.dart`: pantalla con TextField + botón MP3 + WebView.
- `backend/app.py`: backend Flask.

Acceso: en `HomeScreen` aparece un botón (icono globo) que navega a la pantalla de búsqueda.

### Configuración de la URL base
- Emulador Android: usar `http://10.0.2.2:5000`.
- Dispositivo físico: reemplazar por la IP local de tu PC, ej. `http://192.168.1.50:5000`.

Modifica el parámetro opcional `backendBaseUrl` al instanciar `SearchWebScreen` si necesitas otra URL.

### Flujo resumido
1. Usuario escribe término y pulsa buscar (carga resultados en WebView).
2. Pulsa botón MP3: se hace petición GET al backend.
3. Backend transcodifica y envía audio.
4. App guarda archivo en `getTemporaryDirectory()` y ofrece reproducir.
 5. (Opcional) Guardar de forma persistente en almacenamiento externo: implementar futuro método usando `path_provider` y permisos WRITE si fuera necesario.

### Escalabilidad (futuras fuentes)
Para añadir más proveedores (ej. SoundCloud, Jamendo):
- Crear nuevos métodos en el backend que resuelvan URL directa de audio.
- Unificar una interfaz en Flutter (p. ej. enum SourceType) y pasarla como parámetro al endpoint.
- Estándar de respuesta: `audio/mpeg` + `Content-Disposition`.

### Seguridad y buenas prácticas
- Limitar tasa de peticiones (rate limiting) si se expone públicamente.
- Sanitizar parámetros (ya se elimina caracteres peligrosos en filename).
- Considerar caché en memoria con TTL si se reutiliza la misma canción varias veces (sin escribir a disco).
- Revisar Términos de Servicio de YouTube para uso de `yt-dlp`.
 - En producción usar HTTPS y desactivar `android:usesCleartextTraffic`.
 - Validar longitud del query (ej. máximo 100 caracteres) para mitigar abuso.


- **Patrón Singleton**: El `AudioPlayerService` utiliza el patrón singleton para mantener una única instancia del reproductor en toda la aplicación
- **Gestión de estado reactiva**: Uso extensivo de `StreamBuilder` para actualizar la UI en tiempo real
- **Material Design 3**: Interfaz moderna siguiendo las últimas guías de diseño de Google

## Permisos de almacenamiento (lógica persistente)

Para mejorar la experiencia del usuario y evitar que la app solicite permisos de almacenamiento en cada inicio, se implementó una lógica nativa + Flutter con estos puntos:

1. Verificación inicial no bloqueante al arrancar (`MyApp.initState`) usando `PermissionUtils.ensureStoragePermission()`.
2. Canal nativo (`MethodChannel` "rexify/media_store") con método `ensureStoragePermission` que:
  - Comprueba si el permiso ya está concedido (`hasStoragePermission`).
  - Si está concedido, devuelve inmediatamente `true`.
  - Si no, solicita el permiso mostrando un diálogo explicativo (Android 11+ redirige a la pantalla de configuración de "Todos los archivos").
3. Cache en memoria `_storageGrantedCache` para evitar llamadas redundantes una vez obtenida la aprobación durante la sesión.
4. Se actualiza un flag en `SharedPreferences` (clave `storage_granted`) a nivel nativo para diagnósticos o futura lógica personalizada.
5. Los métodos que necesitan permiso (`ensureDownloadPermissions`, `ensureLibraryPermissions`) reutilizan la verificación central.

### Beneficios
- Menos diálogos intrusivos al usuario.
- Flujo de arranque más fluido: la UI se muestra de inmediato.
- Código centralizado para futuras extensiones (ej. manejo diferenciado de permisos de audio, video, imágenes en Android 13+).

### Extensión futura sugerida
- Agregar pantalla de bienvenida que informe del uso de almacenamiento antes de la primera solicitud.
- Registrar métricas anónimas de cuántas veces se revocan los permisos para detectar fricción.



