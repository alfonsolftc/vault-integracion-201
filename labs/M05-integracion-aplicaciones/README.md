# M05 — Integración con aplicaciones

[← Página anterior](../M04-autenticacion/03-lab-secret-id-un-uso.md) · [Siguiente página →](00-integrar-aplicacion.md)

El Departamento de Test no administra el clúster: comprueba que una aplicación consigue el secreto y lo usa. Este módulo deja esa aplicación por escrito. Hay tres formas de entregarle el secreto, y las tres se ven funcionar.

## Qué aprenderás

- Distinguir el servidor Vault de la máquina donde corre la aplicación.
- Una app que hace login AppRole, lee la clave y la usa.
- Qué es Vault Agent, qué dice cada bloque de `agent.hcl` y por qué el fichero lo lee la app.
- Un job de CI que sale con un código distinto si faltan credenciales o si el login es 400.
- Una app que entra en Postgres con un usuario que Vault crea en ese momento y que desaparece al revocar el lease.

## Teoría

Hay dos sitios. `vault-dev` es el servidor. La aplicación vive en otro: tu terminal, cuando ella llama a la API, o el contenedor `pagos`, cuando quien llama es Vault Agent. Meter Agent dentro de `vault-dev` mezcla los dos papeles. En este módulo Agent arranca en `pagos`.

```text
tu terminal                         contenedor pagos                 contenedor vault-dev
(app que llama a la API)            (máquina de la aplicación)       (servidor Vault)
        |                                    |                                |
        |  login AppRole y GET del secreto   |                                |
        +------------------------------------+------------------------------->|
        |                                    |  Vault Agent hace ese login    |
        |                                    +------------------------------->|
        |                                    |  escribe /tmp/clave.txt        |
        |                                    |  app.sh solo lee el fichero    |
```

Vault Agent es el binario `vault` con el subcomando `agent`. Es un proceso de la máquina de la aplicación (en Kubernetes, el contenedor de al lado en el mismo pod). Hace el login, renueva el token y escribe ficheros a partir de plantillas. La aplicación lee el fichero. No tiene token ni dirección de Vault.

`agent.hcl` es lo único que se le da a ese proceso:

| Bloque | Para qué está |
|--------|----------------|
| `pid_file` | Dónde escribe su número de proceso, para poder pararlo |
| `vault.address` | Dónde está el servidor, visto desde la máquina de la app. Aquí `http://vault-dev:8200`. Dentro de `pagos`, `127.0.0.1` es la propia app |
| `auto_auth` | El login AppRole. Lee `role_id` y `secret_id` de ficheros, porque Agent no hereda las variables de tu terminal |
| `remove_secret_id_file_after_reading` | Con `true`, borra el `secret_id` tras el login. En el laboratorio está en `false` para poder arrancar Agent otra vez con el mismo fichero |
| `template` | El GET del secreto y el fichero de destino. `with secret` lee; `.Data.data.clave` es el campo del KV v2 |

La tercera entrega usa el motor `database`. La app pide un usuario de Postgres, Vault lo crea con una contraseña de un solo uso y un lease, y la app entra con ese usuario. La contraseña de administrador no sale de Vault. El mismo motor tiene plugins para MySQL, Redis y otros; aquí Postgres basta para ver el usuario entrar y leer una fila.

## Páginas

| # | Página | Qué hay |
|---|--------|---------|
| 00 | [Integrar una aplicación](00-integrar-aplicacion.md) | La app que llama a la API y la app que lee el fichero de Agent |
| 01 | [Consumo automático](01-lab-consumo-automatico.md) | Los dos caminos, desde un servidor vacío |
| 02 | [El job que falla cerrado](02-lab-job-falla-cerrado.md) | El job de CI sale 2 sin credenciales y 1 si el login es 400 |
| 03 | [Agent y el cambio en caliente](03-lab-agent-en-caliente.md) | La app dice la clave nueva sin rearrancar Agent |
| 04 | [La app entra en Postgres](04-lab-credencial-de-postgres.md) | Cada arranque recibe un usuario distinto, y al revocar deja de existir |

→ Empieza por **[00 — Integrar una aplicación](00-integrar-aplicacion.md)**.
