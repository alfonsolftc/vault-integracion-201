#!/usr/bin/env python3
"""Reenvía 127.0.0.1:8200 a la IP de vault-dev escrita en /tmp/vault-puente.upstream."""
import errno
import pathlib
import socket
import sys
import threading
import time

UPSTREAM = pathlib.Path("/tmp/vault-puente.upstream")


def _pipe(src: socket.socket, dst: socket.socket) -> None:
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for sock in (src, dst):
            try:
                sock.close()
            except OSError:
                pass


def _handle(client: socket.socket) -> None:
    try:
        vip = UPSTREAM.read_text(encoding="utf-8").split()[0]
        remote = socket.create_connection((vip, 8200), timeout=5)
    except (OSError, IndexError):
        client.close()
        return
    threading.Thread(target=_pipe, args=(client, remote), daemon=True).start()
    _pipe(remote, client)


def main() -> None:
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    deadline = time.monotonic() + 10
    while True:
        try:
            server.bind(("127.0.0.1", 8200))
            break
        except OSError as exc:
            if exc.errno != errno.EADDRINUSE or time.monotonic() >= deadline:
                print(
                    f"No puedo escuchar en 127.0.0.1:8200 ({exc.errno}: {exc.strerror}).",
                    file=sys.stderr,
                )
                raise SystemExit(1) from None
            time.sleep(0.2)
    server.listen(64)
    while True:
        client, _ = server.accept()
        threading.Thread(target=_handle, args=(client,), daemon=True).start()


if __name__ == "__main__":
    main()
