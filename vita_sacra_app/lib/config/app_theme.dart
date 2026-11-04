import 'package:flutter/material.dart';

class AppTheme {
  // Paleta de colores oficial de Vita Sacra.
  static const Color principal = Color(0xFF8BB8E8);
  static const Color secundario = Color(0xFFB8D8F0);
  static const Color titulosIconos = Color(0xFF2B5B84);
  static const Color fondo = Color(0xFFF0F6FC);
  static const Color tarjetas = Color(0xFFE4F0FA);
  static const Color contraste = Color(0xFFFFFFFF);

  // Paleta complementaria para el tema oscuro.
  static const Color fondoOscuro = Color(0xFF101B27);
  static const Color tarjetasOscuro = Color(0xFF1B2B3B);
  static const Color superficieOscuro = Color(0xFF24384B);
  static const Color textoOscuro = Color(0xFFEAF3FC);

  // Tema claro principal de la aplicacion.
  static ThemeData get temaClaro {
    final ColorScheme esquema =
        ColorScheme.fromSeed(
          seedColor: principal,
          brightness: Brightness.light,
        ).copyWith(
          primary: titulosIconos,
          onPrimary: contraste,
          primaryContainer: secundario,
          onPrimaryContainer: titulosIconos,
          secondary: principal,
          onSecondary: titulosIconos,
          surface: fondo,
          onSurface: titulosIconos,
          surfaceContainerLow: tarjetas,
          outlineVariant: secundario,
        );

    return _crearTema(esquema: esquema, esOscuro: false);
  }

  // Tema oscuro de la aplicacion.
  static ThemeData get temaOscuro {
    final ColorScheme esquema =
        ColorScheme.fromSeed(
          seedColor: principal,
          brightness: Brightness.dark,
        ).copyWith(
          primary: principal,
          onPrimary: fondoOscuro,
          primaryContainer: superficieOscuro,
          onPrimaryContainer: textoOscuro,
          secondary: secundario,
          onSecondary: fondoOscuro,
          surface: fondoOscuro,
          onSurface: textoOscuro,
          surfaceContainerLow: tarjetasOscuro,
          outlineVariant: superficieOscuro,
        );

    return _crearTema(esquema: esquema, esOscuro: true);
  }

  // Construir la configuracion visual compartida.
  static ThemeData _crearTema({
    required ColorScheme esquema,
    required bool esOscuro,
  }) {
    // Obtener los colores correspondientes al tema.
    final Color colorFondo = esOscuro ? fondoOscuro : fondo;
    final Color colorTarjetas = esOscuro ? tarjetasOscuro : tarjetas;
    final Color colorTexto = esquema.onSurface;
    final Color colorPrincipal = esquema.primary;
    final Color colorContraste = esquema.onPrimary;
    final Color colorCampos = esOscuro ? tarjetasOscuro : contraste;
    final Color colorBordes = esOscuro ? superficieOscuro : secundario;

    return ThemeData(
      useMaterial3: true,
      brightness: esquema.brightness,
      colorScheme: esquema,
      scaffoldBackgroundColor: colorFondo,

      // Tipografia general.
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
          color: colorTexto,
        ),
        headlineMedium: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.bold,
          color: colorTexto,
        ),
        titleLarge: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: colorTexto,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: colorTexto,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: colorTexto),
        bodyMedium: TextStyle(fontSize: 14, color: colorTexto),
      ),

      // Barras superiores.
      appBarTheme: AppBarTheme(
        backgroundColor: colorFondo,
        foregroundColor: colorTexto,
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),

      // Botones principales.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorPrincipal,
          foregroundColor: colorContraste,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      // Botones secundarios.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorPrincipal,
          side: BorderSide(color: colorBordes, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      // Botones de texto.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorPrincipal),
      ),

      // Tarjetas de contenido.
      cardTheme: CardThemeData(
        color: colorTarjetas,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Campos de formularios.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorCampos,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorBordes),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorBordes),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorPrincipal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: esquema.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: esquema.error, width: 2),
        ),
      ),

      // Barra de navegacion inferior.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorCampos,
        indicatorColor: esquema.primaryContainer,
        labelTextStyle: WidgetStateProperty.all(
          TextStyle(
            color: colorTexto,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Botones flotantes.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: esquema.secondary,
        foregroundColor: esquema.onSecondary,
      ),

      // Indicadores de carga.
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colorPrincipal),

      // Mensajes emergentes.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: esOscuro ? superficieOscuro : titulosIconos,
        contentTextStyle: const TextStyle(color: contraste),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // Separadores.
      dividerTheme: DividerThemeData(color: colorBordes, thickness: 1),
    );
  }
}
