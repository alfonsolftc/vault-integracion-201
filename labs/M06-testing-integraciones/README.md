# M06 — Testing de integraciones

[← Página anterior](../M05-integracion-aplicaciones/04-lab-credencial-de-postgres.md) · [Siguiente página →](00-disenar-pruebas.md)

Aquí está el motivo del curso: diseñar la prueba de una aplicación que habla con Vault y saber qué síntoma corresponde a cada fallo. El caso feliz ya lo tienes en el módulo 5; esta página no lo da por hecho y lo reconstruye.

## Qué aprenderás

- Separar autenticación, autorización, dato y disponibilidad.
- Provocar los fallos que pidió el temario y anotar el HTTP que ves.
- No dar por rota «la integración» cuando lo que caducó fue el token.
- Ejecutar un checklist de cuatro afirmaciones y leer el cuerpo de la respuesta, no solo el HTTP.

## Teoría

| Caso | Dónde se rompe | Qué no debes concluir |
|------|----------------|------------------------|
| Token caducado | La credencial de sesión | Que el secreto esté mal |
| Permiso insuficiente | La policy | Que Vault esté caído |
| Secreto inexistente | El camino o la versión | Que el login haya fallado |
| Rotación mal comprobada | Qué versión afirma el test | Que Vault haya perdido el dato |
| Cambio en caliente | La app lee de nuevo, o no | Que haya que reiniciar Vault |
| Vault inalcanzable | La red o el proceso | Un 403 |

Una prueba sin resultado esperado escrito antes de lanzarla no distingue estos casos.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [Diseñar las pruebas](00-disenar-pruebas.md) | La ficha de cada caso |
| 01 | [Escenarios de fallo](01-lab-escenarios-de-fallo.md) | Los provocas y miras la salida |
| 02 | [Checklist ejecutable](02-lab-checklist.md) | Cuatro PASS en una sola orden |
| 03 | [Contrato de la respuesta](03-lab-contrato-de-la-respuesta.md) | 404 con metadata, y un 200 leído en el campo equivocado |

→ Empieza por **[00 — Diseñar las pruebas](00-disenar-pruebas.md)**.
