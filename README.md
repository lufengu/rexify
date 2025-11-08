#  Reproductor de Música Local

Un reproductor de música tematica de dinosaurio bailando y funcional para Android desarrollado en Flutter que reproduce archivos de audio almacenados localmente en el dispositivo.

##  Características

###  Gestión y carga de canciones
-  Escanea todas las canciones locales almacenadas en el dispositivo (memoria interna o tarjeta SD)
-  Lee metadatos usando `on_audio_query`:
  - Título
  - Artista
  - Álbum
  - Duración
  - Carátula del álbum (cover art)
-  Lista automáticamente todas las pistas de audio compatibles (.mp3, .wav, .m4a, etc.)

###  Reproducción de audio
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

###  Integración con el sistema
-  Muestra el estado de reproducción (título, artista, progreso)
-  Compatible con Android 13+ (permiso de lectura de archivos multimedia)
-  Puede seguir reproduciendo mientras la pantalla está apagada

##  Instalación y uso

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

##  Dependencias principales

- `on_audio_query`: ^2.9.0 - Consulta y gestión de metadatos de audio
- `just_audio`: ^0.9.40 - Motor de reproducción de audio
- `permission_handler`: ^11.3.1 - Gestión de permisos
- `audio_video_progress_bar`: ^2.0.3 - Barra de progreso interactiva
- `hive` y `hive_flutter`: ^2.2.3 - Almacenamiento local (preparado para futuras mejoras)

## Estructura del proyecto

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

- **Patrón Singleton**: El `AudioPlayerService` utiliza el patrón singleton para mantener una única instancia del reproductor en toda la aplicación
- **Gestión de estado reactiva**: Uso extensivo de `StreamBuilder` para actualizar la UI en tiempo real
- **Material Design 3**: Interfaz moderna siguiendo las últimas guías de diseño de Google


