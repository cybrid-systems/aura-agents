#!/usr/bin/env python3
"""Minimal RESP server for the #15 replay test: PING/SET/GET/DEL."""
import socket
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 6399


def read_line(f):
    return f.readline().rstrip(b"\r\n")


def read_command(f):
    first = read_line(f)
    if not first.startswith(b"*"):
        return None
    n = int(first[1:])
    parts = []
    for _ in range(n):
        head = read_line(f)
        if not head.startswith(b"$"):
            return None
        size = int(head[1:])
        parts.append(f.read(size))
        f.read(2)
    return parts


def serve(conn):
    f = conn.makefile("rb")
    store = {}
    while True:
        cmd = read_command(f)
        if not cmd:
            return
        name = cmd[0].upper()
        if name == b"PING":
            conn.sendall(b"+PONG\r\n")
        elif name == b"SET" and len(cmd) >= 3:
            store[cmd[1]] = cmd[2]
            conn.sendall(b"+OK\r\n")
        elif name == b"GET" and len(cmd) >= 2:
            value = store.get(cmd[1])
            if value is None:
                conn.sendall(b"$-1\r\n")
            else:
                conn.sendall(b"$" + str(len(value)).encode() + b"\r\n" + value + b"\r\n")
        elif name == b"DEL" and len(cmd) >= 2:
            existed = 1 if store.pop(cmd[1], None) is not None else 0
            conn.sendall(b":" + str(existed).encode() + b"\r\n")
        else:
            conn.sendall(b"-ERR unknown command\r\n")


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(8)
    while True:
        conn, _ = srv.accept()
        try:
            serve(conn)
        finally:
            conn.close()


if __name__ == "__main__":
    main()
