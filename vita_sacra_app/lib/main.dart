import 'package:flutter/material.dart';

import 'config/app_theme.dart';
import 'views/splash_view.dart';

// Punto de entrada de la aplicacion.
void main() {
  // Inicializar los componentes de Flutter.
  WidgetsFlutterBinding.ensureInitialized();

  // Ejecutar la aplicacion.
  runApp(const VitaSacraApp());
}

// Widget principal de Vita Sacra.
class VitaSacraApp extends StatefulWidget {
  const VitaSacraApp({super.key});

  // Obtener el estado principal de la aplicacion.
  static VitaSacraAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<VitaSacraAppState>();
  }

  @override
  State<VitaSacraApp> createState() => VitaSacraAppState();
}

// Estado principal de la aplicacion.
class VitaSacraAppState extends State<VitaSacraApp> {
  // Preferencia global de apariencia.
  ThemeMode _temaActual = ThemeMode.system;

  // Consultar el tema seleccionado.
  ThemeMode get temaActual => _temaActual;

  // Cambiar el tema de toda la aplicacion.
  void cambiarTema(ThemeMode tema) {
    // Evitar actualizaciones innecesarias.
    if (_temaActual == tema) {
      return;
    }

    setState(() {
      _temaActual = tema;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Nombre de la aplicacion.
      title: 'Vita Sacra',

      // Ocultar la etiqueta de depuracion.
      debugShowCheckedModeBanner: false,

      // Aplicar el tema claro de la aplicacion.
      theme: AppTheme.temaClaro,

      // Aplicar el tema oscuro de la aplicacion.
      darkTheme: AppTheme.temaOscuro,

      // Utilizar la preferencia global seleccionada.
      themeMode: _temaActual,

      // Pantalla inicial de la aplicacion.
      home: const SplashView(),
    );
  }
}
