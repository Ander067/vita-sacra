import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

// Pantalla de registro de usuarios.
class RegistroView extends StatefulWidget {
  const RegistroView({super.key});

  @override
  State<RegistroView> createState() => _RegistroViewState();
}

class _RegistroViewState extends State<RegistroView> {
  // Clave para validar el formulario.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controladores de los campos.
  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _correoController = TextEditingController();
  final TextEditingController _contrasenaController = TextEditingController();
  final TextEditingController _confirmarController = TextEditingController();

  // Servicio de autenticacion.
  final AuthService _authService = AuthService();

  // Variables de estado de la pantalla.
  bool _mostrarContrasena = false;
  bool _mostrarConfirmacion = false;
  bool _cargando = false;

  // Validar el nombre del usuario.
  String? _validarNombre(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa tu nombre completo.';
    }

    if (valor.trim().length < 3) {
      return 'El nombre debe tener al menos 3 caracteres.';
    }

    return null;
  }

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
      return 'Ingresa una contrasena.';
    }

    if (valor.length < 8) {
      return 'Utiliza al menos 8 caracteres.';
    }

    return null;
  }

  // Validar la confirmacion de la contrasena.
  String? _validarConfirmacion(String? valor) {
    if (valor == null || valor.isEmpty) {
      return 'Confirma tu contrasena.';
    }

    if (valor != _contrasenaController.text) {
      return 'Las contrasenas no coinciden.';
    }

    return null;
  }

  // Mostrar mensajes al usuario.
  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Registrar al usuario mediante FastAPI.
  Future<void> _registrarUsuario() async {
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
      // Enviar los datos al servicio de autenticacion.
      await _authService.registrar(
        nombre: _nombreController.text.trim(),
        correo: _correoController.text.trim(),
        contrasena: _contrasenaController.text,
      );

      if (!mounted) {
        return;
      }

      // Regresar al inicio de sesion indicando el resultado.
      Navigator.pop(
        context,
        'Cuenta registrada correctamente. Ahora puedes iniciar sesion.',
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

      _mostrarMensaje('Ocurrio un error al registrar la cuenta.');
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Liberar los controladores y el servicio.
    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    _confirmarController.dispose();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Obtener los colores del tema.
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      appBar: AppBar(title: const Text('Registro'), centerTitle: true),

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
                    // Icono del registro.
                    Center(
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: colores.primaryContainer,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Icon(
                          Icons.person_add_alt_1_outlined,
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

                    // Version del proyecto.
                    Text(
                      '1.0.0 - Arca',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 25),

                    // Titulo del formulario.
                    Text(
                      'Crear una cuenta',
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
                      'Registrate para formar parte de nuestra comunidad.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: colores.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 30),

                    // Campo de nombre completo.
                    TextFormField(
                      controller: _nombreController,
                      enabled: !_cargando,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: _validarNombre,
                    ),

                    const SizedBox(height: 20),

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
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
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

                    const SizedBox(height: 20),

                    // Campo de confirmacion.
                    TextFormField(
                      controller: _confirmarController,
                      enabled: !_cargando,
                      obscureText: !_mostrarConfirmacion,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) {
                        if (!_cargando) {
                          _registrarUsuario();
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Confirmar contrasena',
                        prefixIcon: const Icon(Icons.verified_user_outlined),
                        border: const OutlineInputBorder(),

                        // Mostrar u ocultar la confirmacion.
                        suffixIcon: IconButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  setState(() {
                                    _mostrarConfirmacion =
                                        !_mostrarConfirmacion;
                                  });
                                },
                          icon: Icon(
                            _mostrarConfirmacion
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: _validarConfirmacion,
                    ),

                    const SizedBox(height: 30),

                    // Boton para crear la cuenta.
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _cargando ? null : _registrarUsuario,
                        child: _cargando
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Crear cuenta'),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Acceso al inicio de sesion.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            '¿Ya tienes una cuenta?',
                            style: TextStyle(color: colores.onSurfaceVariant),
                          ),
                        ),
                        TextButton(
                          onPressed: _cargando
                              ? null
                              : () {
                                  Navigator.pop(context);
                                },
                          child: const Text('Inicia sesion'),
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
