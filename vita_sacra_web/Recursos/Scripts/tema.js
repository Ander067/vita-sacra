(function () {
    'use strict';

    var claveTema = 'vita-sacra-tema';
    var botonTema = document.getElementById('cambiarTema');

    function obtenerTemaGuardado() {
        try {
            var tema = window.localStorage.getItem(claveTema);
            return tema === 'oscuro' || tema === 'claro' ? tema : null;
        } catch (error) {
            return null;
        }
    }

    function guardarTema(tema) {
        try {
            window.localStorage.setItem(claveTema, tema);
        } catch (error) {
            // Si el navegador bloquea el almacenamiento, el tema cambia
            // durante la página actual, aunque no persista al navegar.
        }
    }

    function aplicarTema(tema) {
        var oscuro = tema === 'oscuro';

        document.body.classList.toggle('tema-oscuro', oscuro);

        if (botonTema) {
            botonTema.setAttribute('aria-pressed', oscuro ? 'true' : 'false');
            botonTema.textContent = oscuro
                ? 'Usar tema claro'
                : 'Usar tema oscuro';
        }
    }

    aplicarTema(obtenerTemaGuardado() || 'claro');

    if (botonTema) {
        botonTema.addEventListener('click', function () {
            var siguienteTema = document.body.classList.contains('tema-oscuro')
                ? 'claro'
                : 'oscuro';

            aplicarTema(siguienteTema);
            guardarTema(siguienteTema);
        });
    }

    window.addEventListener('storage', function (evento) {
        if (evento.key === claveTema) {
            aplicarTema(evento.newValue === 'oscuro' ? 'oscuro' : 'claro');
        }
    });
}());