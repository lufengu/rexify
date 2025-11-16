# Guía de Uso - Reproductor de Música

### 1. Primera ejecución

Cuando abras la aplicación por primera vez:

1. La app solicitará **permiso para acceder a tus archivos de audio**
2. Toca en "Otorgar permiso" o acepta el permiso en el diálogo del sistema
3. La aplicación escaneará automáticamente todas las canciones en tu dispositivo
4. Verás una lista con todas tus canciones disponibles

### 2. Si no ves canciones

Si la lista aparece vacía:

- Asegúrate de tener archivos de música en tu dispositivo (.mp3, .wav, .m4a, etc.)
- Verifica que otorgaste el permiso de lectura de archivos
- Toca el botón de **actualizar** (🔄) en la parte superior derecha
- Si aún no aparecen, reinicia la aplicación

## 🎵 Reproducir música

### Pantalla principal

1. **Lista de canciones**: Verás todas tus canciones con:
   - Portada del álbum (si está disponible)
   - Título de la canción
   - Nombre del artista
   - Duración

2. **Reproducir una canción**:
   - Simplemente toca cualquier canción de la lista
   - Se abrirá la pantalla de reproducción completa
   - La canción comenzará a sonar automáticamente

### Mini reproductor

En la parte inferior de la pantalla principal verás un **mini reproductor** cuando haya una canción activa:

-  Muestra la canción actual
-  Botones de control rápido:
  -  Anterior
  -  Play/Pause
  -  Siguiente
-  Toca el mini reproductor para abrir la pantalla completa

##  Controles de reproducción

### Pantalla de reproducción completa

#### Carátula del álbum
- Muestra la portada de la canción
- **Gira** mientras la música está sonando
- Se detiene cuando pausas

#### Información de la canción
- **Título**: Nombre de la canción
- **Artista**: Intérprete o artista
- **Álbum**: Nombre del álbum

#### Barra de progreso
- Muestra el tiempo transcurrido y total
- **Desliza** la barra para adelantar o retroceder en la canción
- Actualización en tiempo real

#### Botones de control

| Botón | Función |
|-------|---------|
|  | **Anterior**: Reproduce la canción anterior. Si han pasado más de 3 segundos, reinicia la canción actual |
|  | **Play/Pause**: Pausa o reanuda la reproducción |
|  | **Siguiente**: Salta a la siguiente canción |

#### Control de volumen
- Desliza la barra de volumen para ajustar el nivel de audio
- Va de 0% (silencio) a 100% (volumen máximo)
- El icono cambia según el nivel de volumen

##  Modo oscuro

La aplicación se adapta automáticamente al tema de tu sistema:

- **Modo claro**: Durante el día o si tu dispositivo está en modo claro
- **Modo oscuro**: Por la noche o si tu dispositivo está en modo oscuro

Para cambiar entre modos:
1. Ve a los ajustes de tu dispositivo
2. Busca "Tema" o "Pantalla"
3. Cambia entre modo claro/oscuro
4. La app se actualizará automáticamente

##  Comportamiento de la aplicación

### Reproducción continua
- Al terminar una canción, automáticamente comienza la siguiente
- Las canciones se reproducen en el orden en que aparecen en la lista

### Reproducción en segundo plano
- Puedes minimizar la aplicación y la música seguirá sonando
- La pantalla puede apagarse y la música continuará
- Para controlar la música, simplemente abre la app de nuevo

### Navegación
- Usa el botón **Atrás** (←) para volver a la lista de canciones
- El mini reproductor siempre está disponible en la pantalla principal

##  Solución de problemas

### La música no suena
- Verifica el volumen de tu dispositivo
- Comprueba que la canción no esté corrupta
- Asegúrate de que el archivo sea de un formato compatible

### Las canciones no aparecen
- Verifica los permisos de la aplicación en Ajustes > Apps > Reproductor de Música
- Asegúrate de que los archivos de música estén en la memoria del dispositivo
- Toca el botón de actualizar

### La aplicación se cierra inesperadamente
- Asegúrate de tener espacio disponible en el dispositivo
- Reinicia la aplicación
- Si persiste, reinstala la aplicación

### La portada no se muestra
- Algunos archivos de audio no tienen imagen de portada incrustada
- La app mostrará un ícono de música genérico con un color aleatorio


## Requisitos del sistema

- Android 13 o superior (recomendado)
- Al menos 50 MB de espacio libre
- Archivos de audio en formatos: MP3, WAV, M4A, AAC, FLAC

## 🔍 Búsqueda y descarga desde YouTube (beta)

La app incluye una pantalla para buscar música en YouTube y descargar directamente el audio en MP3 sin almacenarlo en el servidor.

### Cómo usarlo
1. En la pantalla principal toca el botón con el ícono de globo terráqueo (🌐).
2. Ingresa el nombre de la canción o artista en el campo de texto superior.
3. Pulsa el botón de búsqueda (lupa) para cargar resultados dentro del WebView.
4. Pulsa el botón "MP3" para solicitar la conversión y descarga.
5. Al finalizar verás una notificación tipo SnackBar con la opción "Reproducir".
6. El archivo se guarda en el directorio temporal de la app (puede limpiarse automáticamente por el sistema). Próximamente opción para guardarlo de forma persistente.

### Consideraciones técnicas
| Aspecto | Detalle |
|---------|---------|
| Backend | Flask + yt-dlp + ffmpeg (transcodificación en streaming) |
| Protocolo | Petición GET a /download?q=TU_TERMINO |
| Formato salida | MP3 192 kbps |
| Almacenamiento servidor | Ninguno (stream en tiempo real) |
| Limitaciones | Calidad sujeta a fuente original; requiere conexión estable |

### Errores comunes
| Mensaje | Causa | Solución |
|---------|-------|----------|
| ffmpeg not found | ffmpeg no instalado en máquina donde corre backend | Instalar paquete ffmpeg (según SO) |
| No results found | yt-dlp no encontró coincidencias | Intenta término más específico |
| 500 No downloadable formats | Video sin formatos de audio disponibles | Prueba otra canción |

### Seguridad y uso responsable
Esta función está pensada para uso personal y educativo. Respeta los derechos de autor y términos de servicio de las plataformas donde realizas búsquedas.

### Extensibilidad planeada
En el futuro se podrán agregar otras fuentes (p.ej. SoundCloud, Jamendo) manteniendo la misma interfaz de descarga.



