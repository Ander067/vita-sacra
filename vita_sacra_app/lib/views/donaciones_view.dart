import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

// Pantalla para realizar aportaciones voluntarias.
class DonacionesView extends StatefulWidget {
  const DonacionesView({super.key});

  @override
  State<DonacionesView> createState() => _DonacionesViewState();
}

class _DonacionesViewState extends State<DonacionesView> {
  // Servicios de comunicacion y autenticacion.
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();

  // Clave para validar el formulario.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Controlador de cantidades personalizadas.
  final TextEditingController _cantidadController = TextEditingController();

  // Cantidades sugeridas en pesos mexicanos.
  final List<int> _cantidadesSugeridas = [25, 50, 100, 200];

  // Cantidad seleccionada inicialmente.
  double? _cantidadSeleccionada = 50;

  // Indicar si el usuario escribe una cantidad.
  bool _cantidadPersonalizada = false;

  // Limites establecidos por FastAPI.
  static const double _cantidadMinima = 10;
  static const double _cantidadMaxima = 10000;

  // Configuracion publica de PayPal.
  bool _consultandoConfiguracion = true;
  bool _paypalConfigurado = false;
  String _modoPayPal = 'sandbox';

  // Estado de la operacion.
  bool _procesando = false;
  String? _error;

  // Datos de la orden creada.
  String? _idOrden;
  String? _urlAprobacion;
  String? _estatusOrden;
  String? _estatusLocal;
  bool _recuperandoOrden = false;
  double? _montoOrden;

  // Control de solicitudes de configuracion.
  int _numeroSolicitud = 0;

  @override
  void initState() {
    super.initState();

    // Consultar la disponibilidad del proveedor.
    _consultarConfiguracion();
    _recuperarOrdenPendiente();
  }

  // Consultar la configuracion publica de PayPal.
  Future<void> _consultarConfiguracion() async {
    if (!mounted) {
      return;
    }

    final int solicitud = ++_numeroSolicitud;

    setState(() {
      _consultandoConfiguracion = true;
      _error = null;
    });

    try {
      // Este endpoint no requiere autenticacion.
      final dynamic respuesta = await _apiService.get('/pagos/configuracion');

      if (respuesta is! Map) {
        throw const ApiException('La configuracion de PayPal no es valida.');
      }

      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _paypalConfigurado = respuesta['configurado'] == true;
        _modoPayPal = (respuesta['modo'] ?? 'sandbox').toString();
        _consultandoConfiguracion = false;
      });
    } on ApiException catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _paypalConfigurado = false;
        _error = error.mensaje;
        _consultandoConfiguracion = false;
      });
    } catch (error) {
      if (!mounted || solicitud != _numeroSolicitud) {
        return;
      }

      setState(() {
        _paypalConfigurado = false;
        _error = 'No fue posible consultar la configuracion de PayPal.';
        _consultandoConfiguracion = false;
      });
    }
  }

  // Recuperar una aportacion pendiente desde los pagos del usuario.
  Future<void> _recuperarOrdenPendiente() async {
    if (!mounted || _idOrden != null || _recuperandoOrden) {
      return;
    }

    setState(() {
      _recuperandoOrden = true;
    });

    try {
      final String? token = await _authService.obtenerToken();
      if (token == null || token.trim().isEmpty) {
        return;
      }

      final dynamic respuesta = await _apiService.get(
        '/pagos/mis-pagos',
        token: token,
      );

      if (respuesta is! List) {
        throw const FormatException('El historial de pagos no es valido.');
      }

      // El endpoint devuelve los pagos ordenados del mas reciente al mas antiguo.
      for (final dynamic elemento in respuesta) {
        if (elemento is! Map) {
          continue;
        }

        final String tipo = (elemento['tipo'] ?? '').toString();
        final String estatus = (elemento['estatus'] ?? '').toString();
        final String orden = (elemento['paypal_order_id'] ?? '').toString();

        if (tipo != 'aportacion' ||
            (estatus != 'creado' && estatus != 'aprobado') ||
            orden.isEmpty) {
          continue;
        }

        final double? monto = double.tryParse(
          (elemento['monto'] ?? '').toString(),
        );

        if (!mounted || _idOrden != null) {
          return;
        }

        setState(() {
          _idOrden = orden;
          _estatusLocal = estatus;
          // El historial local no confirma el estado actual de PayPal.
          _estatusOrden = null;
          _montoOrden = monto;
          // El historial no devuelve la URL de aprobacion de PayPal.
          _urlAprobacion = null;
        });
        break;
      }
    } catch (error) {
      // Un fallo del historial no impide consultar la configuracion publica.
    } finally {
      if (mounted) {
        setState(() {
          _recuperandoOrden = false;
        });
      }
    }
  }

  // Sincronizar una captura ya completada en PayPal.
  Future<void> _sincronizarOrden() async {
    final String? idOrden = _idOrden;
    if (!mounted || _procesando || idOrden == null) {
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final String? token = await _obtenerToken();
      if (token == null || !mounted) {
        return;
      }

      final dynamic respuesta = await _apiService.post(
        '/pagos/orden/${Uri.encodeComponent(idOrden)}/sincronizar',
        datos: <String, dynamic>{},
        token: token,
      );

      if (respuesta is! Map) {
        throw const ApiException(
          'La respuesta de sincronizacion no es valida.',
        );
      }

      if (!mounted || idOrden != _idOrden) {
        return;
      }

      if (respuesta['estatus'] == 'completado') {
        setState(() {
          _estatusLocal = 'completado';
          _estatusOrden = 'COMPLETED';
        });
        _mostrarMensaje('La aportacion se sincronizo correctamente.');
      } else {
        _mostrarMensaje('La aportacion aun no esta confirmada.');
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.mensaje;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'No fue posible sincronizar la orden.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // Obtener la cantidad actual.
  double? _obtenerCantidad() {
    if (!_cantidadPersonalizada) {
      return _cantidadSeleccionada;
    }

    final String texto = _cantidadController.text.trim().replaceAll(',', '.');

    return double.tryParse(texto);
  }

  // Comprobar que el importe tenga dos decimales como maximo.
  bool _tieneDecimalesValidos(double cantidad) {
    final double centavos = cantidad * 100;

    return (centavos - centavos.round()).abs() < 0.000001;
  }

  // Validar una cantidad personalizada.
  String? _validarCantidad(String? valor) {
    if (!_cantidadPersonalizada) {
      return null;
    }

    final String texto = valor?.trim() ?? '';

    if (texto.isEmpty) {
      return 'Escribe una cantidad.';
    }

    final double? cantidad = _obtenerCantidad();

    if (cantidad == null || !cantidad.isFinite) {
      return 'Escribe una cantidad numerica valida.';
    }

    if (cantidad < _cantidadMinima) {
      return 'La cantidad minima es de '
          '\$${_cantidadMinima.toStringAsFixed(2)} MXN.';
    }

    if (cantidad > _cantidadMaxima) {
      return 'La cantidad maxima es de '
          '\$${_cantidadMaxima.toStringAsFixed(2)} MXN.';
    }

    if (!_tieneDecimalesValidos(cantidad)) {
      return 'Utiliza como maximo dos decimales.';
    }

    return null;
  }

  // Seleccionar una cantidad sugerida.
  void _seleccionarCantidad(int cantidad) {
    if (_procesando || _idOrden != null) {
      return;
    }

    setState(() {
      _cantidadPersonalizada = false;
      _cantidadSeleccionada = cantidad.toDouble();
      _cantidadController.clear();
      _error = null;
    });
  }

  // Activar el ingreso de una cantidad personalizada.
  void _activarCantidadPersonalizada() {
    if (_procesando || _idOrden != null) {
      return;
    }

    setState(() {
      _cantidadPersonalizada = true;
      _cantidadSeleccionada = null;
      _error = null;
    });
  }

  // Formatear cantidades monetarias.
  String _formatearCantidad(double cantidad) {
    return '\$${cantidad.toStringAsFixed(2)} MXN';
  }

  // Mostrar mensajes informativos.
  void _mostrarMensaje(String mensaje) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  // Obtener el token requerido para las operaciones de pago.
  Future<String?> _obtenerToken() async {
    final String? token = await _authService.obtenerToken();

    if (token == null || token.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _error = 'Debes iniciar sesion para realizar una aportacion.';
        });
      }

      return null;
    }

    return token;
  }

  // Validar y confirmar la intencion de donar.
  Future<void> _continuarDonacion() async {
    if (_procesando || _idOrden != null) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final double? cantidad = _obtenerCantidad();

    if (cantidad == null ||
        !cantidad.isFinite ||
        cantidad < _cantidadMinima ||
        cantidad > _cantidadMaxima ||
        !_tieneDecimalesValidos(cantidad)) {
      _mostrarMensaje('Selecciona una cantidad valida.');
      return;
    }

    if (!_paypalConfigurado) {
      _mostrarMensaje('PayPal no se encuentra configurado en el servidor.');
      return;
    }

    // Mostrar el resumen antes de crear una orden.
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        final ColorScheme colores = Theme.of(context).colorScheme;

        return AlertDialog(
          title: const Text('Resumen de la aportacion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cantidad seleccionada:',
                style: TextStyle(color: colores.onSurfaceVariant),
              ),

              const SizedBox(height: 8),

              Text(
                _formatearCantidad(cantidad),
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  color: colores.primary,
                ),
              ),

              const SizedBox(height: 18),

              Text(
                _modoPayPal == 'live'
                    ? 'Se creara una orden real de PayPal. '
                          'El cargo requerira tu aprobacion.'
                    : 'PayPal se encuentra en modo sandbox. '
                          'La operacion sera de prueba.',
              ),

              const SizedBox(height: 10),

              const Text(
                'Crear la orden no significa que '
                'la aportacion haya sido pagada.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Crear orden'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmar != true) {
      return;
    }

    await _crearOrden(cantidad);
  }

  // Crear una orden de aportacion en PayPal.
  Future<void> _crearOrden(double cantidad) async {
    if (!mounted || _procesando || _idOrden != null) {
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final String? token = await _obtenerToken();

      if (token == null || !mounted) {
        return;
      }

      // El backend espera exclusivamente el campo monto.
      final dynamic respuesta = await _apiService.post(
        '/pagos/aportaciones/crear',
        datos: {'monto': double.parse(cantidad.toStringAsFixed(2))},
        token: token,
      );

      if (respuesta is! Map) {
        throw const ApiException('La respuesta de la orden no es valida.');
      }

      final String idOrden = (respuesta['paypal_order_id'] ?? '').toString();

      final String url = (respuesta['url_aprobacion'] ?? '').toString();

      final Uri? enlace = Uri.tryParse(url);

      if (idOrden.isEmpty ||
          enlace == null ||
          enlace.scheme != 'https' ||
          enlace.host.isEmpty ||
          enlace.userInfo.isNotEmpty) {
        throw const ApiException('PayPal no devolvio una orden valida.');
      }

      if (!mounted) {
        return;
      }

      // Conservar la orden para evitar crear otra por accidente.
      setState(() {
        _idOrden = idOrden;
        _urlAprobacion = url;
        _estatusOrden = 'CREATED';
        _estatusLocal = 'creado';
        _montoOrden = cantidad;
      });

      // Facilitar el acceso al enlace de aprobacion.
      await _copiarEnlaceAprobacion();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.codigoEstado == 401
            ? 'Tu sesion ha expirado. Inicia sesion nuevamente.'
            : error.mensaje;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No fue posible crear la orden de PayPal.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // Copiar el enlace de aprobacion proporcionado por PayPal.
  Future<void> _copiarEnlaceAprobacion() async {
    final String? url = _urlAprobacion;

    if (url == null || url.isEmpty) {
      return;
    }

    try {
      await Clipboard.setData(ClipboardData(text: url));

      if (!mounted) {
        return;
      }

      _mostrarMensaje(
        'Enlace de PayPal copiado. '
        'Abrelo en tu navegador para aprobar la orden.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _mostrarMensaje('No fue posible copiar el enlace de PayPal.');
    }
  }

  // Consultar el estado de la orden en PayPal.
  Future<void> _consultarOrden() async {
    final String? idOrden = _idOrden;

    if (!mounted || _procesando || idOrden == null) {
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final String? token = await _obtenerToken();

      if (token == null || !mounted) {
        return;
      }

      final dynamic respuesta = await _apiService.get(
        '/pagos/orden/${Uri.encodeComponent(idOrden)}',
        token: token,
      );

      if (respuesta is! Map) {
        throw const ApiException(
          'No fue posible interpretar el estado de la orden.',
        );
      }

      if (!mounted) {
        return;
      }

      final String estatusPayPal = (respuesta['estatus_paypal'] ?? '')
          .toString();

      final String estatusLocal = (respuesta['estatus_local'] ?? '').toString();

      setState(() {
        _estatusOrden = estatusLocal == 'completado'
            ? 'COMPLETED'
            : estatusPayPal;
        _estatusLocal = estatusLocal;
      });

      if (estatusLocal == 'completado') {
        _mostrarMensaje('La aportacion ya figura como completada.');
      } else if (estatusPayPal == 'APPROVED') {
        _mostrarMensaje('Orden aprobada. Ya puedes confirmar el pago.');
      } else {
        _mostrarMensaje('Estado actual de PayPal: $estatusPayPal');
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.mensaje;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = 'No fue posible consultar la orden.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // Capturar una orden aprobada por el usuario.
  Future<void> _capturarOrden() async {
    final String? idOrden = _idOrden;

    if (!mounted ||
        _procesando ||
        idOrden == null ||
        _estatusOrden != 'APPROVED' ||
        _montoOrden == null) {
      return;
    }

    // Solicitar confirmacion antes de capturar.
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirmar aportacion'),
          content: Text(
            'PayPal indica que aprobaste la orden.\n\n'
            '¿Deseas confirmar la captura de '
            '${_formatearCantidad(_montoOrden ?? 0)}?\n\n'
            'Esta accion puede completar el cargo.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancelar'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('Confirmar pago'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmar != true) {
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    try {
      final String? token = await _obtenerToken();

      if (token == null || !mounted) {
        return;
      }

      // La captura se realiza exclusivamente en FastAPI.
      final dynamic respuesta = await _apiService.post(
        '/pagos/orden/${Uri.encodeComponent(idOrden)}/capturar',
        datos: <String, dynamic>{},
        token: token,
      );

      if (respuesta is! Map) {
        throw const ApiException('La respuesta de captura no es valida.');
      }

      if (!mounted || idOrden != _idOrden) {
        return;
      }

      // El backend devuelve estatus local cuando la captura no concluye.
      final String estatusLocal =
          (respuesta['estatus'] ?? respuesta['estatus_local'] ?? '').toString();
      final String estatusPayPal = (respuesta['estatus_paypal'] ?? '')
          .toString();

      final String mensaje = (respuesta['mensaje'] ?? '').toString();

      // Solo el estado completado confirma la aportacion.
      if (estatusLocal == 'completado') {
        setState(() {
          _estatusOrden = 'COMPLETED';
          _estatusLocal = 'completado';
        });

        _mostrarMensaje(
          mensaje.isNotEmpty ? mensaje : 'Aportacion confirmada correctamente.',
        );
      } else {
        setState(() {
          _estatusLocal = estatusLocal.isNotEmpty
              ? estatusLocal
              : _estatusLocal;
          if (estatusPayPal.isNotEmpty) {
            _estatusOrden = estatusPayPal;
          }
        });

        _mostrarMensaje(
          mensaje.isNotEmpty ? mensaje : 'La captura aun no se ha completado.',
        );
      }
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.mensaje;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error =
            'No fue posible confirmar la aportacion. '
            'Consulta el estado de la orden antes de reintentar.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _procesando = false;
        });
      }
    }
  }

  // Construir un beneficio del proyecto.
  Widget _crearBeneficio({
    required IconData icono,
    required String descripcion,
  }) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: colores.primary),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              descripcion,
              style: TextStyle(fontSize: 13, color: colores.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  // Construir la informacion sobre las aportaciones.
  Widget _construirInformacion() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿Para que son las aportaciones?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colores.onPrimaryContainer,
            ),
          ),

          const SizedBox(height: 16),

          _crearBeneficio(
            icono: Icons.computer_outlined,
            descripcion: 'Apoyar el mantenimiento de la plataforma.',
          ),

          _crearBeneficio(
            icono: Icons.auto_awesome_outlined,
            descripcion: 'Contribuir al desarrollo de nuevas funcionalidades.',
          ),

          _crearBeneficio(
            icono: Icons.accessibility_new_outlined,
            descripcion:
                'Impulsar mejoras de accesibilidad '
                'y presentacion de contenido.',
          ),
        ],
      ),
    );
  }

  // Construir una cantidad sugerida.
  Widget _crearCantidad(int cantidad) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final bool seleccionada =
        !_cantidadPersonalizada && _cantidadSeleccionada == cantidad.toDouble();

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        _seleccionarCantidad(cantidad);
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
        decoration: BoxDecoration(
          color: seleccionada ? colores.primary : colores.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: seleccionada ? colores.primary : colores.outlineVariant,
          ),
        ),
        child: Text(
          '\$$cantidad',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: seleccionada ? colores.onPrimary : colores.onSurface,
          ),
        ),
      ),
    );
  }

  // Construir las opciones de cantidad.
  Widget _construirCantidades() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selecciona una cantidad',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: colores.onSurface,
          ),
        ),

        const SizedBox(height: 14),

        // Mostrar cantidades sugeridas.
        Row(
          children: _cantidadesSugeridas.map((cantidad) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 7),
                child: _crearCantidad(cantidad),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 14),

        // Opcion de cantidad personalizada.
        OutlinedButton.icon(
          onPressed: _idOrden == null && !_procesando
              ? _activarCantidadPersonalizada
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ingresar otra cantidad'),
        ),

        // Campo para cantidades personalizadas.
        if (_cantidadPersonalizada) ...[
          const SizedBox(height: 14),

          TextFormField(
            controller: _cantidadController,
            enabled: !_procesando && _idOrden == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              LengthLimitingTextInputFormatter(12),
            ],
            decoration: const InputDecoration(
              labelText: 'Cantidad personalizada',
              hintText: 'Ejemplo: 150.00',
              prefixIcon: Icon(Icons.attach_money),
              suffixText: 'MXN',
              border: OutlineInputBorder(),
            ),
            validator: _validarCantidad,
            onChanged: (_) {
              setState(() {});
            },
          ),

          const SizedBox(height: 8),

          Text(
            'Importe permitido: '
            '\$10.00 a \$10,000.00 MXN.',
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  // Construir el resumen de la cantidad.
  Widget _construirResumen() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    final double? cantidad = _montoOrden ?? _obtenerCantidad();

    final String cantidadTexto =
        cantidad != null && cantidad.isFinite && cantidad >= 0
        ? _formatearCantidad(cantidad)
        : 'Sin cantidad valida';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Cantidad seleccionada',
              style: TextStyle(fontSize: 14, color: colores.onSurfaceVariant),
            ),
          ),

          const SizedBox(width: 10),

          Text(
            cantidadTexto,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colores.primary,
            ),
          ),
        ],
      ),
    );
  }

  // Construir el estado de la integracion.
  Widget _construirEstadoPayPal() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    if (_consultandoConfiguracion) {
      return const Center(child: CircularProgressIndicator());
    }

    final String descripcion;

    if (_paypalConfigurado) {
      descripcion = _modoPayPal == 'live'
          ? 'PayPal configurado en modo real.'
          : 'PayPal configurado en modo de pruebas (sandbox).';
    } else {
      descripcion =
          'PayPal no esta configurado en el backend. '
          'No es posible crear aportaciones.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colores.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            color: colores.onPrimaryContainer,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              descripcion,
              style: TextStyle(fontSize: 13, color: colores.onPrimaryContainer),
            ),
          ),

          IconButton(
            tooltip: 'Actualizar configuracion',
            onPressed: _consultandoConfiguracion
                ? null
                : _consultarConfiguracion,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  // Construir las acciones de una orden creada.
  Widget _construirOrden() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    if (_idOrden == null) {
      return const SizedBox.shrink();
    }

    // Solo el estado confirmado por el backend acredita la aportacion.
    final bool completada = _estatusLocal == 'completado';
    final bool aprobada = _estatusOrden == 'APPROVED';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colores.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Orden de PayPal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colores.onSurface,
            ),
          ),

          const SizedBox(height: 10),

          SelectableText(
            'Identificador: $_idOrden',
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),

          const SizedBox(height: 8),

          Text(
            'Estado: ${_estatusOrden ?? "Desconocido"}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colores.onSurface,
            ),
          ),

          const SizedBox(height: 14),

          if (!completada) ...[
            const Text(
              '1. Copia el enlace de PayPal y abrelo '
              'en tu navegador.\n'
              '2. Aprueba la orden en PayPal.\n'
              '3. Regresa a Vita Sacra y consulta '
              'el estado.\n'
              '4. Confirma el pago cuando la orden '
              'aparezca aprobada.',
            ),

            const SizedBox(height: 16),

            if (_urlAprobacion != null)
              OutlinedButton.icon(
                onPressed: _procesando ? null : _copiarEnlaceAprobacion,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copiar enlace de PayPal'),
              )
            else
              const Text(
                'Esta orden se recupero del historial. '
                'La API no devuelve nuevamente su enlace de aprobacion. '
                'Consulta su estado antes de continuar.',
              ),

            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _procesando ? null : _consultarOrden,
              icon: const Icon(Icons.refresh),
              label: const Text('Consultar estado de la orden'),
            ),

            const SizedBox(height: 10),

            OutlinedButton.icon(
              onPressed: _procesando ? null : _sincronizarOrden,
              icon: const Icon(Icons.sync_outlined),
              label: const Text('Sincronizar pago completado'),
            ),

            if (aprobada) ...[
              const SizedBox(height: 10),

              FilledButton.icon(
                onPressed: _procesando ? null : _capturarOrden,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Confirmar pago'),
              ),
            ],
          ] else
            const Text(
              'La aportacion ha sido confirmada '
              'por el backend.',
            ),
        ],
      ),
    );
  }

  // Construir la advertencia de seguridad.
  Widget _construirSeguridad() {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: 21, color: colores.primary),

        const SizedBox(width: 10),

        Expanded(
          child: Text(
            'Los pagos se gestionan mediante PayPal '
            'y el backend de Vita Sacra. '
            'Esta pantalla no solicita datos bancarios. '
            'Crear una orden no confirma un cargo; '
            'la aportacion se confirma cuando '
            'la captura finaliza correctamente.',
            style: TextStyle(fontSize: 12, color: colores.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Invalidar consultas pendientes.
    _numeroSolicitud++;

    // Liberar los recursos utilizados.
    _cantidadController.dispose();
    _apiService.cerrar();
    _authService.cerrarServicio();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colores.surface,

      // Barra superior del modulo.
      appBar: AppBar(title: const Text('Donaciones'), centerTitle: true),

      // Contenido principal.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Encabezado del modulo.
                Center(
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: colores.primaryContainer,
                        child: Icon(
                          Icons.volunteer_activism_outlined,
                          size: 42,
                          color: colores.onPrimaryContainer,
                        ),
                      ),

                      const SizedBox(height: 14),

                      Text(
                        'Apoya a Vita Sacra',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colores.primary,
                        ),
                      ),

                      const SizedBox(height: 10),

                      Text(
                        'Contribuye voluntariamente '
                        'al desarrollo y mantenimiento '
                        'de nuestra plataforma '
                        'de divulgacion medica.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: colores.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 26),

                // Informacion del proyecto.
                _construirInformacion(),

                const SizedBox(height: 22),

                // Estado de la integracion de PayPal.
                _construirEstadoPayPal(),

                const SizedBox(height: 26),

                // Seleccion de cantidades.
                _construirCantidades(),

                const SizedBox(height: 24),

                // Resumen del importe.
                _construirResumen(),

                const SizedBox(height: 20),

                // Mostrar errores de la operacion.
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colores.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colores.onErrorContainer),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],

                // Crear una orden solamente si no existe otra activa.
                if (_idOrden == null)
                  SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed:
                          _procesando ||
                              _recuperandoOrden ||
                              _consultandoConfiguracion ||
                              !_paypalConfigurado
                          ? null
                          : _continuarDonacion,
                      icon: _procesando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.favorite_outline),
                      label: Text(_procesando ? 'Procesando...' : 'Continuar'),
                    ),
                  ),

                // Mostrar los datos de la orden creada.
                if (_idOrden != null) _construirOrden(),

                const SizedBox(height: 20),

                // Advertencia sobre pagos.
                _construirSeguridad(),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
