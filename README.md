# HashiCorp Vault: secretos, integración y testing

[Siguiente página →](labs/M01-introduccion-vault/README.md)

## De qué va este curso

Vault **ya está implantado** en la organización. Este curso va orientado a **pruebas de integración**: sin conocer la funcionalidad y la arquitectura, esas pruebas no son fiables.

No vas a instalar el clúster de producción. Vas a entender cómo una aplicación se autentica, pide un secreto y qué debe comprobar un test cuando el token caduca, faltan permisos, el secreto no existe o rota en caliente.

El laboratorio corre en el navegador (Codespace o Docker). En tu equipo no se instala nada. Detalle en [infra/README.md](infra/README.md).

## Temario

- **M01 — Introducción y arquitectura** — [qué problema resuelve Vault](labs/M01-introduccion-vault/00-que-es-vault.md) y [de qué piezas está hecho](labs/M01-introduccion-vault/01-arquitectura-vault.md)
  - [Laboratorio: primer secreto](labs/M01-introduccion-vault/02-lab-primer-secreto.md)
  - [Laboratorio: sellado y salud](labs/M01-introduccion-vault/03-lab-sellado.md)
  - [Laboratorio: dos motores](labs/M01-introduccion-vault/04-lab-dos-motores.md)
- **M02 — Secretos y API** — [CLI, API REST y el motor KV con versiones](labs/M02-secretos-y-api/00-cli-api-y-kv.md)
  - [Laboratorio: versiones y API](labs/M02-secretos-y-api/01-lab-versiones-y-api.md)
  - [Laboratorio: borrar una versión](labs/M02-secretos-y-api/02-lab-borrar-version.md)
  - [Laboratorio: listar y variables](labs/M02-secretos-y-api/03-lab-listar-y-variables.md)
- **M03 — Policies, tokens y seguridad** — [quién puede leer qué, y durante cuánto tiempo](labs/M03-policies-y-tokens/00-policies-tokens-auditoria.md)
  - [Laboratorio: permisos y TTL](labs/M03-policies-y-tokens/01-lab-permisos-y-ttl.md)
  - [Laboratorio: renovar el token](labs/M03-policies-y-tokens/02-lab-renovar-token.md)
  - [Laboratorio: dos perfiles](labs/M03-policies-y-tokens/03-lab-dos-perfiles.md)
- **M04 — Autenticación** — [UserPass para personas y AppRole para aplicaciones](labs/M04-autenticacion/00-userpass-y-approle.md)
  - [Laboratorio: AppRole](labs/M04-autenticacion/01-lab-approle.md)
  - [Laboratorio: UserPass](labs/M04-autenticacion/02-lab-userpass.md)
  - [Laboratorio: secret_id de un solo uso](labs/M04-autenticacion/03-lab-secret-id-un-uso.md)
- **M05 — Integración con aplicaciones** — [la app llama a la API, o un inyector y Vault Agent le dejan la clave en el entorno y arrancan el proceso sin tocarlo](labs/M05-integracion-aplicaciones/00-integrar-aplicacion.md)
  - [Laboratorio: consumo automático](labs/M05-integracion-aplicaciones/01-lab-consumo-automatico.md)
  - [Laboratorio: el job que falla cerrado](labs/M05-integracion-aplicaciones/02-lab-job-falla-cerrado.md)
  - [Laboratorio: Agent y el cambio en caliente](labs/M05-integracion-aplicaciones/03-lab-agent-en-caliente.md)
  - [Laboratorio: la app entra en Postgres](labs/M05-integracion-aplicaciones/04-lab-credencial-de-postgres.md)
- **M06 — Testing de integraciones** — [cómo diseñar la prueba y los fallos que tienes que provocar](labs/M06-testing-integraciones/00-disenar-pruebas.md)
  - [Laboratorio: escenarios de fallo](labs/M06-testing-integraciones/01-lab-escenarios-de-fallo.md)
  - [Laboratorio: checklist ejecutable](labs/M06-testing-integraciones/02-lab-checklist.md)
  - [Laboratorio: contrato de la respuesta](labs/M06-testing-integraciones/03-lab-contrato-de-la-respuesta.md)
- **M07 — Integración avanzada** — [el secreto no sale por el echo: Agent comprueba la huella del código, envoltorio, Transit y Vault como CA SSH](labs/M07-integracion-avanzada/00-secreto-sin-echo.md)
  - [Laboratorio: la huella del código](labs/M07-integracion-avanzada/01-lab-huella-del-codigo.md)
  - [Laboratorio: secret_id envuelto](labs/M07-integracion-avanzada/02-lab-secret-id-envuelto.md)
  - [Laboratorio: la app firma](labs/M07-integracion-avanzada/03-lab-firma-transit.md)
  - [Laboratorio: entrar por SSH](labs/M07-integracion-avanzada/04-lab-ssh-ca.md)
  - [Laboratorio: el certificado llega y se va](labs/M07-integracion-avanzada/05-lab-certificado-en-destino.md)
  - [Laboratorio: la batería](labs/M07-integracion-avanzada/06-lab-bateria.md)

## Antes de empezar

| Requisito | Dónde |
|-----------|--------|
| Navegador y terminal del Codespace, o Docker | [infra/README.md](infra/README.md) |
| Servidor limpio de laboratorio | `bash infra/reiniciar-vault.sh` y después `source infra/entorno.sh` |

Cada demostración y cada laboratorio se hacen **solos**: empiezan reiniciando Vault. No hace falta haber terminado la página anterior.

## Empieza aquí

→ **[M01 — Introducción y arquitectura](labs/M01-introduccion-vault/00-que-es-vault.md)**

## Dónde documentarse

El laboratorio usa la imagen `hashicorp/vault:1.18`. Estas páginas describen los mismos mecanismos, fuera del modo dev.

### Documentación

- [Documentación de Vault](https://developer.hashicorp.com/vault/docs) — índice oficial.
- [Qué es Vault](https://developer.hashicorp.com/vault/docs/about-vault/what-is-vault) — el problema y los casos de uso del módulo 1.
- [Arquitectura interna](https://developer.hashicorp.com/vault/docs/internals) — barrier, storage y el camino de una petición.
- [Sellado](https://developer.hashicorp.com/vault/docs/concepts/seal) — por qué un servidor sellado no entrega secretos.
- [KV versión 2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2) — versiones, borrado y metadatos del módulo 2.
- [CLI](https://developer.hashicorp.com/vault/docs/commands) y [API HTTP](https://developer.hashicorp.com/vault/api-docs) — los dos clientes que usa el curso.
- [Policies](https://developer.hashicorp.com/vault/docs/concepts/policies), [tokens](https://developer.hashicorp.com/vault/docs/concepts/tokens) y [auditoría](https://developer.hashicorp.com/vault/docs/audit) — el módulo 3.
- [AppRole](https://developer.hashicorp.com/vault/docs/auth/approle) y [UserPass](https://developer.hashicorp.com/vault/docs/auth/userpass) — aplicación y persona, módulo 4.
- [Vault Agent](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent), [plantillas](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent/template) y [proxy](https://developer.hashicorp.com/vault/docs/agent-and-proxy/agent/apiproxy) — el entrypoint, el render y el proxy de firma de los módulos 5 y 7.
- [Response wrapping](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping) — el envoltorio de un solo uso del `secret_id`.
- [Transit](https://developer.hashicorp.com/vault/docs/secrets/transit) — firmar sin exportar la clave privada.
- [Motor database](https://developer.hashicorp.com/vault/docs/secrets/databases) y [Postgres](https://developer.hashicorp.com/vault/docs/secrets/databases/postgresql) — el usuario que la app recibe al arrancar.
- [Certificados SSH firmados](https://developer.hashicorp.com/vault/docs/secrets/ssh/signed-ssh-certificates) — la CA con la que `ana` entra por el puerto 2222.
- [Notas de la 1.18.0](https://developer.hashicorp.com/vault/docs/v1.18.x/release-notes/1.18.0) — la versión del contenedor.

### Tutoriales

- [Biblioteca de tutoriales](https://developer.hashicorp.com/vault/tutorials) — recorridos guiados de HashiCorp, con su propio servidor.
- [Primeros pasos](https://developer.hashicorp.com/vault/tutorials/get-started) — dev server, primer secreto y policy, en la documentación.
- [KV con versiones](https://developer.hashicorp.com/vault/tutorials/secrets-management/versioned-kv) — el mismo motor del módulo 2, paso a paso.
- [AppRole](https://developer.hashicorp.com/vault/tutorials/auth-methods/approle) — `role_id`, `secret_id` y el login de una aplicación.
- [Introducción segura del secreto](https://developer.hashicorp.com/vault/tutorials/app-integration/secure-introduction) — response wrapping más allá del `secret_id` de este curso.
- [Credenciales de base de datos](https://developer.hashicorp.com/vault/tutorials/db-credentials/database-secrets) — el motor database con un usuario que caduca.

### Foros y código

- [Foro de Vault](https://discuss.hashicorp.com/c/vault/30) — preguntas de operación, auth methods y secret engines. El índice de toda la comunidad está en [discuss.hashicorp.com](https://discuss.hashicorp.com/).
- [Código de Vault](https://github.com/hashicorp/vault) — el servidor que corre la imagen del laboratorio.
- [Incidencias](https://github.com/hashicorp/vault/issues) — fallos y cambios en discusión.
- [CHANGELOG](https://github.com/hashicorp/vault/blob/main/CHANGELOG.md) — qué entró y qué salió en cada versión. El modo `key_type=dynamic` del motor SSH se quitó en la 1.13; este curso está en la 1.18.

### Para ampliar

- [Blog de HashiCorp](https://www.hashicorp.com/en/blog) — artículos de producto. El de secretos dinámicos está en [Why we need dynamic secrets](https://www.hashicorp.com/en/blog/why-we-need-dynamic-secrets).
- [Contraseñas SSH de un solo uso](https://developer.hashicorp.com/vault/docs/secrets/ssh/one-time-ssh-passwords) — el otro modo vivo del motor `ssh`, distinto del certificado del módulo 7.
- [vault-ssh-helper](https://github.com/hashicorp/vault-ssh-helper) — el programa que, en el servidor, comprueba esa contraseña de un solo uso contra Vault.
- [ssh-keygen](https://man.openbsd.org/ssh-keygen) — cómo OpenSSH lee el certificado que Vault firma (`-L` y el fichero `-cert.pub`).
- [Motor PKI](https://developer.hashicorp.com/vault/tutorials/pki/pki-engine) — certificados X.509. No es el motor `ssh/` de este curso.
