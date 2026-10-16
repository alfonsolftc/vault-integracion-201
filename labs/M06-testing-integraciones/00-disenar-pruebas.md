# Diseñar las pruebas

[← Página anterior](README.md) · [Siguiente página →](01-lab-escenarios-de-fallo.md)

Antes de romper nada, la ficha del caso dice qué preparas, qué haces y qué tiene que pasar. Esta página usa un servidor nuevo y una sola aplicación de prueba.

## Punto de partida

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
```

Servidor vacío. La aplicación de referencia hace login AppRole y lee `secret/data/pagos/api`. En el caso feliz imprime la clave y el HTTP es 200. Si el login falla, no llega a haber HTTP de lectura: el fallo es 400 en `/auth/approle/login` y la ficha se queda ahí.

## La ficha

Cada caso de abajo tiene las tres líneas que usarías en un checklist.

| Línea | Qué fija |
|-------|----------|
| Preparación | El estado de Vault antes de la acción: token, policy, versión o red |
| Acción | La llamada concreta. Una. Si hay dos lecturas, la ficha lo dice |
| Resultado | El HTTP y el texto del cuerpo que otra persona puede corregir sin ver tu pantalla |

## Los casos

### Token caducado

Preparación: token con TTL de 5 segundos y policy de lectura.

Acción: leer, esperar 6 segundos y leer otra vez con el mismo token.

Resultado: la segunda lectura no trae clave. El error es 403 `invalid token`.

### Permiso insuficiente

Preparación: token cuya policy no incluye `secret/data/pagos/api`. El secreto existe.

Acción: leer `secret/pagos/api`.

Resultado: 403 y `permission denied`. Con el token `root` la clave sigue.

### Secreto inexistente

Preparación: login válido y permiso de lectura sobre `secret/pagos/no-existe`.

Acción: leer ese camino. El login no se repite: ya había token.

Resultado: 404. El cuerpo no trae la clave.

### Rotación

Preparación: versión 2 escrita. La prueba pide `?version=1`.

Acción: leer con ese query.

Resultado: HTTP 200 y la clave antigua. Afirmar que «ya está la nueva» es el fallo de la prueba.

### Cambio en caliente

Preparación: la app lee el secreto en cada arranque.

Acción: una lectura, un `kv put`, otra lectura. Nadie reinicia Vault.

Resultado: la segunda lectura trae el valor nuevo.

### No disponible

Preparación: `docker pause` del contenedor. La memoria no se borra.

Acción: `curl` con `--max-time 3`.

Resultado: no hay HTTP 200 ni 403. Es timeout o conexión rechazada. Al quitar la pausa, el secreto sigue.

## Fuera de esta ficha

Instalar Vault, desellar el clúster de producción y probar un motor que esta aplicación no usa quedan fuera. Si el equipo nombra otro engine, se añade un caso con las mismas tres líneas.

## Qué queda visto

Cada fallo tiene su ficha. El [laboratorio](01-lab-escenarios-de-fallo.md) ejecuta esas fichas en un servidor limpio, un paso por acción.
