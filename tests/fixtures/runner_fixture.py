#!/usr/bin/env python3
"""Minimal newline-JSON aura-runner fixture for the #15 replay test."""
import json
import socket
import sys
import time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8799


def send(conn, obj):
    conn.sendall((json.dumps(obj, separators=(",", ":")) + "\n").encode())


def state(tick):
    return {"op": "state", "tick": tick, "level": 1, "hearts": 3}


def handle(conn):
    f = conn.makefile("rb")
    tick = 0
    for raw in f:
        try:
            msg = json.loads(raw.decode())
        except json.JSONDecodeError:
            continue
        op = msg.get("op")
        if op == "hello":
            send(conn, {"op": "welcome", "seed": msg.get("seed", 42)})
            send(conn, state(tick))
        elif op == "tick":
            tick += 1
            time.sleep(0.002)
            send(conn, state(tick))
        elif op == "wish":
            time.sleep(0.003)
            send(conn, {"op": "notes", "kind": "WISH", "text": "ok"})
            send(conn, state(tick))
        elif op == "bye":
            return


def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(4)
    while True:
        conn, _ = srv.accept()
        try:
            handle(conn)
        finally:
            conn.close()


if __name__ == "__main__":
    main()
