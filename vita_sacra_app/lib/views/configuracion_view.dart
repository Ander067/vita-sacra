import 'package:flutter/material.dart';

import '../main.dart';
import '../services/auth_service.dart';

// Pantalla para administrar las preferencias.
class ConfiguracionView extends StatefulWidget {
  const ConfiguracionView({super.key});

  @override
  State<ConfiguracionView> createState() => _ConfiguracionViewState();
}

class _ConfiguracionViewState extends State<ConfiguracionView> {
  // Servicio de autenticacion.
  final AuthService _authService = AuthService();

  // Variables de estado.
  bool _cargando = true;
  bool _sesionIniciada = false;

  @override
  void initState() {
    super.initState();

    // Verificar si existe un token almacenado.
    _verificarSesion();
  }

  // Comprobar si existe una sesion registrada.
  Future<void> _verificarSesion() async {
    try {
      final bool tieneToken = await _authService.tieneToken();

      if (!mounted) {
        return;
      }

      setState(() {
        _sesionIniciada = tieneToken;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _sesionIniciada = false;
        _cargando = false;
      });
    }
  }

  // Obtener el tema seleccionado globalmente.
  ThemeMode _obtenerTemaActual() {
    return VitaSacraApp.of(context)?.temaActual ?? ThemeMode.system;
  }

  // Cambiar la apariencia de toda la aplicacion.
  void _cambiarTema(ThemeMode tema) {
    // Obtener el controlador global.
    final VitaSacraAppState? aplicacion = VitaSacraApp.of(context);

    if (aplicacion == null) {
      return;
    }

    // Actualizar la apariencia global.
    aplicacion.cambiarTema(tema);
  }

  // Mostrar informacion sobre la cuenta.
  void _mostrarInformacionCuenta() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Informacion de la cuenta'),
          content: Text(
            _sesionIniciada
                ? 'Se encontro una sesion almacenada. '
                      'Puedes consultar tus datos personales '
                      'desde la pantalla Mi perfil. '
                      'La edicion de datos se integrara '
                      'con el backend.'
                : 'Inicia sesion para consultar '
                      'la informacion de tu cuenta.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  // Mostrar informacion sobre privacidad.
  void _mostrarPrivacidad() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Privacidad y proteccion de datos'),
          content: const Text(
            'Vita Sacra utiliza mecanismos de '
            'autenticacion para acceder a las '
            'funciones personales.\n\n'
            'La consulta del aviso de privacidad, '
            'las solicitudes sobre datos personales '
            'y las preferencias de tratamiento '
            'se integraran cuando esten disponibles '
            'los documentos y endpoints oficiales.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  // Mostrar informacion sobre seguridad.
  void _mostrarSeguridad() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Seguridad de la cuenta'),
          content: const Text(
            'Las operaciones de cambio de contrasena '
            'y administracion de sesiones '
            'se conectaran cuando FastAPI disponga '
            'de los endpoints correspondientes.\n\n'
            'Esta pantalla no muestra ni almacena '
            'la contrasena del usuario.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Entendido'),
            ),
          ],
        );
      },
    );
  }

  // Construir una opcion de configuracion.
  Widget _crearOpcion({
    required IconData icono,
    required String titulo,
    required String descripcion,
    required VoidCallback onTap,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: Icon(icono, color: colores.primary),
        title: Text(
          titulo,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(descripcion, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // Construir una opcion para seleccionar el tema.
  Widget _crearOpcionTema({
    required ThemeMode valor,
    required String titulo,
    required IconData icono,
    required ThemeMode temaActual,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Comprobar si esta opcion esta seleccionada.
    final bool seleccionado = temaActual == valor;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          _cambiarTema(valor);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            color: seleccionado ? colores.primary : colores.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: seleccionado ? colores.primary : colores.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icono,
                size: 22,
                color: seleccionado ? colores.onPrimary : colores.onSurface,
              ),

              const SizedBox(height: 7),

              Text(
                titulo,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: seleccionado ? colores.onPrimary : colores.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Construir el apartado de apariencia.
  Widget _construirApariencia() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    // Consultar la preferencia global actual.
    final ThemeMode temaActual = _obtenerTemaActual();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado de apariencia.
          Row(
            children: [
              Icon(Icons.palette_outlined, color: colores.primary),

              const SizedBox(width: 10),

              const Text(
                'Tema de la aplicacion',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Opciones de apariencia.
          Row(
            children: [
              _crearOpcionTema(
                valor: ThemeMode.light,
                titulo: 'Claro',
                icono: Icons.light_mode_outlined,
                temaActual: temaActual,
              ),

              const SizedBox(width: 8),

              _crearOpcionTema(
                valor: ThemeMode.dark,
                titulo: 'Oscuro',
                icono: Icons.dark_mode_outlined,
                temaActual: temaActual,
              ),

              const SizedBox(width: 8),

              _crearOpcionTema(
                valor: ThemeMode.system,
                titulo: 'Sistema',
                icono: Icons.brightness_auto_outlined,
                temaActual: temaActual,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Informar sobre el alcance de la preferencia.
          Text(
            'La apariencia seleccionada se aplica '
            'a toda la aplicacion. La preferencia '
            'se restablece al reiniciar Vita Sacra.',
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // Construir el apartado informativo.
  Widget _construirAcercaDe() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vita Sacra',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colores.onPrimaryContainer,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Version 1.0.0 - Arca',
            style: TextStyle(fontSize: 13, color: colores.onPrimaryContainer),
          ),

          const SizedBox(height: 10),

          Text(
            'Plataforma de informacion '
            'y divulgacion medica.',
            style: TextStyle(fontSize: 13, color: colores.onPrimaryContainer),
          ),

          const SizedBox(height: 10),

          Text(
            'El contenido es informativo y no '
            'sustituye la valoracion de '
            'un profesional de la salud.',
            style: TextStyle(fontSize: 12, color: colores.onPrimaryContainer),
          ),
        ],
      ),
    );
  }

  // Construir el contenido de configuracion.
  Widget _construirContenido() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Encabezado de la pantalla.
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colores.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.settings_outlined,
                size: 30,
                color: colores.onPrimaryContainer,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mis preferencias',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: colores.primary,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    'Personaliza tu experiencia '
                    'en Vita Sacra.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colores.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        // Seccion de apariencia.
        Text(
          'Apariencia',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),

        const SizedBox(height: 12),

        _construirApariencia(),

        const SizedBox(height: 28),

        // Seccion de cuenta y seguridad.
        Text(
          'Cuenta y seguridad',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),

        const SizedBox(height: 12),

        // Opcion para consultar la cuenta.
        _crearOpcion(
          icono: Icons.person_outline,
          titulo: 'Informacion de mi cuenta',
          descripcion: 'Datos personales y perfil.',
          onTap: _mostrarInformacionCuenta,
        ),

        // Opcion de privacidad.
        _crearOpcion(
          icono: Icons.shield_outlined,
          titulo: 'Privacidad y proteccion de datos',
          descripcion: 'Informacion sobre privacidad.',
          onTap: _mostrarPrivacidad,
        ),

        // Opcion de seguridad.
        _crearOpcion(
          icono: Icons.lock_outline,
          titulo: 'Seguridad de la cuenta',
          descripcion: 'Contrasena y acceso a la cuenta.',
          onTap: _mostrarSeguridad,
        ),

        const SizedBox(height: 28),

        // Seccion de informacion de la aplicacion.
        Text(
          'Acerca de',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),

        const SizedBox(height: 12),

        _construirAcercaDe(),

        const SizedBox(height: 24),
      ],
    );
  }

  @override
  void dispose() {
    // Liberar el servicio de autenticacion.
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior de configuracion.
      appBar: AppBar(title: const Text('Configuracion'), centerTitle: true),

      // Contenido principal.
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _construirContenido(),
      ),
    );
  }
}
