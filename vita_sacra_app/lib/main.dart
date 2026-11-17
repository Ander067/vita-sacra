import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/app_theme.dart';
import 'views/splash_view.dart';

const String _claveTemaPreferido = 'vita_sacra_theme_mode';

// Punto de entrada de la aplicacion.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final SharedPreferences preferencias = await SharedPreferences.getInstance();

  runApp(VitaSacraApp(preferencias: preferencias));
}

// Widget principal de Vita Sacra.
class VitaSacraApp extends StatefulWidget {
  const VitaSacraApp({super.key, this.preferencias});

  final SharedPreferences? preferencias;

  // Obtener el estado principal de la aplicacion.
  static VitaSacraAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<VitaSacraAppState>();
  }

  @override
  State<VitaSacraApp> createState() => VitaSacraAppState();
}

// Estado principal de la aplicacion.
class VitaSacraAppState extends State<VitaSacraApp> {
  late ThemeMode _temaActual;

  // Consultar el tema seleccionado.
  ThemeMode get temaActual => _temaActual;

  @override
  void initState() {
    super.initState();
    _temaActual = _leerTemaGuardado();
  }

  ThemeMode _leerTemaGuardado() {
    final String? temaGuardado = widget.preferencias?.getString(
      _claveTemaPreferido,
    );

    switch (temaGuardado) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  // Cambiar y guardar el tema de toda la aplicacion.
  Future<void> cambiarTema(ThemeMode tema) async {
    if (_temaActual == tema) {
      return;
    }

    final SharedPreferences? preferencias = widget.preferencias;

    if (preferencias != null) {
      final bool guardado = await preferencias.setString(
        _claveTemaPreferido,
        tema.name,
      );

      if (!guardado) {
        throw StateError('No fue posible guardar la preferencia del tema.');
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _temaActual = tema;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vita Sacra',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.temaClaro,
      darkTheme: AppTheme.temaOscuro,
      themeMode: _temaActual,
      home: const SplashView(),
    );
  }
}
