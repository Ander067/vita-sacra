import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'home_view.dart';
import 'login_view.dart';

// Pantalla de bienvenida de Vita Sacra.
class SplashView extends StatefulWidget {
  const SplashView({super.key});

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView> {
  // Servicio encargado de comprobar la sesion.
  final AuthService _authService = AuthService();

  // Controla el retraso inicial antes de verificar la sesion.
  Timer? _timerSesion;

  // Evitar ejecutar la navegacion mas de una vez.
  bool _navegacionRealizada = false;

  // Pool de frases de bienvenida.
  final List<String> _frasesInicio = [
    'El conocimiento es el primer paso hacia el bienestar.',
    'Cuidar la salud tambien comienza con aprender.',
    'Conocimiento medico al alcance de todos.',
    'La informacion confiable puede marcar la diferencia.',
    'Un espacio para compartir, aprender y cuidar.',
    'La salud se fortalece con conocimiento.',
    'Bienvenido a una comunidad dedicada al bienestar.',
    'Cada descubrimiento comienza con una pregunta.',
    'Compartiendo conocimiento para una vida mejor.',
    'La prevencion tambien nace del conocimiento.',
  ];

  // Seleccionar una frase aleatoria.
  late final String _fraseInicio =
      _frasesInicio[Random().nextInt(_frasesInicio.length)];

  @override
  void initState() {
    super.initState();

    // Verificar la sesion al iniciar la aplicacion.
    _timerSesion = Timer(const Duration(seconds: 4), _verificarSesion);
  }

  // Comprobar si el usuario tiene una sesion valida.
  Future<void> _verificarSesion() async {
    // Evitar continuar si la pantalla ya fue cerrada.
    if (!mounted || _navegacionRealizada) {
      return;
    }

    bool sesionActiva = false;

    try {
      // Consultar la validez de la sesion con FastAPI.
      sesionActiva = await _authService.sesionValida();
    } catch (error) {
      // Continuar sin sesion cuando ocurra un error.
      debugPrint('Error al verificar la sesion: $error');
      sesionActiva = false;
    }

    // Evitar navegar si la pantalla ya fue cerrada.
    if (!mounted || _navegacionRealizada) {
      return;
    }

    // Marcar la navegacion como realizada.
    _navegacionRealizada = true;

    // Seleccionar la pantalla correspondiente.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) {
          if (sesionActiva) {
            return const HomeView();
          }

          return const LoginView();
        },
      ),
    );
  }

  @override
  void dispose() {
    // Cancelar la espera inicial si la vista se destruye antes de tiempo.
    _timerSesion?.cancel();

    // Liberar los recursos del servicio HTTP.
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Obtener los colores del tema actual.
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),

            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logotipo principal de Vita Sacra.
                Image.asset(
                  'assets/images/vita_sacra_logo.png',
                  width: 340,
                  height: 190,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 8),

                // Version del proyecto.
                Text(
                  '1.0.0 - Arca',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colores.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 24),

                // Frase aleatoria de bienvenida.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  child: Text(
                    _fraseInicio,
                    key: ValueKey(_fraseInicio),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ),

                const SizedBox(height: 60),

                // Indicador de carga.
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colores.primary,
                  ),
                ),

                const SizedBox(height: 20),

                // Mensaje durante la inicializacion.
                Text(
                  'Preparando Vita Sacra...',
                  style: TextStyle(
                    fontSize: 14,
                    color: colores.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
