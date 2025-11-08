#  Guía de Compilación y Despliegue

##  Prerrequisitos

Antes de compilar debes tener instalado:

-  Flutter SDK (versión 3.9.2 o superior)
-  Android Studio o VS Code con extensiones Flutter
-  Java JDK 11 o superior
-  Android SDK (nivel de API 33+)

## Comandos de compilación

### Desarrollo (Debug)

Para ejecutar en modo desarrollo con hot reload:

```bash
flutter run
```

O con un dispositivo específico:

```bash
# Ver dispositivos disponibles
flutter devices

# Ejecutar en dispositivo específico
flutter run -d <device-id>
```

### Compilación de Producción (Release)

#### APK (para distribución manual)

```bash
# APK universal (funciona en todos los dispositivos)
flutter build apk

# APK optimizado por arquitectura (más pequeño)
flutter build apk --split-per-abi
```

Los archivos APK generados estarán en:
```
build/app/outputs/flutter-apk/
```

Tipos de APK generados con `--split-per-abi`:
- `app-armeabi-v7a-release.apk` - Para dispositivos ARM de 32 bits
- `app-arm64-v8a-release.apk` - Para dispositivos ARM de 64 bits
- `app-x86_64-release.apk` - Para emuladores y dispositivos x86

#### App Bundle (para Google Play Store)

```bash
flutter build appbundle
```

El archivo `.aab` estará en:
```
build/app/outputs/bundle/release/app-release.aab
```

##  Testing

### Ejecutar tests

```bash
# Todos los tests
flutter test

# Test específico
flutter test test/widget_test.dart

# Con cobertura
flutter test --coverage
```

### Análisis de código

```bash
# Analizar problemas
flutter analyze

# Formatear código
flutter format lib/

# Verificar todo antes de commit
flutter analyze && flutter test
```

##  Instalación manual del APK

### Vía USB (ADB)

```bash
# 1. Compilar APK
flutter build apk --release

# 2. Instalar en dispositivo conectado
flutter install
```

O usando adb directamente:

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Vía compartir archivo

1. Compila el APK: `flutter build apk`
2. Encuentra el archivo en `build/app/outputs/flutter-apk/app-release.apk`
3. Copia el archivo a tu dispositivo
4. En el dispositivo, habilita "Fuentes desconocidas" en Ajustes
5. Abre el archivo APK e instala

##  Firma de la aplicación (para producción)

### 1. Crear un keystore

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

### 2. Configurar key.properties

Crea el archivo `android/key.properties`:

```properties
storePassword=<tu-contraseña>
keyPassword=<tu-contraseña>
keyAlias=upload
storeFile=<ruta-a-keystore>/upload-keystore.jks
```

### 3. Actualizar build.gradle

En `android/app/build.gradle`, agrega antes de `android {}`:

```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

Y dentro de `buildTypes`:

```gradle
release {
    signingConfig signingConfigs.release
}
```

### 4. Compilar con firma

```bash
flutter build appbundle --release
```

##  Optimización del tamaño

### Reducir tamaño del APK

```bash
# Compilar con ofuscación
flutter build apk --obfuscate --split-debug-info=build/app/outputs/symbols

# APKs separados por arquitectura
flutter build apk --split-per-abi --obfuscate --split-debug-info=build/app/outputs/symbols
```

### Analizar tamaño

```bash
# Ver tamaño por componente
flutter build apk --analyze-size

# O para app bundle
flutter build appbundle --analyze-size
```

##  Modo Profile (para optimización de rendimiento)

```bash
# Ejecutar en modo profile
flutter run --profile

# Compilar APK en modo profile
flutter build apk --profile
```

Útil para:
- Medir rendimiento real
- Usar Flutter DevTools
- Debugging de performance

##  Debugging

### Logs en tiempo real

```bash
# Ver logs de Flutter
flutter logs

# O usar adb directamente
adb logcat
```

### Flutter DevTools

```bash
# Abrir DevTools
flutter pub global activate devtools
flutter pub global run devtools

# Luego ejecuta la app en modo debug o profile
flutter run --profile
```

##  Actualizar dependencias

```bash
# Ver dependencias desactualizadas
flutter pub outdated

# Actualizar a versiones compatibles
flutter pub upgrade

# Actualizar a últimas versiones (puede romper)
flutter pub upgrade --major-versions

# Limpiar caché
flutter clean
flutter pub get
```

##  Estructura de archivos generados

```
build/
├── app/
│   ├── outputs/
│   │   ├── flutter-apk/
│   │   │   ├── app-release.apk
│   │   │   ├── app-armeabi-v7a-release.apk
│   │   │   ├── app-arm64-v8a-release.apk
│   │   │   └── app-x86_64-release.apk
│   │   └── bundle/
│   │       └── release/
│   │           └── app-release.aab
│   └── intermediates/
└── ...
```

##  Checklist pre-publicación

Antes de publicar en Google Play:

- [ ] Versión actualizada en `pubspec.yaml`
- [ ] Íconos de app correctos en todos los tamaños
- [ ] Splash screen configurado
- [ ] Permisos mínimos necesarios
- [ ] App firmada con keystore de producción
- [ ] Tests ejecutados y pasando
- [ ] Sin warnings críticos en `flutter analyze`
- [ ] Probado en múltiples dispositivos/versiones de Android
- [ ] Capturas de pantalla para la tienda
- [ ] Descripción de la app lista
- [ ] Política de privacidad (si es necesaria)

##  Publicar en Google Play Store

### 1. Preparar assets

- Ícono: 512x512 px
- Capturas (mínimo 2): 
  - Teléfono: 320-3840 px en cualquier dimensión
  - Tablet (opcional): 1024-3840 px

### 2. Crear App en Play Console

1. Ve a [Google Play Console](https://play.google.com/console)
2. Crear aplicación
3. Completa toda la información requerida
4. Sube el App Bundle: `build/app/outputs/bundle/release/app-release.aab`

### 3. Configurar lanzamiento

- Pruebas internas
- Pruebas cerradas
- Pruebas abiertas
- Producción

##  Notas importantes

### Tamaños típicos

- APK universal: ~20-30 MB
- APK por arquitectura: ~15-20 MB cada uno
- App Bundle: ~18-25 MB (Google genera APKs optimizados)

### Versionado

En `pubspec.yaml`:
```yaml
version: 1.0.0+1
#        │    │ │
#        │    │ └─ Build number (Android: versionCode)
#        │    └─── Patch version
#        └──────── Major.Minor version (Android: versionName)
```

Incrementa:
- **Major**: Cambios grandes/incompatibles
- **Minor**: Nuevas funcionalidades
- **Patch**: Correcciones de bugs
- **Build**: Con cada compilación

### Comandos útiles

```bash
# Limpiar proyecto completamente
flutter clean

# Verificar instalación de Flutter
flutter doctor -v

# Ver información del dispositivo
flutter devices -v

# Capturar screenshot
flutter screenshot

# Crear ícono de launcher
flutter pub run flutter_launcher_icons:main
```

##  Solución de problemas comunes

### Error: "Gradle build failed"
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Error: "Unsupported class file major version"
- Actualiza Java JDK a versión 11 o superior
- Verifica en `android/gradle.properties`

### APK muy grande
- Usa `--split-per-abi`
- Habilita `--obfuscate`
- Revisa assets innecesarios


