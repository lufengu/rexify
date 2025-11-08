# 🏗️ Arquitectura del Proyecto

## 📁 Estructura de archivos

```
reproductor_musica/
│
├── 📱 android/                          # Configuración Android
│   └── app/
│       └── src/
│           └── main/
│               └── AndroidManifest.xml  # ✅ Permisos configurados
│
├── 🎨 lib/                              # Código fuente Flutter
│   ├── main.dart                        # 🚀 Punto de entrada
│   │
│   ├── 📺 screens/                      # Pantallas de la UI
│   │   ├── home_screen.dart             # Lista de canciones
│   │   └── player_screen.dart           # Reproductor completo
│   │
│   └── ⚙️ services/                     # Lógica de negocio
│       └── audio_player_service.dart    # Servicio de audio (Singleton)
│
├── 📦 pubspec.yaml                      # Dependencias
├── 📖 README.md                         # Documentación principal
└── 📱 GUIA_DE_USO.md                    # Manual de usuario

```

## 🔄 Flujo de datos

```
┌─────────────────────────────────────────────────────────────┐
│                         main.dart                            │
│  • Inicializa Hive                                          │
│  • Inicializa AudioPlayerService                           │
│  • Configura temas (claro/oscuro)                          │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│                     HomeScreen                               │
│  • Solicita permisos                                        │
│  • Escanea canciones                                        │
│  • Muestra lista                                            │
│  • Mini reproductor                                         │
└──────────────┬──────────────────────┬───────────────────────┘
               │                      │
               │                      │ (Toca canción)
               │                      ▼
               │           ┌──────────────────────────┐
               │           │    PlayerScreen          │
               │           │  • Carátula animada      │
               │           │  • Controles completos   │
               │           │  • Barra de progreso     │
               │           │  • Control de volumen    │
               │           └──────────┬───────────────┘
               │                      │
               ▼                      ▼
┌──────────────────────────────────────────────────────────────┐
│              AudioPlayerService (Singleton)                   │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  OnAudioQuery                  JustAudio            │    │
│  │  • Escanea canciones           • Reproduce          │    │
│  │  • Lee metadatos               • Control de audio   │    │
│  │  • Obtiene portadas            • Streams de estado  │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
│  Métodos principales:                                        │
│  • loadSongs()         - Carga canciones del dispositivo    │
│  • playSong()          - Reproduce una canción              │
│  • togglePlayPause()   - Pausa/reproduce                    │
│  • playNext()          - Siguiente canción                  │
│  • playPrevious()      - Canción anterior                   │
│  • seek()              - Salta a posición                   │
│  • setVolume()         - Ajusta volumen                     │
└───────────────────────────────────────────────────────────────┘
```

## 🎯 Componentes principales

### 1. **main.dart** - Inicialización
```dart
• Inicializa Flutter bindings
• Configura Hive (preparado para futuro)
• Inicializa AudioPlayerService
• Define temas claro/oscuro
• Lanza HomeScreen
```

### 2. **HomeScreen** - Pantalla principal
```dart
Responsabilidades:
├── Gestión de permisos
├── Escaneo de canciones
├── Visualización de lista
├── Mini reproductor persistente
└── Navegación a PlayerScreen

StreamBuilders:
└── playerStateStream → Actualiza mini reproductor
```

### 3. **PlayerScreen** - Reproductor completo
```dart
Responsabilidades:
├── Visualización de carátula (animada)
├── Información de la canción
├── Controles de reproducción
├── Barra de progreso interactiva
└── Control de volumen

StreamBuilders:
├── playerStateStream → Estado play/pause
├── positionStream → Posición actual
└── durationStream → Duración total

AnimationController:
└── Rotación de carátula
```

### 4. **AudioPlayerService** - Lógica de audio
```dart
Patrón: Singleton
├── AudioPlayer (just_audio)
└── OnAudioQuery

Estado interno:
├── _playlist: List<SongModel>
├── _currentIndex: int
└── _audioPlayer: AudioPlayer

Streams expuestos:
├── positionStream
├── durationStream
├── playerStateStream
└── processingStateStream
```

## 🔌 Dependencias clave

| Paquete | Propósito | Uso |
|---------|-----------|-----|
| **on_audio_query** | Consulta de metadatos | Escaneo de canciones, portadas |
| **just_audio** | Motor de audio | Reproducción, control |
| **permission_handler** | Permisos | Acceso a archivos multimedia |
| **audio_video_progress_bar** | UI | Barra de progreso |
| **hive_flutter** | Persistencia | Futuras configuraciones |

## 🎨 Patrones de diseño utilizados

### 1. **Singleton**
```dart
AudioPlayerService usa Singleton para:
- Una única instancia del reproductor
- Estado compartido entre pantallas
- Gestión centralizada del audio
```

### 2. **StreamBuilder**
```dart
Actualización reactiva de UI:
- Escucha cambios en el reproductor
- Actualiza automáticamente la interfaz
- Sin necesidad de setState manual
```

### 3. **Service Locator**
```dart
AudioPlayerService actúa como:
- Punto de acceso centralizado
- Abstracción de la lógica de audio
- Facilita testing y mantenimiento
```

## 🔐 Permisos (Android)

```xml
AndroidManifest.xml configurado con:

├── READ_EXTERNAL_STORAGE (Android ≤12)
├── READ_MEDIA_AUDIO (Android 13+)
├── WAKE_LOCK (reproducción en background)
└── FOREGROUND_SERVICE (servicios en primer plano)
```

## 📊 Flujo de estados del reproductor

```
┌──────────┐
│  IDLE    │ Estado inicial
└────┬─────┘
     │ playSong()
     ▼
┌──────────┐
│ LOADING  │ Cargando audio
└────┬─────┘
     │
     ▼
┌──────────┐
│ PLAYING  │ ◄──┐ togglePlayPause()
└────┬─────┘    │
     │          │
     ▼          │
┌──────────┐    │
│ PAUSED   │ ───┘
└────┬─────┘
     │ playNext() / playPrevious()
     ▼
┌──────────┐
│COMPLETED │ → Auto reproduce siguiente
└──────────┘
```

## 🎯 Próximas mejoras sugeridas

```
Fase 1 - Funcionalidad básica ✅
├── Escaneo de canciones ✅
├── Reproducción básica ✅
├── Control de volumen ✅
└── Modo oscuro ✅

Fase 2 - Características avanzadas (TODO)
├── Playlists personalizadas
├── Búsqueda y filtros
├── Modo aleatorio
├── Modo repetición
└── Guardar estado con Hive

Fase 3 - Mejoras UX (TODO)
├── Ecualizador
├── Temporizador de apagado
├── Widgets de pantalla de inicio
├── Notificaciones mejoradas
└── Letras de canciones
```

## 🧪 Testing (Futuro)

```dart
Áreas a testear:
├── Unit tests
│   ├── AudioPlayerService
│   └── Lógica de negocio
├── Widget tests
│   ├── HomeScreen
│   └── PlayerScreen
└── Integration tests
    └── Flujo completo de reproducción
```

---

Esta arquitectura está diseñada para ser:
- ✅ **Escalable**: Fácil agregar nuevas funcionalidades
- ✅ **Mantenible**: Código organizado y documentado
- ✅ **Testeable**: Separación clara de responsabilidades
- ✅ **Performante**: Uso eficiente de recursos
