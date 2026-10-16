# M06 — Testing de integraciones

[← Página anterior](../M05-integracion-aplicaciones/04-lab-credencial-de-postgres.md) · [Siguiente página →](00-disenar-pruebas.md)

Aquí está el motivo del curso: diseñar la prueba de una aplicación que habla con Vault y saber qué síntoma corresponde a cada fallo. El caso feliz ya lo tienes en el módulo 5; esta página no lo da por hecho y lo reconstruye.

## Qué aprenderás

- Separar autenticación, autorización, dato y disponibilidad.
- Provocar los fallos que pidió el temario y anotar el HTTP que ves.
- Leer el síntoma en su sitio: un token caducado deja el secreto donde estaba.
- Ejecutar un checklist de cuatro afirmaciones y leer el cuerpo de la respuesta, no solo el HTTP.

## Teoría

La aplicación de referencia hace dos llamadas. Primero el login en `/auth/approle/login`. Después el GET de `secret/data/pagos/api`. Cada fallo corta en un sitio distinto de ese camino.

```text
login AppRole          GET del secreto
role_id + secret_id → token → policy → dato en KV → red hasta vault-dev
     |                  |        |          |              |
  400 de login     403 token   403 policy  404 o versión   timeout
```

### Autenticación

El login devuelve el token. Si el `secret_id` no vale, la respuesta es 400 y no llega a haber GET. Si el token ya existía y caducó, el GET responde 403 con `invalid token`. El secreto no se ha movido: lo que caducó es la credencial de sesión.

### Autorización

Un token vigente con una policy que no incluye `secret/data/pagos/api` también recibe 403, esta vez con `permission denied`. El login fue bien. Con el token `root` el mismo camino sigue devolviendo la clave.

### El dato

Con token y policy válidos, el cuerpo dice qué pasa con el valor.

| Qué afirmas | HTTP | Qué miras en el cuerpo |
|-------------|------|------------------------|
| El camino no existe | 404 | No hay `clave` |
| Pides la versión anterior | 200 | `clave` antigua y `version` 1 |
| La app lee otra vez tras un `kv put` | 200 | La clave nueva, sin reiniciar Vault |
| La versión vigente está borrada | 404 | `deletion_time` con contenido y `destroyed` false |
| La versión está destruida | 404 | `destroyed` true. `undelete` imprime Success y el cuerpo no cambia |
| El test lee el campo mal | 200 | `KeyError` en `data.clave`. El valor está en `data.data.clave` |

### Disponibilidad

`docker pause` congela `vault-dev` sin borrar la memoria. El `curl` con `--max-time 3` no recibe 200 ni 403: agota el tiempo. Al quitar la pausa, la clave sigue.

Una prueba escribe antes estos tres datos: qué preparas, qué haces y qué tiene que pasar. Sin ese resultado, un 403 puede ser el token, la policy o el servicio.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [Diseñar las pruebas](00-disenar-pruebas.md) | La ficha de cada caso, partida en preparación, acción y resultado |
| 01 | [Escenarios de fallo](01-lab-escenarios-de-fallo.md) | Cada fallo, en su propio paso |
| 02 | [Checklist ejecutable](02-lab-checklist.md) | Cuatro PASS en una sola orden |
| 03 | [Contrato de la respuesta](03-lab-contrato-de-la-respuesta.md) | 404 con metadata, y un 200 leído en el campo equivocado |

→ Empieza por **[00 — Diseñar las pruebas](00-disenar-pruebas.md)**.
