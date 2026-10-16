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
  - [Laboratorio: la batería](labs/M07-integracion-avanzada/05-lab-bateria.md)

## Antes de empezar

| Requisito | Dónde |
|-----------|--------|
| Navegador y terminal del Codespace, o Docker | [infra/README.md](infra/README.md) |
| Servidor limpio de laboratorio | `bash infra/reiniciar-vault.sh` y después `source infra/entorno.sh` |

Cada demostración y cada laboratorio se hacen **solos**: empiezan reiniciando Vault. No hace falta haber terminado la página anterior.

## Empieza aquí

→ **[M01 — Introducción y arquitectura](labs/M01-introduccion-vault/00-que-es-vault.md)**
