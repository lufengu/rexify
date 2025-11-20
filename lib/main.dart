import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/audio_player_service.dart';
import 'services/audio_handler.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'services/download_manager.dart';
import 'screens/root_dashboard.dart';
import 'services/permission_utils.dart';

late AudioHandler audioHandler; // tipo general (evita error de asignación)

// Nuevo: notificador global para cambiar themeMode en runtime
late ValueNotifier<ThemeMode> themeModeNotifier;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializar flutter_downloader para tareas en background (Android).
  try {
    await FlutterDownloader.initialize(
      debug: true, // logs para desarrollo
      ignoreSsl: true,
    );
    // Registrar callback global para progreso/estado (DownloadManager debe exponer callback válido)
    try {
      FlutterDownloader.registerCallback(DownloadManager.downloadCallback);
    } catch (_) {
      // ignore: avoid_print
      print('No se pudo registrar callback de FlutterDownloader (verificar método estático).');
    }
  } catch (e) {
    // ignore: avoid_print
    print('FlutterDownloader init falló: $e');
  }

  // Initialize Hive
  await Hive.initFlutter();

  // Inicializar datos de localización para Intl (fechas, etc.)
  try {
    await initializeDateFormatting('es');
    Intl.defaultLocale = 'es';
  } catch (e) {
    // ignore: avoid_print
    print('No se pudo inicializar Intl/es: $e');
  }

  // Abrir box de settings (persistencia simple para tema)
  final settingsBox = await Hive.openBox('rexify_settings');
  final stored = settingsBox.get('theme', defaultValue: 'dark') as String;
  ThemeMode initialMode;
  if (stored == 'light') initialMode = ThemeMode.light;
  else if (stored == 'system') initialMode = ThemeMode.system;
  else initialMode = ThemeMode.dark;
  themeModeNotifier = ValueNotifier<ThemeMode>(initialMode);

  // Initialize audio player service (tu wrapper debe exponer init())
  try {
    await AudioPlayerService().init();
  } catch (e) {
    // ignore: avoid_print
    print('AudioPlayerService initialization falló: $e');
  }

  // Initialize audio service handler para notificaciones
  try {
    final handler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.example.reproductor_musica',
        androidNotificationChannelName: 'Rexify',
        // Nota: Con androidStopForegroundOnPause=false, el flag androidNotificationOngoing no tiene efecto
        // y provoca una aserción. Para mantener foreground persistente en pausa, dejamos ongoing en false.
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
      ),
    );
    audioHandler = handler;
  } catch (e) {
    // ignore: avoid_print
    print('AudioService.init falló: $e');
    // como fallback, crea una instancia mínima para no romper referencias
    audioHandler = MyAudioHandler();
  }

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Verificación inicial de permisos de almacenamiento (no bloqueante).
    // Sólo solicita si falta. Evita spam de diálogos en cada arranque.
    if (Platform.isAndroid) {
      // Ejecutar en microtask para no interferir con build inicial.
      Future.microtask(() => PermissionUtils.ensureStoragePermission());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Paleta base (mantiene identidad visual)
    const Color basePrimary = Color(0xFF6C63FF); // morado actual
    const Color baseAccent = Color(0xFFFF6584);  // acento rosado
    const Color baseTertiary = Color(0xFF4ECDC4);
    const Color darkBg = Color(0xFF0A0E27);      // fondo principal (negro mate azulado)
    const Color darkSurface = Color(0xFF1A1F3A); // tarjetas / superficies
    const Color darkElevated = Color(0xFF252B47); // superficies elevadas
    const Color onSurface = Colors.white70;

    final ThemeData darkTheme = ThemeData(
      brightness: Brightness.dark,
      primaryColor: basePrimary,
      scaffoldBackgroundColor: darkBg,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: basePrimary,
        secondary: baseAccent,
        tertiary: baseTertiary,
        surface: darkSurface,
        background: darkBg,
        onPrimary: Colors.white,
        onSurface: onSurface,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white),
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: darkSurface.withOpacity(0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: basePrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.white70),
      sliderTheme: SliderThemeData(
        activeTrackColor: basePrimary,
        thumbColor: basePrimary,
        inactiveTrackColor: Colors.white12,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: basePrimary),
      cardColor: darkSurface,
      canvasColor: darkBg,
      dialogBackgroundColor: darkElevated,
      shadowColor: Colors.black87,
    );

    // Si quieres mantener también un tema claro coherente, define `theme`
    final ThemeData lightTheme = ThemeData(
      brightness: Brightness.light,
      primaryColor: basePrimary,
      colorScheme: ColorScheme.fromSeed(seedColor: basePrimary, primary: basePrimary, secondary: baseAccent),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Rexify',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,        // opcional: tema claro preparado
      darkTheme: darkTheme,     // tema oscuro completo y adaptado
      themeMode: ThemeMode.dark,// fuerza modo oscuro en toda la app
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const RootDashboard(),
    );
  }
}
