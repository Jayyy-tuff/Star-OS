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
  S19 quick settings opens from the tray by keyboard; the network tile says
      the wired network is connected; Right on the "Volume" slider raises
      PipeWire's sink volume (QEMU has an HDA sound card for this)
  S20 a notification sent over D-Bus as Files (naming its desktop entry)
      shows a toast and is listed in the clock's notification centre;
      "Clear all" empties it (ADR-0014)
  S23 (right after S2) the Welcome tour opened at login: its first page,
      Return turns the page, Escape skips it, and it is marked as seen in
      ~/.config/staros-welcomerc (ADR-0017)
  S24 Game Center opens from the start menu with its search, filters, game
      mode and "Get games"; no games are installed, so it says so
  S25 locking shows the Star OS lock screen (kscreenlocker with
      org.staros.lookandfeel): the time, a "Password" field and "Unlock";
      Return unlocks the passwordless live user (ADR-0016)
  S26 Power shows the Star OS logout screen ("What would you like to do?",
      Restart, Shut down, Log out, Cancel); Escape cancels it (ADR-0016)
  S21 a copy survives the app that made it (wl-copy exits, wl-paste still
      reads it); Meta+V lists the copies newest first and Return puts the
      chosen one back on the clipboard (ADR-0014)
  S22 the desktop shows the Clock, Weather (asking for a city; nothing is
      sent), System and Calendar widgets; hiding one in widgets.json hides
      it without a restart
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
WELCOME = "org.staros.welcome"
GAMES = "org.staros.games"
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

    # The harness enables a11y as Orca would; running Qt apps turn on their
    # AT-SPI bridge when told.
    s.atspi("enable")

    # S23: the Welcome tour, before anything else wants the focus.
    scenario_welcome(s)

    # S3: the taskbar over AT-SPI.
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

    # S19, S20: quick settings and notifications (ADR-0014).
    scenario_quick_settings(s)
    scenario_notifications(s)

    # S21, S22: the clipboard history and the desktop widgets.
    scenario_clipboard(s)
    scenario_widgets(s)

    # S24: Game Center (ADR-0017).
    scenario_game_center(s)

    # S26: the Star OS logout screen, asked for every choice (no countdown).
    # Before S25, so that a lock screen failure does not hide its result.
    scenario_logout_screen(s)

    # S25: the Star OS lock screen (ADR-0016).
    scenario_lock_screen(s)

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
    """Roles and names of a tree's named objects on screen, for evidence lines;
    the probe's error (with the applications it saw) when there is no tree."""
    if "error" in tree:
        return json.dumps(tree)[:600]
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


AUDIO_ARGS = ("-audiodev", "none,id=snd0", "-device", "intel-hda", "-device", "hda-output,audiodev=snd0")


def focus_taskbar_button(s, name, scenario):
    """Meta+Alt+P, then Right until the taskbar button NAME has the focus."""
    s.keys("meta_l", "alt", "p")
    focus = s.wait_focus(BUTTON, "Applications")
    for _ in range(16):
        if focus.get("name") == name:
            break
        s.keys("right")
        time.sleep(0.3)
        focus = s.wait_focus(BUTTON, None, seconds=3)
    s.check(scenario, focus.get("name") == name, f"the taskbar's {name!r} has the focus: {json.dumps(focus)}")
    return focus


def sink_volume(s):
    code, out, err = s.as_user(["/usr/bin/wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], timeout=30)
    return code, (out + err).strip()


def scenario_quick_settings(s):
    code, before = sink_volume(s)
    s.record("S19", "INFO", f"wpctl before: exit {code}, {before!r}")
    s.as_user(["/usr/bin/wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.5"], timeout=30)
    s.as_user(["/usr/bin/wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"], timeout=30)
    focus_taskbar_button(s, "Quick settings", "S19")
    s.keys("ret")
    tree = wait_tree(s, "plasmashell", lambda t: find(t, role="frame", name="Quick settings", showing=True), 20)
    frames = find(tree, role="frame", name="Quick settings", showing=True)
    s.check("S19", bool(frames), f"the 'Quick settings' panel is open: {showing_objects(tree, 60)}")
    panel = frames[0] if frames else {}
    network = find(panel, name="Network", showing=True)
    s.check("S19", bool(network) and network[0].get("description") == "Wired, connected",
            f"the network tile: {json.dumps(network[:1])}")
    sliders = find(panel, role="slider", name="Volume", showing=True)
    s.check("S19", bool(sliders), f"a 'Volume' slider: {json.dumps(sliders[:1])}")
    for name in ("Night light", "Do not disturb", "Star Lens", "Settings", "Power"):
        s.record("S19", "INFO", f"{name}: {json.dumps(find(panel, name=name, showing=True)[:1])}")
    s.screenshot("S19-quick-settings")
    # Tab to the slider, then Right twice: 50 % becomes 60 %.
    focus = {}
    for _ in range(12):
        s.keys("tab")
        time.sleep(0.3)
        focus = s.wait_focus(("slider",), None, seconds=2)
        if focus.get("role") == "slider" and focus.get("name") == "Volume":
            break
    s.check("S19", focus.get("name") == "Volume", f"Tab reaches the Volume slider: {json.dumps(focus)}")
    s.keys("right")
    time.sleep(0.5)
    s.keys("right")
    time.sleep(1.5)
    code, after = sink_volume(s)
    s.check("S19", code == 0 and "0.60" in after, f"PipeWire's sink volume after Right twice: {after!r}")
    s.keys("esc")
    time.sleep(1)


# As an installed app sends it, naming its desktop entry: Plasma's default
# settings keep notifications from unnamed senders ("Other applications")
# out of the history, and the notification centre follows those settings.
NOTIFY = ["/usr/bin/gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
          "--object-path", "/org/freedesktop/Notifications", "--method",
          "org.freedesktop.Notifications.Notify", "Files", "0", "org.staros.files",
          "Hello from the test", "Sent over D-Bus", "[]", "{'desktop-entry': <'org.staros.files'>}", "30000"]
NOTIFY_SUMMARY = "Hello from the test"


def notification_named(tree):
    """Showing objects named '<app>: Hello from the test' (the app name is
    the desktop entry's)."""
    return [n for n in find(tree, showing=True) if str(n.get("name", "")).endswith(": " + NOTIFY_SUMMARY)]


def scenario_notifications(s):
    code, out, err = s.as_user(["/usr/bin/gdbus", "call", "--session", "--dest", "org.freedesktop.Notifications",
                                "--object-path", "/org/freedesktop/Notifications", "--method",
                                "org.freedesktop.Notifications.GetServerInformation"], timeout=30)
    s.check("S20", code == 0 and "Plasma" in out, f"the notification server: {(out + err).strip()!r}")
    code, out, err = s.as_user(NOTIFY, timeout=30)
    s.check("S20", code == 0, f"Notify answered: {(out + err).strip()!r}")
    tree = wait_tree(s, "plasmashell", notification_named, 20)
    toasts = notification_named(tree)
    if not toasts:
        code, out, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b _UID=1000 -o cat --no-pager -q"
                                " | grep -i -E 'notif|toast' | tail -n 15"])
        s.record("S20", "INFO", f"journal about notifications: {out.strip()!r}")
        s.record("S20", "INFO", f"plasmashell objects: {showing_objects(tree, 30)}")
    s.check("S20", bool(toasts), f"a toast shows it: {json.dumps(toasts[:1])}")
    s.check("S20", toasts[0].get("name") == "Files: " + NOTIFY_SUMMARY,
            f"the toast names the app from its desktop entry: {toasts[0].get('name')!r}")
    s.screenshot("S20-toast")
    focus_taskbar_button(s, "Clock", "S20")
    s.keys("ret")
    tree = wait_tree(s, "plasmashell",
                     lambda t: find(t, role="frame", name="Calendar and notifications", showing=True), 20)
    frames = find(tree, role="frame", name="Calendar and notifications", showing=True)
    s.check("S20", bool(frames), f"the calendar and notifications are open: {showing_objects(tree, 60)}")
    panel = frames[0] if frames else {}
    listed = notification_named(panel)
    s.check("S20", bool(listed), f"the notification centre lists it: {json.dumps(listed[:1])}")
    today = [n for n in find(panel, showing=True) if str(n.get("name", "")).endswith(", today")]
    s.check("S20", bool(today), f"the calendar marks today: {json.dumps(today[:1])}")
    s.screenshot("S20-calendar")
    focus = {}
    for _ in range(12):
        focus = s.wait_focus(BUTTON, None, seconds=2)
        if focus.get("name") == "Clear all":
            break
        s.keys("tab")
        time.sleep(0.3)
    s.check("S20", focus.get("name") == "Clear all", f"Tab reaches 'Clear all': {json.dumps(focus)}")
    s.keys("ret")
    tree = wait_tree(s, "plasmashell", lambda t: find(t, name="No new notifications.", showing=True), 15)
    s.check("S20", bool(find(tree, name="No new notifications.", showing=True)), "Clear all emptied the centre")
    s.keys("esc")
    time.sleep(1)


# S11: real scaling under KWin with kscreen-doctor (as the live user).
def has_window(report, app):
    return any(app in str(w.get("resourceClass", "")).lower() for w in report.get("windows", []))


def dismiss_welcome(s, scenario, seconds=120):
    """Skips the Welcome tour opened at login (Escape), so that it holds no
    focus in later steps. Returns whether it was there."""
    try:
        report = s.wait_oracle(lambda e: has_window(e, WELCOME), seconds, f"a {WELCOME} window")
    except CheckFailed:
        s.record(scenario, "INFO", "no Welcome window appeared")
        return False
    if is_active(report, WELCOME):
        s.keys("esc")
    try:
        s.wait_oracle(lambda e: not has_window(e, WELCOME), 20, f"no {WELCOME} window")
        s.record(scenario, "INFO", "skipped the Welcome tour with Escape")
    except CheckFailed:
        s.as_user(["/usr/bin/pkill", "-x", "staros-welcome"], timeout=30)
        s.record(scenario, "INFO", "closed the Welcome tour with pkill")
    return True


def scenario_welcome(s):
    report = s.wait_oracle(lambda e: has_window(e, WELCOME), 120, f"a {WELCOME} window")
    s.check("S23", is_active(report, WELCOME), f"the Welcome tour opened at login and is active: {json.dumps(report)}")
    tree = wait_tree(s, "staros-welcome", lambda t: find(t, name="Take the tour", showing=True), 30)
    s.check("S23", bool(find(tree, role="frame", name="Welcome to Star OS")),
            f"its window is 'Welcome to Star OS': {showing_objects(tree)}")
    s.check("S23", bool(find(tree, role=BUTTON, name="Take the tour", showing=True)), "the first page offers 'Take the tour'")
    s.screenshot("S23-welcome")
    focus = s.wait_focus(BUTTON, "Take the tour")
    s.check("S23", focus.get("name") == "Take the tour", f"'Take the tour' has the focus: {json.dumps(focus)}")
    s.keys("ret")
    tree = wait_tree(s, "staros-welcome",
                     lambda t: find(t, name="Everything starts with the Star key", showing=True), 15)
    s.check("S23", bool(find(tree, name="Everything starts with the Star key", showing=True)),
            f"Return turns to the start menu page: {showing_objects(tree)}")
    s.keys("esc")
    report = s.wait_oracle(lambda e: not has_window(e, WELCOME), 20, f"no {WELCOME} window")
    s.check("S23", True, f"Escape skips the tour and closes it: {json.dumps(report)}")
    code, out, _ = s.guest(["/usr/bin/cat", "/home/liveuser/.config/staros-welcomerc"])
    s.check("S23", "Shown=true" in out, f"the tour is marked as seen: {out.strip()!r}")


def scenario_game_center(s):
    launch(s, "game center")
    report = s.wait_oracle(lambda e: is_active(e, GAMES), 45, f"active {GAMES}")
    s.check("S24", True, f"Game Center launched and active per KWin: {json.dumps(report)}")
    tree = wait_tree(s, "staros-games", lambda t: find(t, name="Get games", showing=True), 30)
    with open(os.path.join(s.log_dir, "atspi-games.json"), "w") as f:
        json.dump(tree, f, indent=1)
    for role, name in (("text", "Search games"), (None, "Steam"), (None, "Emulators"), (BUTTON, "Get games"),
                       (None, "No games yet")):
        s.check("S24", bool(find(tree, role=role, name=name, showing=True)),
                f"Game Center shows {name!r}: {showing_objects(tree, 60)}")
    mode = find(tree, name="Game mode", showing=True)
    s.check("S24", bool(mode), f"game mode is offered (gamemoderun is installed): {json.dumps(mode[:1])}")
    focus = s.wait_focus("text", "Search games")
    s.record("S24", "INFO", f"focus: {json.dumps(focus)}")
    s.screenshot("S24-game-center")
    s.keys("alt", "f4")
    s.wait_oracle(lambda e: not has_window(e, GAMES), 20, f"no {GAMES} window")


SCREENSAVER = ["/usr/bin/gdbus", "call", "--session", "--dest", "org.freedesktop.ScreenSaver",
               "--object-path", "/ScreenSaver", "--method"]


def screen_locked(s):
    code, out, err = s.as_user(SCREENSAVER + ["org.freedesktop.ScreenSaver.GetActive"], timeout=30)
    return code == 0 and "true" in out


def wait_locked(s, locked, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if screen_locked(s) == locked:
            return True
        time.sleep(1)
    return False


def scenario_lock_screen(s):
    code, out, err = s.as_user(SCREENSAVER + ["org.freedesktop.ScreenSaver.Lock"], timeout=30)
    s.check("S25", code == 0, f"Lock answered: {(out + err).strip()!r}")
    s.check("S25", wait_locked(s, True, 30), "the screen is locked (ScreenSaver.GetActive)")
    time.sleep(3)
    tree = wait_tree(s, "kscreenlocker_greet", lambda t: find(t, name="Unlock", showing=True), 30)
    with open(os.path.join(s.log_dir, "atspi-lockscreen.json"), "w") as f:
        json.dump(tree, f, indent=1)
    s.record("S25", "INFO", f"lock screen objects: {showing_objects(tree, 40)}")
    code, out, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b -o cat --no-pager -q | grep 'STAROS-LOCK'"
                            " | grep -v guest-exec | tail -n 5"])
    s.record("S25", "INFO", f"lock screen log: {out.strip()!r}")
    # Ours logs 'STAROS-LOCK ready' and names itself 'Screen locked';
    # kscreenlocker's built-in fallback does neither.
    loaded = "STAROS-LOCK ready" in out or bool(find(tree, name="Screen locked"))
    if not loaded:
        _, log, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b -o cat --no-pager -q"
                             " | grep -i -E 'kscreenlocker|lockscreen|greeter|look-and-feel|lookandfeel'"
                             " | grep -v guest-exec | tail -n 20"])
        s.record("S25", "INFO", "journal about the lock screen: " + " | ".join(log.strip().splitlines()))
        # Leave the session usable before failing.
        s.as_user(["/usr/bin/loginctl", "unlock-session"], timeout=30)
    s.check("S25", loaded, "the Star OS lock screen loaded (not the fallback)")
    s.check("S25", bool(find(tree, name="Password", showing=True)) and bool(find(tree, name="Unlock", showing=True)),
            "the lock screen shows 'Password' and 'Unlock'")
    s.screenshot("S25-lock-screen")
    s.keys("ret")
    unlocked = wait_locked(s, False, 30)
    if not unlocked:
        # Leave the session usable for the scenarios after this one.
        s.as_user(["/usr/bin/loginctl", "unlock-session"], timeout=30)
    s.check("S25", unlocked, "Return unlocked the live user")
    s.screenshot("S25-unlocked")


def scenario_logout_screen(s):
    code, out, err = s.as_user(["/usr/bin/gdbus", "call", "--session", "--dest", "org.kde.LogoutPrompt",
                                "--object-path", "/LogoutPrompt", "--method", "org.kde.LogoutPrompt.promptAll"],
                               timeout=30)
    s.check("S26", code == 0, f"promptAll answered: {(out + err).strip()!r}")
    tree = wait_tree(s, "ksmserver-logout-greeter",
                     lambda t: find(t, name="What would you like to do?", showing=True), 30)
    with open(os.path.join(s.log_dir, "atspi-logout.json"), "w") as f:
        json.dump(tree, f, indent=1)
    code, out, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b -o cat --no-pager -q | grep 'STAROS-LOGOUT'"
                            " | grep -v guest-exec | tail -n 3"])
    s.record("S26", "INFO", f"logout screen log: {out.strip()!r}")
    if "STAROS-LOGOUT ready" not in out:
        _, log, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b -o cat --no-pager -q"
                             " | grep -i -E 'logout|greeter|look-and-feel|lookandfeel'"
                             " | grep -v guest-exec | tail -n 20"])
        s.record("S26", "INFO", "journal about the logout screen: " + " | ".join(log.strip().splitlines()))
        s.record("S26", "INFO", f"logout screen objects: {showing_objects(tree, 40)}")
        s.as_user(["/usr/bin/pkill", "-f", "ksmserver-logout-greeter"], timeout=30)
    s.check("S26", "STAROS-LOGOUT ready type=-1" in out, "the Star OS logout screen loaded")
    for name in ("What would you like to do?", "Restart", "Shut down", "Log out", "Cancel"):
        s.check("S26", bool(find(tree, name=name, showing=True)), f"the logout screen shows {name!r}: {showing_objects(tree, 40)}")
    s.screenshot("S26-logout")
    s.keys("esc")
    # The greeter is the D-Bus service org.kde.LogoutPrompt and may outlive
    # its screen: closed means it exited or shows nothing any more.
    closed, how = False, ""
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and not closed:
        time.sleep(1)
        code, _, _ = s.guest(["/usr/bin/pgrep", "-u", "liveuser", "-f", "ksmserver-logout-greeter"])
        if code != 0:
            closed, how = True, "the greeter exited"
            break
        tree = s.atspi("walk", "ksmserver-logout-greeter", "3")
        if "error" not in tree and not find(tree, name="What would you like to do?", showing=True):
            closed, how = True, "the greeter shows nothing"
    if not closed:
        s.as_user(["/usr/bin/pkill", "-f", "ksmserver-logout-greeter"], timeout=30)
    s.check("S26", closed, f"Escape cancelled the logout screen ({how or 'still showing after 20 s'})")


def paste(s):
    code, out, err = s.as_user(["/usr/bin/wl-paste", "--no-newline"], timeout=30)
    return code, out if code == 0 else (out + err).strip()


def wl_copy(s, text):
    """wl-copy forks and serves the copy until it is replaced or killed."""
    return s.as_user(["/usr/bin/sh", "-c", f"/usr/bin/wl-copy {shlex.quote(text)} </dev/null >/dev/null 2>&1"],
                     timeout=30)


def scenario_clipboard(s):
    first, second = "Star clipboard test", "Second copy"
    code, _, err = wl_copy(s, first)
    s.check("S21", code == 0, f"wl-copy ran: {err.strip()!r}")
    time.sleep(2)
    code, out = paste(s)
    s.check("S21", code == 0 and out == first, f"wl-paste reads the copy: {out!r}")
    # The app that owned the copy quits: the shell offers it again.
    s.as_user(["/usr/bin/pkill", "-x", "wl-copy"], timeout=30)
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        time.sleep(1)
        code, out = paste(s)
        if code == 0 and out == first:
            break
    _, log, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b _UID=1000 -o cat --no-pager -q"
                         " | grep STAROS-CLIPBOARD | tail -n 12"])
    s.record("S21", "INFO", "clipboard history log: " + " | ".join(log.strip().splitlines()))
    s.check("S21", code == 0 and out == first, f"after wl-copy exited, wl-paste still reads it: {out!r}")
    wl_copy(s, second)
    time.sleep(2)
    s.keys("meta_l", "v")
    tree = wait_tree(s, "plasmashell", lambda t: find(t, role="frame", name="Clipboard history", showing=True), 20)
    frames = find(tree, role="frame", name="Clipboard history", showing=True)
    s.check("S21", bool(frames), f"Meta+V opens the clipboard history: {showing_objects(tree, 60)}")
    panel = frames[0] if frames else {}
    lists = find(panel, role="list", name="Copies", showing=True)
    # The copies as shown, top to bottom: AT-SPI lists a view's rows in the
    # order they were created, and each row holds a 'Forget this copy' button.
    buttons = [n for n in find(lists[0], role=BUTTON, showing=True)
               if n.get("name") != "Forget this copy" and n.get("extents")] if lists else []
    rows = [n.get("name") for n in sorted(buttons, key=lambda n: n["extents"][1])]
    s.record("S21", "INFO", f"copies: {json.dumps(rows)}")
    s.check("S21", rows[:2] == [second, first], f"newest first: {json.dumps(rows[:2])}")
    s.screenshot("S21-clipboard")
    focus = s.wait_focus(BUTTON, second)
    s.check("S21", focus.get("name") == second, f"the newest copy has the focus: {json.dumps(focus)}")
    s.keys("down")
    focus = s.wait_focus(BUTTON, first)
    s.keys("ret")
    time.sleep(2)
    code, out = paste(s)
    s.check("S21", code == 0 and out == first, f"Return put the older copy back: {out!r}")
    tree = s.atspi("walk", "plasmashell", "30")
    s.check("S21", not find(tree, role="frame", name="Clipboard history", showing=True), "the panel closed")
    s.as_user(["/usr/bin/pkill", "-x", "wl-copy"], timeout=30)


WIDGETS = ("Clock", "Weather", "System", "Calendar")
WIDGETS_FILE = "/home/liveuser/.local/share/staros/widgets.json"


def shown_widgets(tree):
    panes = find(tree, name="Desktop widgets")
    if not panes:
        return []
    # Qt maps Accessible.Grouping to "panel" or "grouping" depending on the
    # version; the widgets are the showing objects with their names.
    names = []
    for node in find(panes[0], showing=True):
        if node.get("name") in WIDGETS and node.get("name") not in names and "check box" not in str(node.get("role")):
            names.append(node.get("name"))
    return names


def scenario_widgets(s):
    tree = wait_tree(s, "plasmashell", lambda t: len(shown_widgets(t)) == 4, 30)
    s.check("S22", shown_widgets(tree) == list(WIDGETS), f"the desktop shows {json.dumps(shown_widgets(tree))}")
    weather = [n for n in find(tree, name="Weather", showing=True) if n.get("description")]
    s.check("S22", bool(weather) and weather[0].get("description") == "Choose a city",
            f"the weather asks for a city first: {json.dumps(weather[:1])[:300]}")
    cpu = [n.get("name") for n in find(tree, showing=True) if str(n.get("name", "")).startswith("Processor: ")]
    s.record("S22", "INFO", f"system widget: {json.dumps(cpu)}")
    s.check("S22", bool(cpu) and cpu[0].endswith("%"), f"the System widget measures the processor: {cpu}")
    clock = [n for n in find(tree, name="Clock", showing=True) if n.get("description")]
    s.record("S22", "INFO", f"clock: {clock[0].get('description') if clock else None!r}")
    s.screenshot("S22-widgets")
    hidden = '{"version": 1, "shown": {"calendar": false}}'
    s.as_user(["/usr/bin/sh", "-c", f"mkdir -p $(dirname {WIDGETS_FILE}) && printf '%s' {shlex.quote(hidden)} > {WIDGETS_FILE}"],
              timeout=30)
    tree = wait_tree(s, "plasmashell", lambda t: "Calendar" not in shown_widgets(t), 20)
    s.check("S22", shown_widgets(tree) == ["Clock", "Weather", "System"],
            f"hiding the calendar in widgets.json hides it: {json.dumps(shown_widgets(tree))}")
    s.as_user(["/usr/bin/rm", "-f", WIDGETS_FILE], timeout=30)
    tree = wait_tree(s, "plasmashell", lambda t: len(shown_widgets(t)) == 4, 20)
    s.check("S22", len(shown_widgets(tree)) == 4, "removing the file shows every widget again")
    code, out, _ = s.guest(["/usr/bin/sh", "-c", "journalctl -b -o cat --no-pager -q | grep -ci open-meteo || true"])
    s.record("S22", "INFO", f"journal lines naming open-meteo: {out.strip()}")


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
        s.start(os.path.abspath(args.iso), extra=AUDIO_ARGS)
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
