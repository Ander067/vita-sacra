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

  // Evitar ejecutar la navegacion mas de una vez.
  bool _navegacionRealizada = false;

  @override
  void initState() {
    super.initState();

    // Verificar la sesion al iniciar la aplicacion.
    _verificarSesion();
  }

  // Comprobar si el usuario tiene una sesion valida.
  Future<void> _verificarSesion() async {
    bool sesionActiva = false;

    try {
      // Mostrar brevemente la pantalla de bienvenida.
      await Future.delayed(const Duration(seconds: 2));

      // Evitar continuar si la pantalla fue cerrada.
      if (!mounted) {
        return;
      }

      // Consultar la validez de la sesion con FastAPI.
      sesionActiva = await _authService.sesionValida();
    } catch (error) {
      // Continuar sin sesion cuando ocurra un error.
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
                // Icono principal de la aplicacion.
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: colores.primaryContainer,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    size: 70,
                    color: colores.onPrimaryContainer,
                  ),
                ),

                const SizedBox(height: 30),

                // Nombre de la aplicacion.
                Text(
                  'Vita Sacra',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: colores.primary,
                  ),
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

                const SizedBox(height: 20),

                // Mensaje de bienvenida.
                Text(
                  'Conocimiento medico al alcance de todos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: colores.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 60),

                // Indicador de carga.
                CircularProgressIndicator(color: colores.primary),

                const SizedBox(height: 20),

                // Mensaje durante la inicializacion.
                Text(
                  'Iniciando aplicacion...',
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
