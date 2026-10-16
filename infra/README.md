# Entorno de laboratorio

Vault en **modo dev**, accesible en el navegador del Codespace o en Docker local. No hace falta instalar Vault en el equipo.

| Dato | Valor |
|------|--------|
| Imagen | `hashicorp/vault:1.18` |
| Dirección | `http://127.0.0.1:8200` |
| Token de laboratorio | `root` |
| Motor de secretos ya habilitado | KV v2 en `secret/` |

El modo dev no se sella, no persiste al recrear el contenedor y el token `root` lo puede todo. Sirve para probar integraciones. No es el Vault de producción.

## Arranque

Desde la raíz del repo:

```bash
bash infra/reiniciar-vault.sh
source infra/entorno.sh
vault status
```

`reiniciar-vault.sh` deja un servidor vacío. `source infra/entorno.sh` exporta `VAULT_ADDR` y `VAULT_TOKEN` en **esta** terminal. Si abres otra, vuelve a cargarlo.

Las policies se registran con `bash infra/policy.sh NOMBRE`, que lee el HCL por la entrada estándar y lo guarda dentro del contenedor. El CLI de `vault kv` también necesita permiso de lectura en `sys/internal/ui/mounts/secret/*`; si falta, el 403 es de ese preflight y no del secreto.

Si no tienes el CLI de Vault, `entorno.sh` define una función `vault` que ejecuta el CLI dentro del contenedor. Los scripts que leen JSON usan `python3`: el Codespace lo instala al crearse; en Docker local tiene que estar en tu terminal.

## Codespace

1. Haz fork del repositorio.
2. **Code → Create codespace on main**.
3. Al terminar, el puerto **8200** queda publicado. Ábrelo solo si quieres la UI; los laboratorios usan la terminal.
4. Espera a que termine el **postCreate** (Vault se levanta solo). Si en la terminal sale `docker: command not found`, no sigas: **Ctrl+Shift+P → Codespaces: Rebuild Container** y espera de nuevo. Si persiste, borra el codespace y créalo otra vez desde **Create codespace on main** (tiene que existir la carpeta `.devcontainer` en tu fork).
5. Si hace falta, ejecuta el arranque de arriba a mano.

### Fallos frecuentes

| Síntoma | Qué hacer |
|---------|-----------|
| `docker: command not found` | Rebuild Container; no abras el repo solo en el navegador sin codespace |
| `No encuentro el contenedor de este Codespace` / `No such container` | `git pull` y `bash infra/reiniciar-vault.sh`. Si sigue, pega la salida de `docker ps --format '{{.ID}} {{.Names}}'` |
| `sharing network namespace` / no se puede unir a la red | El Codespace usa la red del host. `git pull` y `bash infra/reiniciar-vault.sh`: el puente publica el 8200 |
| `El puente a Vault no responde` | `bash infra/reiniciar-vault.sh` otra vez; si falla, `cat /tmp/vault-puente.log` |
| `Vault no ha respondido` | `docker logs vault-dev` |

## Contenedores de aplicación (módulo 5)

Los laboratorios de integración arrancan, además de `vault-dev`, el contenedor `pagos` (la máquina de la aplicación, con Vault Agent) y, en el módulo 5, `pagos-db` (Postgres). Esos contenedores no son el servidor Vault. `bash infra/reiniciar-vault.sh` los elimina.

## Qué no hace este entorno

No reproduce el clúster, el auto-unseal ni los métodos de autenticación de producción. Cada laboratorio construye aquí el estado que necesita para poder hacerse solo.
