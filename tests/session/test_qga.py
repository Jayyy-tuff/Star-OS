# SPDX-License-Identifier: GPL-3.0-or-later
"""Unit tests for qga.py against a fake guest agent on a Unix socket."""

import base64
import json
import os
import socket
import sys
import tempfile
import threading
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import qga  # noqa: E402


class FakeAgent(threading.Thread):
    """Answers QGA requests; starts with stale output like a real agent can."""

    def __init__(self, path, stale=b'{"return": 7}\n\xff', exit_code=0):
        super().__init__(daemon=True)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(1)
        self.stale = stale
        self.exit_code = exit_code
        self.requests = []
        self.polls = 0

    def run(self):
        conn, _ = self.server.accept()
        self.server.close()
        reader = conn.makefile("rb")
        conn.sendall(self.stale)
        for line in reader:
            request = json.loads(line)
            self.requests.append(request)
            command = request["execute"]
            args = request.get("arguments", {})
            if command == "guest-sync":
                reply = {"return": args["id"]}
            elif command == "guest-exec":
                reply = {"return": {"pid": 42}}
            elif command == "guest-exec-status":
                self.polls += 1
                if self.polls < 2:
                    reply = {"return": {"exited": False}}
                else:
                    reply = {"return": {"exited": True, "exitcode": self.exit_code,
                                        "out-data": base64.b64encode(b"hello\n").decode()}}
            else:
                reply = {"error": {"class": "CommandNotFound", "desc": f"no {command}"}}
            # Replies may arrive split across reads.
            data = json.dumps(reply).encode() + b"\n"
            conn.sendall(data[:5])
            conn.sendall(data[5:])
        reader.close()
        conn.close()


class GuestAgentTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.dir.name, "qga.sock")

    def tearDown(self):
        self.dir.cleanup()

    def agent(self, **kwargs):
        fake = FakeAgent(self.path, **kwargs)
        fake.start()
        client = qga.GuestAgent(self.path, timeout=5)
        client.connect()
        self.addCleanup(client.close)
        return fake, client

    def test_sync_skips_stale_replies(self):
        _, client = self.agent()
        self.assertTrue(client.sync())

    def test_run_waits_and_decodes_output(self):
        fake, client = self.agent()
        client.sync()
        code, out, err = client.run(["/bin/echo", "hello"], env={"A": "1"}, stdin="x")
        self.assertEqual((code, out, err), (0, "hello\n", ""))
        request = fake.requests[1]["arguments"]
        self.assertEqual(request["path"], "/bin/echo")
        self.assertEqual(request["arg"], ["hello"])
        self.assertEqual(request["env"], ["A=1"])
        self.assertEqual(base64.b64decode(request["input-data"]), b"x")
        self.assertTrue(request["capture-output"])

    def test_run_without_wait_returns_pid(self):
        _, client = self.agent()
        client.sync()
        self.assertEqual(client.run(["/bin/true"], wait=False), 42)

    def test_error_reply_raises(self):
        _, client = self.agent()
        client.sync()
        with self.assertRaises(qga.GuestAgentError):
            client.execute("guest-nonsense")

    def test_write_file_failure_raises(self):
        _, client = self.agent(exit_code=1)
        client.sync()
        with self.assertRaises(qga.GuestAgentError):
            client.write_file("/run/staros-test/x", "data")

    def test_timeout(self):
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(self.path)
        server.listen(1)
        self.addCleanup(server.close)
        client = qga.GuestAgent(self.path, timeout=0.3)
        client.connect()
        self.addCleanup(client.close)
        with self.assertRaises(qga.GuestAgentError):
            client.sync()


if __name__ == "__main__":
    unittest.main()
