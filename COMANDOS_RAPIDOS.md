# ⚡ Comandos Rápidos

## 🚀 Inicio rápido

```bash
# 1. Verificar Flutter
flutter doctor

# 2. Obtener dependencias
flutter pub get

# 3. Conectar dispositivo Android
# (Conecta tu dispositivo o inicia un emulador)

# 4. Ejecutar la app
flutter run
```

## 🔨 Desarrollo

```bash
# Ejecutar en modo debug (hot reload habilitado)
flutter run

# Ejecutar en dispositivo específico
flutter run -d <device-id>

# Ver dispositivos conectados
flutter devices

# Hot reload (mientras la app está corriendo)
# Presiona 'r' en la terminal

# Hot restart (mientras la app está corriendo)
# Presiona 'R' en la terminal

# Ver logs en tiempo real
flutter logs
```

## 🧪 Testing y análisis

```bash
# Analizar código (buscar problemas)
flutter analyze

# Formatear código
flutter format lib/

# Ejecutar tests
flutter test

# Limpiar proyecto
flutter clean

# Reinstalar dependencias
flutter pub get
```

## 📦 Compilación

```bash
# APK para desarrollo/testing
flutter build apk --debug

# APK de producción (optimizado)
flutter build apk --release

# APK separado por arquitectura (más pequeño)
flutter build apk --split-per-abi --release

# App Bundle para Google Play
flutter build appbundle --release

# Con ofuscación de código
flutter build apk --obfuscate --split-debug-info=build/app/outputs/symbols
```

## 📱 Instalación

```bash
# Instalar APK en dispositivo conectado
flutter install

# O usando adb directamente
adb install build/app/outputs/flutter-apk/app-release.apk

# Desinstalar app del dispositivo
adb uninstall com.example.reproductor_musica
```

## 🐛 Debugging

```bash
# Ejecutar en modo profile (para performance)
flutter run --profile

# Ver información detallada de Flutter
flutter doctor -v

# Capturar screenshot
flutter screenshot

# Abrir DevTools
flutter pub global activate devtools
flutter pub global run devtools
```

## 🔄 Actualización

```bash
# Ver dependencias desactualizadas
flutter pub outdated

# Actualizar dependencias
flutter pub upgrade

# Actualizar Flutter
flutter upgrade
```

## 🧹 Limpieza

```bash
# Limpieza completa
flutter clean
cd android && ./gradlew clean && cd ..
flutter pub get

# Eliminar caché de build
rm -rf build/
```

## 📊 Información

```bash
# Versión de Flutter
flutter --version

# Información del dispositivo
flutter devices -v

# Tamaño del APK
flutter build apk --analyze-size

# Configuración del proyecto
flutter config
```

## 🎯 Comandos más usados

### Durante desarrollo
```bash
flutter run              # Iniciar app
# Luego presiona:
r                       # Hot reload
R                       # Hot restart
q                       # Salir
```

### Antes de commit
```bash
flutter analyze && flutter format lib/ && flutter test
```

### Para compilar y distribuir
```bash
flutter clean
flutter pub get
flutter build apk --split-per-abi --release
```

## 💡 Tips

### Ver logs filtrados
```bash
# Solo mensajes de Flutter
adb logcat | grep -i flutter

# Solo errores
adb logcat *:E
```

### Reiniciar ADB
```bash
adb kill-server
adb start-server
```

### Limpiar completamente
```bash
flutter clean
rm -rf .dart_tool/
rm -rf .packages
rm pubspec.lock
flutter pub get
```

### Ejecutar con configuración específica
```bash
# Con más memoria para Gradle
flutter run --no-sound-null-safety
```

## 🆘 Solución rápida de problemas

```bash
# Problema: Build falla
flutter clean && flutter pub get && flutter run

# Problema: Gradle error
cd android && ./gradlew clean && cd ..
flutter clean && flutter run

# Problema: Dependencias rotas
rm pubspec.lock
flutter pub get

# Problema: Dispositivo no detectado
adb kill-server && adb start-server
flutter devices
```

## 📝 Notas

- Usa `flutter run` para desarrollo (hot reload)
- Usa `flutter build apk --release` para producción
- Siempre ejecuta `flutter analyze` antes de hacer commit
- `flutter clean` resuelve muchos problemas de caché

---

**Para más información detallada, consulta COMPILACION.md**
