import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'home_view.dart';
import 'registro_view.dart';

// Pantalla de inicio de sesion.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  // Clave para validar el formulario.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controladores de los campos.
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();

  // Servicio de autenticacion.
  final AuthService _authService = AuthService();

  // Variables de estado de la pantalla.
  bool _mostrarContrasena = false;
  bool _cargando = false;

  // Validar el correo electronico.
  String? _validarCorreo(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu correo electronico.';
    }

    final RegExp expresion = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!expresion.hasMatch(valor.trim())) {
      return 'Ingresa un correo electronico valido.';
    }

    return null;
  }

  // Validar la contrasena.
  String? _validarContrasena(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Ingresa tu contrasena.';
    }

    return null;
  }

  // Mostrar mensajes al usuario.
  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Iniciar sesion mediante FastAPI.
  Future<void> _iniciarSesion() async {
    // Evitar solicitudes duplicadas.
    if (_cargando) {
      return;
    }

    // Validar los campos del formulario.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    // Ocultar el teclado antes de realizar la solicitud.
    FocusScope.of(context).unfocus();

    setState(() {
      _cargando = true;
    });

    try {
      // Enviar las credenciales al servidor.
      await _authService.iniciarSesion(
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      // Comprobar que el token permita consultar el perfil.
      final bool sesionValida = await _authService.sesionValida();

      if (!sesionValida) {
        throw const ApiException('No fue posible verificar la sesion.');
      }

      // Evitar navegar si la pantalla ya no esta montada.
      if (!mounted) {
        return;
      }

      // Abrir la pantalla principal y eliminar el historial anterior.
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeView()),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje(error.mensaje);
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('Ocurrio un error al iniciar sesion.');
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  // Abrir la pantalla de registro.
  Future<void> _abrirRegistro() async {
    // Evitar abrir el registro mientras se inicia sesion.
    if (_cargando) {
      return;
    }

    // Esperar el resultado de la pantalla de registro.
    final String? mensaje = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const RegistroView()),
    );

    // Verificar que la pantalla siga activa.
    if (!mounted) {
      return;
    }

    // Mostrar el mensaje cuando el registro sea exitoso.
    if (mensaje != null && mensaje.isNotEmpty) {
      _mostrarMensaje(mensaje);
    }
  }

  @override
  void dispose() {
    // Liberar los controladores y el servicio.
    _correoController.dispose();
    _contrasenaController.dispose();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Obtener los colores del tema.
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),

            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),

              child: Form(
                key: _formKey,

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Icono de Vita Sacra.
                    Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: colores.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.monitor_heart_outlined,
                          size: 55,
                          color: colores.onPrimaryContainer,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Nombre de la aplicacion.
                    Text(
                      'Vita Sacra',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colores.primary,
                      ),
                    ),

                    const SizedBox(height: 5),

                    // Version de la aplicacion.
                    Text(
                      '1.0.0 - Arca',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Titulo del formulario.
                    Text(
                      'Iniciar sesion',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colores.onSurface,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Mensaje de bienvenida.
                    Text(
                      'Bienvenido de nuevo. Ingresa tus datos para continuar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Campo de correo electronico.
                    TextFormField(
                      controller: _correoController,
                      enabled: !_cargando,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo electronico',
                        hintText: 'correo@ejemplo.com',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarCorreo,
                    ),

                    const SizedBox(height: 20),

                    // Campo de contrasena.
                    TextFormField(
                      controller: _contrasenaController,
                      enabled: !_cargando,
                      obscureText: !_mostrarContrasena,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) {
                        if (!_cargando) {
                          _iniciarSesion();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Contrasena',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),

                        // Mostrar u ocultar la contrasena.
                        suffixIcon: IconButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  setState(() {
                                    _mostrarContrasena = !_mostrarContrasena;
                                  });
                                },
                          icon: Icon(
                            _mostrarContrasena
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: _validarContrasena,
                    ),

                    const SizedBox(height: 30),

                    // Boton de inicio de sesion.
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _iniciarSesion,
                        child: _cargando
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Iniciar sesion'),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Acceso al registro de usuarios.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            '¿No tienes una cuenta?',
                            style: TextStyle(color: colores.onSurfaceVariant),
                          ),
                        ),

                        TextButton(
                          onPressed: _cargando ? null : _abrirRegistro,
                          child: const Text('Registrate'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
