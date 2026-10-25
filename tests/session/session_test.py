#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Drives the Star OS prototype session on the CI-built ISO (M0.2 to M0.5).

Boots the ISO in QEMU/KVM with the graphical profile, a QEMU guest agent port
and a USB tablet, waits for staros-session-report's verdict, then runs the
scenarios below with real key presses (QMP send-key) and observes the result
from three independent views:

  KWin    a test-time KWin script reports the window list and the active
          window over D-Bus to a listener (tests/session/guest/);
  shell   AT-SPI: roles, names, descriptions and focus of plasmashell's
          accessible objects;
  screen  QMP screen dumps (saved as PNG; informational).

Scenarios:
  S0 guest agent answers            S5 launch Konsole from the start menu
  S1 session facts                  S6 launch System Settings
  S2 test helpers and KWin oracle   S7 both windows in the taskbar
  S3 taskbar over AT-SPI            S8 switch windows with Meta+Alt+P
  S4 Meta opens the start menu      S9 Escape closes the start menu
  S12 launch Files; its Places and Folder contents lists over AT-SPI
  S13 launch Sun Store; its first-run "Enable Flathub" button over AT-SPI
      (CI has no network; nothing is added or downloaded)
  S14 quick answer: "12*3" shows "Answer: 36"; Return copies it
  S15 sticky note: "note: hello star" puts a note on the desktop and in
      ~/.local/share/staros/notes.json
  S16 the taskbar's "Quick settings" says the session is live (in memory)
  S17 Star Lens (Meta+Shift+L, else the launcher) takes a screenshot through
      KWin's grant, asks to select an area; Ctrl+A, Return show the results
      (the recognised text is informational); Escape twice closes it
  S18 an app exported into the live user's Flatpak directory while the
      session runs appears in the start menu's "Recently installed" without a
      restart, and starts from a search (ADR-0013)
  Informational: S11 scaling with kscreen-doctor (AT-SPI geometry and screen
  dumps at 150, 200 and 100 %), S10 Orca (Meta+Alt+S, then a debug Orca's
  speech output for the launcher).

Prints one 'EVIDENCE <scenario> PASS|FAIL|INFO <detail>' line per check and
writes session-result.json. Helpers are copied to /run/staros-test (tmpfs)
and nothing is installed in the image.

Exit status: 0 all gating checks passed, 1 a check failed, 2 setup error.
"""

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "iso"))

import boot_test  # noqa: E402
import qga  # noqa: E402
import screen  # noqa: E402

GUEST_DIR = "/run/staros-test"
HELPERS = ("runas.py", "atspi_probe.py", "oracle_listener.py", "kwin_oracle.js")
ORACLE_FILE = "/run/user/1000/staros-oracle.jsonl"
# Wayland app ids, matched by substring because packaging may prefix them.
KONSOLE = "konsole"
SETTINGS = "systemsettings"
FILES = "org.staros.files"
SUNSTORE = "org.staros.sunstore"
LENS = "org.staros.lens"
# The live medium's writable layer (M0.3, scripts/build-iso.sh).
KERNEL_PARAM = "cow_spacesize=50%"

# Characters that need a different key or Shift (US layout).
QCODES = {" ": ("spc",), "\n": ("ret",), "-": ("minus",), ".": ("dot",), "/": ("slash",),
          "*": ("kp_multiply",), "+": ("kp_add",), ":": ("shift", "semicolon")}


def qcode(ch):
    """The QMP qcodes to press together for one character."""
    if ch.isalpha() or ch.isdigit():
        return (ch.lower(),)
    return QCODES[ch]


class CheckFailed(Exception):
    pass


class Session:
    def __init__(self, args, log_dir):
        self.args = args
        self.log_dir = log_dir
        self.evidence = []
        self.failed = False
        self.proc = None
        self.agent = None
        self.shots = 0

    # ----- reporting -------------------------------------------------------

    def record(self, scenario, status, detail):
        line = f"EVIDENCE {scenario} {status} {detail}"
        print(line, flush=True)
        self.evidence.append({"scenario": scenario, "status": status, "detail": detail})
        if status == "FAIL":
            self.failed = True

    def check(self, scenario, condition, detail):
        self.record(scenario, "PASS" if condition else "FAIL", detail)
        if not condition:
            raise CheckFailed(f"{scenario}: {detail}")

    # ----- QEMU --------------------------------------------------------------

    def start(self, iso, name="session", vars_file=None, extra=()):
        """Boots ISO with UEFI. NAME names the logs; VARS_FILE keeps the UEFI
        variables between boots (a fresh copy otherwise); EXTRA adds QEMU
        arguments, such as a scratch disk."""
        fw = "uefi"
        self.serial_log = os.path.join(self.log_dir, f"serial-{name}.log")
        self.qemu_log = os.path.join(self.log_dir, f"qemu-{name}.log")
        self.sock_dir = tempfile.mkdtemp(prefix="staros-session-")
        self.qmp_socket = os.path.join(self.sock_dir, "qmp.sock")
        self.qga_socket = os.path.join(self.sock_dir, "qga.sock")
        pair = boot_test.find_ovmf()
        if pair is None:
            raise boot_test.SetupError("OVMF firmware not found")
        if vars_file is None:
            vars_file = os.path.join(self.log_dir, f"ovmf-vars-{name}.fd")
            shutil.copyfile(pair[1], vars_file)
        accel = "kvm" if os.access("/dev/kvm", os.R_OK | os.W_OK) else "tcg"
        cmd = boot_test.build_qemu_command(
            shutil.which(self.args.qemu) or self.args.qemu, iso, fw, accel,
            boot_test.PROFILES["graphical"]["memory"], self.serial_log, self.qmp_socket,
            pair[0], vars_file, "graphical")
        devices = [
            "-device", "virtio-serial-pci,id=vser0",
            "-chardev", f"socket,id=qga0,path={self.qga_socket},server=on,wait=off",
            "-device", "virtserialport,bus=vser0.0,chardev=qga0,name=org.qemu.guest_agent.0",
            "-device", "qemu-xhci,id=xhci",
            "-device", "usb-tablet,bus=xhci.0",
            *extra,
        ]
        cmd = cmd[:-1] + devices + cmd[-1:]
        print("+ " + shlex.join(cmd), flush=True)
        with open(self.qemu_log, "wb") as out:
            self.proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT)
        self.started = time.monotonic()

    def connect_agent(self, seconds=120):
        """Connects to the guest agent (udev starts it when the port
        appears). Returns None, or the last error after SECONDS."""
        self.agent = qga.GuestAgent(self.qga_socket, timeout=10)
        deadline = time.monotonic() + seconds
        while True:
            try:
                self.agent.connect()
                self.agent.sync(timeout=10)
                return None
            except (OSError, qga.GuestAgentError) as err:
                if time.monotonic() > deadline:
                    return err
                time.sleep(3)

    def install_helpers(self):
        """Copies the guest helpers to GUEST_DIR (tmpfs), starts the oracle
        listener and loads the KWin oracle script. Returns (script id or None,
        bus error text)."""
        for name in HELPERS:
            with open(os.path.join(HERE, "guest", name), encoding="utf-8") as f:
                self.agent.write_file(f"{GUEST_DIR}/{name}", f.read(), mode="0644")
        self.guest(["/usr/bin/chmod", "0755", GUEST_DIR])
        self.as_user(["/usr/bin/python3", "-I", f"{GUEST_DIR}/oracle_listener.py", ORACLE_FILE],
                     wait=False)
        time.sleep(2)
        code, out, err = self.as_user(["/usr/bin/busctl", "--user", "call", "org.kde.KWin",
                                       "/Scripting", "org.kde.kwin.Scripting", "loadScript", "ss",
                                       f"{GUEST_DIR}/kwin_oracle.js", "staros-test-oracle"])
        script_id = out.split()[-1] if code == 0 and out.split() else None
        if script_id is not None and script_id != "-1":
            self.as_user(["/usr/bin/busctl", "--user", "call", "org.kde.KWin",
                          f"/Scripting/Script{script_id}", "org.kde.kwin.Script", "run"])
        return script_id, err.strip()

    def stop(self):
        if self.agent:
            self.agent.close()
        if self.proc:
            boot_test.stop_qemu(self.proc, self.qmp_socket)
        shutil.rmtree(getattr(self, "sock_dir", ""), ignore_errors=True)

    def qmp(self, command, arguments=None):
        reply = boot_test.qmp_execute(self.qmp_socket, command, arguments)
        if "error" in reply:
            raise boot_test.SetupError(f"QMP {command}: {reply['error']}")
        return reply.get("return")

    def keys(self, *names, hold_ms=80):
        """Presses the named keys together, then releases them."""
        self.qmp("send-key", {"keys": [{"type": "qcode", "data": n} for n in names],
                              "hold-time": hold_ms})
        time.sleep(0.3)

    def type_text(self, text):
        for ch in text:
            self.keys(*qcode(ch))

    def screenshot(self, label):
        self.shots += 1
        ppm = os.path.join(self.log_dir, f"shot-{self.shots:02d}.ppm")
        png = os.path.join(self.log_dir, f"shot-{self.shots:02d}-{label}.png")
        try:
            self.qmp("screendump", {"filename": ppm})
            with open(ppm, "rb") as f:
                image = screen.parse_ppm(f.read())
            with open(png, "wb") as f:
                f.write(screen.png_bytes(image))
            os.remove(ppm)
            facts = screen.analyse(image)
            self.record(label, "INFO", "screen " + " ".join(f"{k}={v}" for k, v in facts.items()))
        except (OSError, ValueError, boot_test.SetupError) as err:
            self.record(label, "INFO", f"screen dump failed: {err}")

    # ----- guest -------------------------------------------------------------

    def wait_session_ok(self):
        deadline = self.started + self.args.session_timeout
        while time.monotonic() < deadline:
            session = boot_test.parse_session(boot_test.read_text(self.serial_log))
            if session["status"] is not None:
                return session
            if self.proc.poll() is not None:
                raise boot_test.SetupError(f"QEMU exited with status {self.proc.returncode}")
            time.sleep(2)
        raise boot_test.SetupError("timed out waiting for the session report")

    def guest(self, argv, timeout=60, stdin=None, wait=True):
        return self.agent.run(argv, timeout=timeout, stdin=stdin, wait=wait)

    def as_user(self, argv, timeout=60, wait=True):
        return self.guest(["/usr/bin/python3", "-I", f"{GUEST_DIR}/runas.py"] + argv,
                          timeout=timeout, wait=wait)

    def atspi(self, *args, timeout=90):
        code, out, err = self.as_user(
            ["/usr/bin/python3", "-I", f"{GUEST_DIR}/atspi_probe.py", *args], timeout=timeout)
        lines = [line for line in out.splitlines() if line.startswith("{")]
        if not lines:
            return {"error": f"no output (exit {code}): {err.strip()[-300:]}"}
        return json.loads(lines[-1])

    def oracle(self):
        code, out, _ = self.guest(["/usr/bin/cat", ORACLE_FILE])
        events = []
        for line in out.splitlines():
            try:
                events.append(json.loads(line))
            except ValueError:
                continue
        return events

    def wait_oracle(self, predicate, seconds, what):
        deadline = time.monotonic() + seconds
        last = None
        while time.monotonic() < deadline:
            events = [e for e in self.oracle() if "windows" in e]
            if events:
                last = events[-1]
                if predicate(last):
                    return last
            time.sleep(1)
        raise CheckFailed(f"KWin never reported {what}; last report: {json.dumps(last)}")

    def wait_focus(self, role, name, seconds=10):
        deadline = time.monotonic() + seconds
        focus = None
        while time.monotonic() < deadline:
            focus = self.atspi("focused", "2", timeout=30)
            roles = (role,) if isinstance(role, str) else role
            if focus.get("role") in roles and (name is None or focus.get("name") == name):
                return focus
            time.sleep(0.5)
        return focus

    def journal_shell(self):
        code, out, _ = self.guest(["/usr/bin/journalctl", "-b", "_UID=1000", "-o", "cat",
                                   "--no-pager", "-q"], timeout=60)
        return [line for line in out.splitlines() if "STAROS-SHELL" in line]


def is_active(report, app):
    return app in str(report.get("active") or "").lower()


# at-spi2-core renamed the push-button role name to "button"; accept both.
BUTTON = ("push button", "button")


def find(node, role=None, name=None, description=None, showing=False):
    """All nodes of an AT-SPI tree matching the given fields (role: str or tuple).

    The tree also holds hidden objects (Qt Quick items with visible: false);
    showing=True keeps only those on screen.
    """
    roles = (role,) if isinstance(role, str) else role
    found = []
    if ((roles is None or node.get("role") in roles)
            and (name is None or node.get("name") == name)
            and (description is None or node.get("description") == description)
            and (not showing or "showing" in node.get("states", []))):
        found.append(node)
    for child in node.get("children", []):
        found.extend(find(child, role, name, description, showing))
    return found


def run_scenarios(s):
    # S0: the guest agent answers (udev starts it when the port appears).
    err = s.connect_agent()
    s.check("S0", err is None, f"guest agent answers{'' if err is None else f': {err}'}")

    # S1: session facts seen from inside the guest.
    code, out, _ = s.guest(["/usr/bin/sh", "-c",
                            "pid=$(pgrep -u liveuser -x plasmashell | head -n1); "
                            "tr '\\0' '\\n' </proc/$pid/environ | grep -E '^(PLASMA_DEFAULT_SHELL|WAYLAND_DISPLAY|XDG_SESSION_TYPE)='"])
    s.check("S1", "PLASMA_DEFAULT_SHELL=org.staros.shell" in out
            and "XDG_SESSION_TYPE=wayland" in out,
            "plasmashell environment: " + out.replace("\n", " ").strip())
    # plasmashell saves its layout lazily, so the file may appear later.
    code, out, _ = s.guest(["/usr/bin/sh", "-c", "ls /home/liveuser/.config/ | grep appletsrc"])
    s.record("S1", "INFO", "appletsrc files: " + (out.replace("\n", " ").strip() or "none yet"))
    code, out, _ = s.guest(["/usr/bin/cat", "/proc/cmdline"])
    s.check("S1", KERNEL_PARAM in out.split(), f"kernel command line has {KERNEL_PARAM}: {out.strip()}")
    code, out, _ = s.guest(["/usr/bin/df", "-h", "--output=size,used,target", "/run/archiso/cowspace"])
    s.record("S1", "INFO", "copy-on-write space: " + " ".join(out.split()))

    # S2: helpers, KWin oracle and its listener.
    script_id, err = s.install_helpers()
    s.check("S2", script_id is not None and script_id != "-1",
            f"KWin script loaded (id {script_id}) {err}")
    loaded = s.wait_oracle(lambda e: True, 20, "a first report")
    s.check("S2", True, "KWin oracle reports: " + json.dumps(loaded))

    # S3: the taskbar over AT-SPI (the harness enables a11y as Orca would).
    s.atspi("enable")
    tree = s.atspi("walk", "plasmashell", "45")
    with open(os.path.join(s.log_dir, "atspi-taskbar.json"), "w") as f:
        json.dump(tree, f, indent=1)
    toolbar = find(tree, role="tool bar", name="Taskbar")
    s.check("S3", bool(toolbar), "plasmashell exposes a 'Taskbar' tool bar")
    outline = [(n.get("role"), n.get("name")) for n in find(toolbar[0])]
    for role, name in ((BUTTON, "Applications"), ("list", "Apps"), (BUTTON, "Quick settings"),
                       (BUTTON, "Clock"), (BUTTON, "Notifications")):
        s.check("S3", bool(find(toolbar[0], role=role, name=name)),
                f"{name!r} in the taskbar; taskbar objects: {outline}")
    s.screenshot("S3-desktop")

    # S4: Meta opens the launcher with focus in the search field.
    s.keys("meta_l")
    focus = s.wait_focus("text", "Search applications")
    if focus.get("name") not in ("Search applications", "Application launcher"):
        # Only when the launcher did not open: Alt+F1 toggles it.
        s.record("S4", "INFO", f"Meta gave focus {focus}; retrying with Alt+F1")
        s.keys("alt", "f1")
        focus = s.wait_focus("text", "Search applications")
    s.check("S4", focus.get("name") == "Search applications",
            f"launcher search field focused: {json.dumps(focus)}")
    s.screenshot("S4-launcher")

    # S5: type to search, Return launches the first match.
    s.type_text("kon")
    s.keys("ret")
    report = s.wait_oracle(lambda e: is_active(e, KONSOLE), 45, f"active {KONSOLE}")
    s.check("S5", True, f"Konsole launched and active per KWin: {json.dumps(report)}")

    # S6: a second application.
    s.keys("meta_l")
    s.wait_focus("text", "Search applications")
    s.type_text("system set")
    s.keys("ret")
    report = s.wait_oracle(lambda e: is_active(e, SETTINGS), 60, f"active {SETTINGS}")
    s.check("S6", True, f"System Settings launched and active per KWin: {json.dumps(report)}")

    # S7: both windows are in the taskbar's apps (with the pinned apps); the
    # active one is marked.
    time.sleep(3)
    tree = s.atspi("walk", "plasmashell", "20")
    with open(os.path.join(s.log_dir, "atspi-two-windows.json"), "w") as f:
        json.dump(tree, f, indent=1)
    apps = find(tree, role="list", name="Apps")
    buttons = find(apps[0], role=BUTTON) if apps else []
    windows = [b for b in buttons if b.get("description") in ("Window", "Active window")]
    s.record("S7", "INFO", "taskbar apps: " + json.dumps([(b["name"], b["description"]) for b in buttons]))
    s.check("S7", len(windows) == 2,
            "window buttons: " + json.dumps([(b["name"], b["description"]) for b in windows]))
    active = [b for b in windows if b["description"] == "Active window"]
    s.check("S7", len(active) == 1, "exactly one button is described as 'Active window'")
    s.screenshot("S7-two-windows")

    # S8: keyboard switching through the taskbar.
    s.keys("meta_l", "alt", "p")
    focus = s.wait_focus(BUTTON, "Applications")
    s.check("S8", focus.get("name") == "Applications",
            f"Meta+Alt+P focuses the taskbar: {json.dumps(focus)}")
    # Right moves through the pinned apps to Konsole's window.
    focus = {}
    for _ in range(10):
        s.keys("right")
        time.sleep(0.4)
        focus = s.wait_focus(BUTTON, None)
        if "Konsole" in str(focus.get("name")) and focus.get("description") == "Window":
            break
    s.check("S8", "Konsole" in str(focus.get("name")), f"Right reaches Konsole's window: {json.dumps(focus)}")
    s.keys("ret")
    report = s.wait_oracle(lambda e: is_active(e, KONSOLE), 20, f"active {KONSOLE}")
    s.check("S8", True, f"Return on Konsole's button activates it: {json.dumps(report)}")

    # S9: Escape closes the launcher and KWin returns focus to the window.
    s.keys("meta_l")
    s.wait_focus("text", "Search applications")
    s.keys("esc")
    report = s.wait_oracle(lambda e: is_active(e, KONSOLE), 20, f"active {KONSOLE}")
    s.check("S9", True, f"Escape returns to Konsole: {json.dumps(report)}")

    # S12: Files from the launcher, with its accessible lists.
    launch(s, "fil")
    report = s.wait_oracle(lambda e: is_active(e, FILES), 45, f"active {FILES}")
    s.check("S12", True, f"Files launched and active per KWin: {json.dumps(report)}")
    lists = ("Places", "Folder contents")
    tree = wait_tree(s, "staros-files",
                     lambda t: all(find(t, role="list", name=n, showing=True) for n in lists), 30)
    with open(os.path.join(s.log_dir, "atspi-files.json"), "w") as f:
        json.dump(tree, f, indent=1)
    for name in lists:
        s.check("S12", bool(find(tree, role="list", name=name, showing=True)),
                f"Files shows a list named {name!r}: {showing_objects(tree)}")
    s.screenshot("S12-files")

    # S13: Sun Store from the launcher. No user remote exists, so it asks
    # before adding Flathub; the test does not press the button.
    launch(s, "sun")
    report = s.wait_oracle(lambda e: is_active(e, SUNSTORE), 45, f"active {SUNSTORE}")
    s.check("S13", True, f"Sun Store launched and active per KWin: {json.dumps(report)}")
    tree = wait_tree(s, "staros-sunstore",
                     lambda t: find(t, role=BUTTON, name="Enable Flathub", showing=True), 30)
    with open(os.path.join(s.log_dir, "atspi-sunstore.json"), "w") as f:
        json.dump(tree, f, indent=1)
    s.check("S13", bool(find(tree, role=BUTTON, name="Enable Flathub", showing=True)),
            f"Sun Store shows an 'Enable Flathub' button: {showing_objects(tree)}")
    code, out, _ = s.as_user(["/usr/bin/flatpak", "remotes", "--user", "--columns=name"], timeout=30)
    s.check("S13", code == 0 and not out.strip(), f"no Flatpak remote was added: {out.strip()!r}")
    s.screenshot("S13-sunstore")

    # S14: a quick answer in the launcher; Return copies it and closes.
    s.keys("meta_l")
    s.wait_focus("text", "Search applications")
    s.type_text("12*3")
    time.sleep(1)
    tree = s.atspi("walk", "plasmashell", "20")
    answers = find(tree, name="Answer: 36")
    s.check("S14", bool(answers), f"the launcher shows 'Answer: 36': {named_objects(tree, 60)}")
    s.keys("ret")
    time.sleep(1)
    s.check("S14", any("STAROS-SHELL answer=36" in line for line in s.journal_shell()),
            "Return copied the answer (shell log 'answer=36')")

    # S15: "note:" makes a sticky note on the desktop.
    s.keys("meta_l")
    s.wait_focus("text", "Search applications")
    s.type_text("note: hello star")
    s.keys("ret")
    time.sleep(2)
    code, out, _ = s.guest(["/usr/bin/cat", "/home/liveuser/.local/share/staros/notes.json"])
    s.check("S15", code == 0 and "hello star" in out, f"notes.json has the note: {out.strip()[:300]!r}")
    tree = s.atspi("walk", "plasmashell", "20")
    notes = [n for n in find(tree, name="Sticky note") if n.get("description") == "hello star"]
    s.check("S15", bool(notes), "the desktop shows a 'Sticky note' with the text over AT-SPI")
    s.screenshot("S15-note")

    # S16: the tray's Quick settings button says where changes are kept.
    trays = find(tree, role=BUTTON, name="Quick settings")
    detail = trays[0].get("description", "") if trays else ""
    s.check("S16", detail.startswith("Live session: changes are lost at shutdown."),
            f"'Quick settings' says: {detail!r}")

    # S17: Star Lens. Meta+Shift+L is its global shortcut, registered from its
    # desktop file (informational); when it does not start Star Lens the
    # launcher does, so the screenshot and the results are checked either way.
    s.keys("meta_l", "shift", "l")
    try:
        report = s.wait_oracle(lambda e: is_active(e, LENS), 20, f"active {LENS}")
        s.record("S17", "INFO", "Meta+Shift+L started Star Lens")
    except CheckFailed as err:
        s.record("S17", "INFO", f"Meta+Shift+L did not start Star Lens ({err}); using the launcher")
        launch(s, "lens")
        report = s.wait_oracle(lambda e: is_active(e, LENS), 45, f"active {LENS}")
    s.check("S17", True, f"Star Lens active per KWin: {json.dumps(report)}")
    # The view keeps every panel in the tree and hides the ones for other
    # states, so only objects that are showing count.
    tree = wait_tree(s, "staros-lens", lambda t: find(t, name="Select an area", showing=True), 30)
    with open(os.path.join(s.log_dir, "atspi-lens.json"), "w") as f:
        json.dump(tree, f, indent=1)
    s.check("S17", bool(find(tree, name="Select an area", showing=True)),
            f"Star Lens has a screenshot and asks to select an area: {showing_objects(tree)}")
    s.screenshot("S17-lens-select")
    s.keys("ctrl", "a")
    s.keys("ret")
    tree = wait_tree(s, "staros-lens", lambda t: find(t, name="Results", showing=True), 120)
    with open(os.path.join(s.log_dir, "atspi-lens-results.json"), "w") as f:
        json.dump(tree, f, indent=1)
    s.check("S17", bool(find(tree, name="Results", showing=True)),
            f"Ctrl+A and Return show the 'Results': {showing_objects(tree)}")
    texts = find(tree, name="Recognised text", showing=True)
    if texts:
        s.record("S17", "INFO", f"recognised text: {texts[0].get('description', '')[:300]!r}")
    else:
        s.record("S17", "INFO", "no text recognised")
    s.screenshot("S17-lens-results")
    # Escape returns to selecting; a second Escape closes Star Lens, which
    # copied nothing and so has nothing to keep serving.
    s.keys("esc")
    time.sleep(1)
    s.keys("esc")
    deadline = time.monotonic() + 20
    code = 0
    while code == 0 and time.monotonic() < deadline:
        time.sleep(1)
        code, _, _ = s.guest(["/usr/bin/pgrep", "-x", "staros-lens"])
    s.check("S17", code == 1, "Escape twice closed Star Lens")

    # S18: an app installed while the session runs appears in the start menu
    # (ADR-0013). Flatpak exports desktop files into the user's export
    # directory; this writes one there as Flatpak would, with an Exec that
    # leaves a marker, without network.
    scenario_installed_app(s)

    # Informational until each has three consecutive green runs (design spec).
    for scenario in (scenario_scaling, scenario_orca):
        try:
            scenario(s)
        except (CheckFailed, qga.GuestAgentError, boot_test.SetupError, ValueError,
                KeyError, IndexError) as err:
            s.record(scenario.__name__, "INFO", f"did not complete: {err}")


def launch(s, text):
    """Opens the launcher, types TEXT and launches the first match."""
    s.keys("meta_l")
    s.wait_focus("text", "Search applications")
    s.type_text(text)
    s.keys("ret")


def wait_tree(s, app, predicate, seconds):
    """APP's AT-SPI tree once PREDICATE holds for it, else the last tree."""
    deadline = time.monotonic() + seconds
    tree = {}
    while time.monotonic() < deadline:
        tree = s.atspi("walk", app, "30")
        if predicate(tree):
            break
        time.sleep(2)
    return tree


def named_objects(tree, limit=40):
    """Roles and names of a tree's named objects, for evidence lines."""
    named = [(n.get("role"), n.get("name")) for n in find(tree) if n.get("name")]
    return json.dumps(named[:limit])


def showing_objects(tree, limit=40):
    """Roles and names of a tree's named objects on screen, for evidence lines."""
    named = [(n.get("role"), n.get("name")) for n in find(tree, showing=True) if n.get("name")]
    return json.dumps(named[:limit])


def overlaps(a, b):
    return a[0] < b[0] + b[2] and b[0] < a[0] + a[2] and a[1] < b[1] + b[3] and b[1] < a[1] + a[3]


def launcher_geometry(tree):
    """Checks tiles of the open launcher: inside its window, no overlaps."""
    frames = find(tree, role="frame", name="Star OS applications")
    if not frames:
        return False, "launcher window not found over AT-SPI"
    window = frames[0]["extents"]
    tiles = [t for t in find(frames[0], role=BUTTON, showing=True) if t.get("extents")]
    problems = []
    for i, tile in enumerate(tiles):
        x, y, w, h = tile["extents"]
        if x < 0 or y < 0 or x + w > window[2] or y + h > window[3]:
            problems.append(f"{tile['name']} {tile['extents']} outside {window}")
        for other in tiles[i + 1:]:
            if overlaps(tile["extents"], other["extents"]):
                problems.append(f"{tile['name']} overlaps {other['name']}")
    return (len(tiles) >= 2 and not problems,
            f"{len(tiles)} tiles in window {window}; " + ("; ".join(problems) or "no problems"))


EXPORTS = "/home/liveuser/.local/share/flatpak/exports/share"
TEST_APP = "org.staros.TestApp"
TEST_APP_MARKER = "/tmp/staros-test-app-started"


def scenario_installed_app(s):
    code, out, _ = s.guest(["/usr/bin/sh", "-c",
                            "pid=$(pgrep -u liveuser -x plasmashell | head -n1); "
                            "tr '\\0' '\\n' </proc/$pid/environ | grep '^XDG_DATA_DIRS='"])
    s.check("S18", EXPORTS in out, f"plasmashell's data directories include the Flatpak exports: {out.strip()}")
    entry = ("[Desktop Entry]\nType=Application\nName=Star Test App\nGenericName=Test game\n"
             f"Exec=/usr/bin/touch {TEST_APP_MARKER}\nIcon=applications-games\nCategories=Game;\n")
    path = f"{EXPORTS}/applications/{TEST_APP}.desktop"
    code, out, err = s.as_user(["/usr/bin/sh", "-c", f"mkdir -p {EXPORTS}/applications && "
                                f"printf '%b' {shlex.quote(entry)} > {path} && cat {path}"], timeout=30)
    s.check("S18", code == 0 and "Star Test App" in out, f"exported {path}: {(out + err).strip()[:200]!r}")

    # The open start menu follows the install.
    s.keys("meta_l")
    s.wait_focus("text", "Search applications")
    tree = wait_tree(s, "plasmashell", lambda t: find(t, role=BUTTON, name="Star Test App", showing=True), 60)
    found = find(tree, role=BUTTON, name="Star Test App", showing=True)
    s.check("S18", bool(found), "'Recently installed' lists it: "
            + json.dumps([(n.get("name"), n.get("description")) for n in found]))
    if found:
        s.check("S18", str(found[0].get("description", "")).startswith("New."),
                f"it is marked new: {found[0].get('description')!r}")
    s.screenshot("S18-installed-app")
    s.type_text("star test")
    time.sleep(1)
    s.keys("ret")
    code = 1
    deadline = time.monotonic() + 30
    while code != 0 and time.monotonic() < deadline:
        time.sleep(1)
        code, _, _ = s.guest(["/usr/bin/test", "-e", TEST_APP_MARKER])
    s.check("S18", code == 0, f"searching 'star test' and Return started it ({TEST_APP_MARKER} exists)")
    s.check("S18", any(f"STAROS-SHELL launch={TEST_APP}.desktop" in line for line in s.journal_shell()),
            f"the shell logged 'launch={TEST_APP}.desktop'")
    s.guest(["/usr/bin/rm", "-f", path])


# S11: real scaling under KWin with kscreen-doctor (as the live user).
def scenario_scaling(s):
    code, out, err = s.as_user(["/usr/bin/kscreen-doctor", "-j"], timeout=30)
    outputs = json.loads(out[out.find("{"):])["outputs"]
    name = outputs[0]["name"]
    for scale in ("1.5", "2", "1"):
        s.as_user(["/usr/bin/kscreen-doctor", f"output.{name}.scale.{scale}"], timeout=30)
        time.sleep(4)
        s.screenshot(f"S11-desktop-scale-{scale}")
        s.keys("meta_l")
        s.wait_focus("text", "Search applications")
        ok, detail = launcher_geometry(s.atspi("walk", "plasmashell", "20"))
        s.record("S11", "INFO", f"scale {scale}: {'PASS' if ok else 'FAIL'} {detail}")
        s.screenshot(f"S11-launcher-scale-{scale}")
        s.keys("esc")
        time.sleep(1)


# S10: Orca. Meta+Alt+S is kaccess's toggle; a debug Orca then logs what it
# would speak, even without a speech server.
def scenario_orca(s):
    s.keys("meta_l", "alt", "s")
    started = False
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline and not started:
        code, out, _ = s.guest(["/usr/bin/pgrep", "-u", "liveuser", "-x", "orca"])
        started = code == 0
        time.sleep(1)
    s.record("S10", "INFO", f"Meta+Alt+S started Orca: {started}")
    s.guest(["/usr/bin/pkill", "-u", "liveuser", "-x", "orca"])
    log = "/run/user/1000/staros-orca-debug.out"
    s.as_user(["/usr/bin/orca", "--replace", "--debug", f"--debug-file={log}"], wait=False)
    time.sleep(10)
    for keys in (("meta_l",), ("down",), ("right",), ("esc",)):
        s.keys(*keys)
        time.sleep(2)
    code, out, _ = s.guest(["/usr/bin/grep", "-a", "SPEECH OUTPUT", log])
    spoken = [line.split("SPEECH OUTPUT:", 1)[-1].strip() for line in out.splitlines()]
    heard = [n for n in ("Search applications", "Ark", "Files") if any(n in x for x in spoken)]
    s.record("S10", "INFO", f"names in Orca's speech output: {heard}; last lines: "
             + " | ".join(spoken[-12:]))
    s.guest(["/usr/bin/pkill", "-u", "liveuser", "-x", "orca"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--iso", required=True)
    parser.add_argument("--log-dir", default="session-logs")
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--session-timeout", type=int, default=480)
    args = parser.parse_args(argv)

    log_dir = os.path.abspath(args.log_dir)
    os.makedirs(log_dir, exist_ok=True)
    s = Session(args, log_dir)
    status = 0
    error = None
    try:
        s.start(os.path.abspath(args.iso))
        session = s.wait_session_ok()
        problems = boot_test.check_session(session, boot_test.read_forbidden_env())
        s.check("C1", not problems, "session report: " + ("; ".join(problems) or "ok"))
        run_scenarios(s)
    except CheckFailed as err:
        error = str(err)
    except (boot_test.SetupError, qga.GuestAgentError, OSError, ValueError) as err:
        error = f"setup: {err}"
        status = 2
    finally:
        if s.failed or error:
            try:
                if s.agent:
                    lines = s.journal_shell()
                    s.record("debug", "INFO", "shell log: " + " | ".join(lines[-20:]))
                    s.record("debug", "INFO", "oracle: " + json.dumps(s.oracle()[-5:]))
                s.screenshot("failure")
            except Exception as err:  # diagnostics must not hide the failure
                print(f"warning: diagnostics failed: {err}", file=sys.stderr)
        s.stop()
    if s.failed and status == 0:
        status = 1
    result = {"passed": status == 0, "error": error, "evidence": s.evidence}
    with open(os.path.join(log_dir, "session-result.json"), "w") as f:
        json.dump(result, f, indent=2)
    if error:
        print(f"error: {error}", file=sys.stderr)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("### Session test (QEMU/KVM, CI-built ISO)\n\n| Scenario | Status | Detail |\n|---|---|---|\n")
            for e in s.evidence:
                f.write(f"| {e['scenario']} | {e['status']} | {e['detail'][:200].replace('|', '/')} |\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
