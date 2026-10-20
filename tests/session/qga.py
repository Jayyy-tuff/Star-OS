# SPDX-License-Identifier: GPL-3.0-or-later
"""Minimal QEMU guest agent client (standard library only).

Talks QGA's JSON protocol over the Unix socket of a QEMU chardev that backs a
virtserialport named org.qemu.guest_agent.0. Used only by the CI session test;
nothing here ships in the image.
"""

import base64
import json
import random
import socket
import time


class GuestAgentError(Exception):
    """The agent reported an error or did not answer in time."""


class GuestAgent:
    def __init__(self, path, timeout=10.0):
        self.path = path
        self.timeout = timeout
        self.sock = None
        self.buffer = b""

    def connect(self):
        self.close()
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)
        self.buffer = b""

    def close(self):
        if self.sock is not None:
            self.sock.close()
            self.sock = None

    def _send(self, command, arguments=None):
        request = {"execute": command}
        if arguments is not None:
            request["arguments"] = arguments
        self.sock.sendall(json.dumps(request).encode() + b"\n")

    def _read_message(self, deadline):
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise GuestAgentError("timed out waiting for the guest agent")
            self.sock.settimeout(remaining)
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout as err:
                raise GuestAgentError("timed out waiting for the guest agent") from err
            if not chunk:
                raise GuestAgentError("guest agent connection closed")
            self.buffer += chunk
        line, _, self.buffer = self.buffer.partition(b"\n")
        # A resynchronisation can leave a 0xff delimiter or partial data.
        line = line.replace(b"\xff", b"").strip()
        if not line:
            return None
        try:
            return json.loads(line)
        except ValueError:
            return None

    def sync(self, timeout=None):
        """Discards stale replies; returns once the agent echoes a fresh id."""
        token = random.randint(1, 2**31 - 1)
        deadline = time.monotonic() + (timeout or self.timeout)
        self._send("guest-sync", {"id": token})
        while True:
            message = self._read_message(deadline)
            if isinstance(message, dict) and message.get("return") == token:
                return True

    def execute(self, command, arguments=None, timeout=None):
        deadline = time.monotonic() + (timeout or self.timeout)
        self._send(command, arguments)
        while True:
            message = self._read_message(deadline)
            if not isinstance(message, dict):
                continue
            if "error" in message:
                raise GuestAgentError(f"{command}: {message['error'].get('desc', message['error'])}")
            if "return" in message:
                return message["return"]

    def run(self, argv, env=None, stdin=None, timeout=60.0, wait=True):
        """Runs a command in the guest as root.

        Returns (exit code, stdout, stderr) as text, or the guest PID when
        wait is false.
        """
        arguments = {"path": argv[0], "arg": list(argv[1:]), "capture-output": wait}
        if env:
            arguments["env"] = [f"{k}={v}" for k, v in env.items()]
        if stdin is not None:
            data = stdin.encode() if isinstance(stdin, str) else stdin
            arguments["input-data"] = base64.b64encode(data).decode()
        pid = self.execute("guest-exec", arguments)["pid"]
        if not wait:
            return pid
        deadline = time.monotonic() + timeout
        while True:
            status = self.execute("guest-exec-status", {"pid": pid})
            if status.get("exited"):
                out = base64.b64decode(status.get("out-data", "")).decode("utf-8", "replace")
                err = base64.b64decode(status.get("err-data", "")).decode("utf-8", "replace")
                if "exitcode" in status:
                    code = status["exitcode"]
                elif "signal" in status:
                    code = 128 + status["signal"]
                else:
                    code = -1
                return code, out, err
            if time.monotonic() > deadline:
                raise GuestAgentError(f"{argv[0]} did not finish within {timeout} s")
            time.sleep(0.2)

    def write_file(self, path, data, mode="0644"):
        """Writes DATA to PATH in the guest (as root) through a shell."""
        script = 'umask 077; mkdir -p "$(dirname "$1")" && cat > "$1" && chmod "$2" "$1"'
        code, _, err = self.run(["/bin/sh", "-c", script, "sh", path, mode], stdin=data)
        if code != 0:
            raise GuestAgentError(f"writing {path} failed: {err.strip()}")
