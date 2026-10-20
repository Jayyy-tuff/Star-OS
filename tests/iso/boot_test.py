#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Boots a Star OS ISO in QEMU and waits for the live boot report.

The ISO is attached as a read-only CD-ROM and no disk images are attached, so
this test cannot modify any disk. Inside the live system, staros-boot-check
writes a report line and a marker to the first serial port; QEMU saves the
serial output to a log file, which this script reads.

With --session (M0.2) it also waits for staros-session-report's verdict on the
graphical session and checks its facts, saves a screen dump as PNG and logs
the taskbar band; with --wait-idle it waits for the idle report and the
stability verdict as well.

Writes serial-<firmware>.log, qemu-<firmware>.log and result-<firmware>.json to
the log directory, plus session-<firmware>.png with --session, and
screen-<firmware>.ppm when a check fails while QEMU is still running.

Exit status: 0 passed, 1 failed, 2 usage or environment error.
"""

import argparse
import json
import os
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import time

import screen

MARKER = "STAROS-LIVE-BOOT-OK"
REPORT_PREFIX = "STAROS-BOOT-CHECK "
SESSION_CHECK = "STAROS-SESSION-CHECK "
EXPECTED_SHELL = "org.staros.shell"
FORBIDDEN_ENV_LIST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                  "..", "..", "scripts", "ci", "forbidden-env.txt")

# QEMU machine profiles. 'minimal' is the M0.1 boot test; 'graphical' runs the
# M0.2 session on a 1920x1080 standard VGA (bochs-drm in the guest).
PROFILES = {
    "minimal": {"memory": 2048, "smp": 2, "display": ["-vga", "std"]},
    "graphical": {"memory": 4096, "smp": 4,
                  "display": ["-vga", "none", "-device", "VGA,xres=1920,yres=1080,vgamem_mb=32"]},
}

# (code, vars) firmware image pairs: Debian/Ubuntu, Arch, Fedora.
OVMF_CANDIDATES = (
    ("/usr/share/OVMF/OVMF_CODE_4M.fd", "/usr/share/OVMF/OVMF_VARS_4M.fd"),
    ("/usr/share/OVMF/OVMF_CODE.fd", "/usr/share/OVMF/OVMF_VARS.fd"),
    ("/usr/share/edk2/x64/OVMF_CODE.4m.fd", "/usr/share/edk2/x64/OVMF_VARS.4m.fd"),
    ("/usr/share/edk2/ovmf/OVMF_CODE.fd", "/usr/share/edk2/ovmf/OVMF_VARS.fd"),
)


class SetupError(Exception):
    """The test could not run; this says nothing about the ISO."""


def parse_boot_report(text):
    """Returns the fields of the last boot report followed by the marker, or None."""
    report = None
    for line in text.splitlines():
        start = line.find(REPORT_PREFIX)
        if start >= 0:
            report = {}
            for item in line[start + len(REPORT_PREFIX):].split():
                key, sep, value = item.partition("=")
                if sep:
                    report[key] = value
        elif MARKER in line and report is not None:
            return report
    return None


def check_report(report, expected_id, expected_firmware):
    """Returns a list of problems with a boot report; empty means it passed."""
    if report is None:
        return [f"boot marker {MARKER} was not seen on the serial console"]
    problems = []
    if report.get("id") != expected_id:
        problems.append(f"id is {report.get('id')!r}, expected {expected_id!r}")
    if report.get("firmware") != expected_firmware:
        problems.append(
            f"booted with firmware {report.get('firmware')!r}, expected {expected_firmware!r}")
    return problems


def find_ovmf(candidates=OVMF_CANDIDATES, exists=os.path.isfile):
    """Returns the first (code, vars) pair whose files both exist, or None."""
    for code, variables in candidates:
        if exists(code) and exists(variables):
            return code, variables
    return None


def read_forbidden_env(path=FORBIDDEN_ENV_LIST):
    """Returns the banned environment variable names (scripts/ci/forbidden-env.txt)."""
    with open(path) as f:
        return {line.strip() for line in f if line.strip() and not line.startswith("#")}


def parse_fields(text):
    fields = {}
    for item in text.split():
        key, sep, value = item.partition("=")
        if sep:
            fields[key] = value
    return fields


def parse_session(text):
    """Returns what staros-session-report printed so far, as a dict."""
    session = {"check": None, "status": None, "reason": None, "shell_log": None,
               "idle": None, "idle_error": None, "stable": None, "stable_status": None}
    for line in text.splitlines():
        line = line.strip("\r\x00")
        if (start := line.find(SESSION_CHECK)) >= 0:
            session["check"] = parse_fields(line[start + len(SESSION_CHECK):])
        elif "STAROS-SESSION-OK" in line:
            session["status"] = "ok"
        elif (start := line.find("STAROS-SESSION-FAIL")) >= 0:
            session["status"] = "fail"
            session["reason"] = line[start:].partition("reason=")[2] or "unknown"
        elif (start := line.find("STAROS-SESSION-SHELL-LOG ")) >= 0:
            session["shell_log"] = line[start + len("STAROS-SESSION-SHELL-LOG "):]
        elif (start := line.find("STAROS-IDLE-REPORT ")) >= 0:
            try:
                session["idle"] = json.loads(line[start + len("STAROS-IDLE-REPORT "):])
            except ValueError as err:
                session["idle_error"] = f"unreadable idle report: {err}"
        elif (start := line.find("STAROS-SESSION-STABLE")) >= 0:
            session["stable_status"] = "stable"
            session["stable"] = parse_fields(line[start:])
        elif (start := line.find("STAROS-SESSION-UNSTABLE")) >= 0:
            session["stable_status"] = "unstable"
            before, _, reason = line[start:].partition("reason=")
            session["stable"] = parse_fields(before)
            session["stable"]["reason"] = reason
    return session


def layout_problems(layout):
    problems = []
    panels = [p for p in layout.get("panels", []) if p.get("type") == "org.staros.taskbar"]
    if len(panels) != 1:
        problems.append(f"expected one org.staros.taskbar panel, found {len(panels)}")
    elif panels[0].get("location") != "bottom" or panels[0].get("floating") is not False:
        problems.append(f"taskbar panel is not bottom and non-floating: {panels[0]}")
    desktops = layout.get("desktops", [])
    if not desktops:
        problems.append("no desktop containment")
    for desktop in desktops:
        if desktop.get("type") != "org.staros.desktop" or desktop.get("wallpaper") != "org.kde.color":
            problems.append(f"unexpected desktop containment: {desktop}")
    return problems


def check_session(session, forbidden):
    """Returns a list of problems with the session report; empty means it passed."""
    if session["status"] is None:
        return ["no STAROS-SESSION-OK or STAROS-SESSION-FAIL on the serial console"]
    problems = []
    if session["status"] == "fail":
        problems.append(f"session report failed: {session['reason']}")
    check = session["check"]
    if check is None:
        return problems + ["no STAROS-SESSION-CHECK line"]
    expected = {
        "user": "liveuser",
        "logind_type": "wayland",
        "seat": "seat0",
        "shell": EXPECTED_SHELL,
        "grant": "ok",
        "shellrc_override": "none",
        "plasma_default_shell": EXPECTED_SHELL,
    }
    for key, want in expected.items():
        if check.get(key) != want:
            problems.append(f"{key} is {check.get(key)!r}, expected {want!r}")
    for key in ("env_kwin", "env_plasmashell"):
        names = set(check.get(key, "").split(",")) & forbidden
        if names:
            problems.append(f"{key} contains forbidden variables: {', '.join(sorted(names))}")
    try:
        layout = json.loads(check.get("layout", "null"))
    except ValueError:
        layout = None
    if not isinstance(layout, dict):
        problems.append("the layout is missing or unreadable")
    else:
        problems.extend(layout_problems(layout))
    return problems


def check_idle(session):
    """Returns a list of problems with the idle and stability phases."""
    problems = []
    if session["idle_error"]:
        problems.append(session["idle_error"])
    elif session["idle"] is None:
        problems.append("no STAROS-IDLE-REPORT on the serial console")
    elif not isinstance(session["idle"].get("session_pss_mib"), (int, float)):
        problems.append("the idle report has no session_pss_mib")
    if session["stable_status"] is None:
        problems.append("no STAROS-SESSION-STABLE or STAROS-SESSION-UNSTABLE")
    elif session["stable_status"] == "unstable":
        problems.append(f"session unstable: {session['stable'].get('reason')}")
    return problems


def build_qemu_command(qemu, iso, firmware, accel, memory_mib, serial_log, qmp_socket,
                       ovmf_code=None, ovmf_vars=None, profile="minimal"):
    """Returns the QEMU argument list. The only drives are the ISO and firmware."""
    for path in (iso, serial_log, qmp_socket, ovmf_code, ovmf_vars):
        if path is not None and "," in path:
            raise SetupError(f"QEMU cannot take paths containing ',': {path}")
    machine = PROFILES[profile]
    cmd = [qemu, "-machine", "q35", "-m", str(memory_mib), "-smp", str(machine["smp"])]
    if accel == "kvm":
        cmd += ["-accel", "kvm", "-cpu", "host"]
    else:
        cmd += ["-accel", "tcg", "-cpu", "max"]
    if firmware == "uefi":
        if not (ovmf_code and ovmf_vars):
            raise SetupError("UEFI boot needs OVMF code and vars images")
        cmd += [
            "-drive", f"if=pflash,format=raw,unit=0,readonly=on,file={ovmf_code}",
            "-drive", f"if=pflash,format=raw,unit=1,file={ovmf_vars}",
        ]
    cmd += [
        "-cdrom", iso,
        "-boot", "order=d",
        "-display", "none",
        *machine["display"],
        "-nic", "user,model=virtio-net-pci,restrict=on",
        "-serial", f"file:{serial_log}",
        "-qmp", f"unix:{qmp_socket},server=on,wait=off",
        "-no-reboot",
    ]
    return cmd


def qmp_execute(socket_path, command, arguments=None, timeout=10.0):
    """Runs one QMP command and returns QEMU's reply."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        sock.connect(socket_path)
        reader = sock.makefile("rb")

        def reply():
            while True:
                line = reader.readline()
                if not line:
                    raise SetupError("QMP connection closed")
                message = json.loads(line)
                if "return" in message or "error" in message:
                    return message

        reader.readline()  # greeting
        sock.sendall(b'{"execute": "qmp_capabilities"}\n')
        reply()
        request = {"execute": command}
        if arguments:
            request["arguments"] = arguments
        sock.sendall(json.dumps(request).encode() + b"\n")
        return reply()


def stop_qemu(proc, qmp_socket):
    if proc.poll() is not None:
        return
    try:
        qmp_execute(qmp_socket, "quit", timeout=5)
        proc.wait(timeout=10)
    except (OSError, SetupError, ValueError, subprocess.TimeoutExpired):
        proc.kill()
        proc.wait()


def read_text(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", "replace")
    except FileNotFoundError:
        return ""


def qemu_version(qemu):
    out = subprocess.run([qemu, "--version"], capture_output=True, text=True, check=False)
    return out.stdout.splitlines()[0] if out.stdout else "unknown"


def wait_for(serial_log, proc, deadline, done, what):
    """Polls the serial log until done(text) is true; returns (text, reason)."""
    while True:
        text = read_text(serial_log)
        if done(text):
            return text, None
        if proc.poll() is not None:
            return text, f"QEMU exited with status {proc.returncode} before {what}"
        if time.monotonic() > deadline:
            return text, f"timed out without {what}"
        time.sleep(1)


def take_screen(qmp_socket, ppm_path, png_path):
    """Saves a screen dump as PNG and returns screen.analyse() facts, or None."""
    try:
        qmp_execute(qmp_socket, "screendump", {"filename": ppm_path})
        for _ in range(20):  # allow for a slow write
            if os.path.exists(ppm_path) and os.path.getsize(ppm_path) > 0:
                break
            time.sleep(0.5)
        with open(ppm_path, "rb") as f:
            image = screen.parse_ppm(f.read())
        with open(png_path, "wb") as f:
            f.write(screen.png_bytes(image))
        os.remove(ppm_path)
        return screen.analyse(image)
    except (OSError, SetupError, ValueError) as err:
        print(f"warning: screen dump failed: {err}", file=sys.stderr)
        return None


def run(args):
    iso = os.path.abspath(args.iso)
    if not os.path.isfile(iso):
        raise SetupError(f"ISO not found: {iso}")
    qemu = shutil.which(args.qemu)
    if qemu is None:
        raise SetupError(f"{args.qemu} not found")
    kvm = os.access("/dev/kvm", os.R_OK | os.W_OK)
    if args.require_kvm and not kvm:
        raise SetupError("/dev/kvm is not usable and --require-kvm was given")
    accel = "kvm" if kvm else "tcg"
    if not kvm:
        print("warning: no usable /dev/kvm; using slow software emulation", file=sys.stderr)
    forbidden = read_forbidden_env() if args.session else set()
    memory = args.memory or PROFILES[args.profile]["memory"]

    log_dir = os.path.abspath(args.log_dir)
    os.makedirs(log_dir, exist_ok=True)
    fw = args.firmware
    serial_log = os.path.join(log_dir, f"serial-{fw}.log")
    qemu_log = os.path.join(log_dir, f"qemu-{fw}.log")
    screen_ppm = os.path.join(log_dir, f"screen-{fw}.ppm")
    session_png = os.path.join(log_dir, f"session-{fw}.png")
    for stale in (serial_log, qemu_log, screen_ppm, session_png):
        if os.path.exists(stale):
            os.remove(stale)

    ovmf_code = ovmf_vars = None
    if fw == "uefi":
        pair = (args.ovmf_code, args.ovmf_vars) if args.ovmf_code else find_ovmf()
        if pair is None or not all(pair):
            raise SetupError("OVMF firmware not found; install it or pass --ovmf-code/--ovmf-vars")
        ovmf_code = pair[0]
        ovmf_vars = os.path.join(log_dir, f"ovmf-vars-{fw}.fd")
        shutil.copyfile(pair[1], ovmf_vars)

    qmp_dir = tempfile.mkdtemp(prefix="staros-qmp-")
    qmp_socket = os.path.join(qmp_dir, "qmp.sock")
    cmd = build_qemu_command(qemu, iso, fw, accel, memory, serial_log, qmp_socket,
                             ovmf_code, ovmf_vars, args.profile)
    print("+ " + shlex.join(cmd), flush=True)

    report = session = screen_facts = None
    seconds = {}
    problems = []
    start = time.monotonic()
    with open(qemu_log, "wb") as qemu_out:
        proc = subprocess.Popen(cmd, stdout=qemu_out, stderr=subprocess.STDOUT)
    try:
        _, reason = wait_for(serial_log, proc, start + args.timeout,
                             lambda text: parse_boot_report(text) is not None,
                             "the boot marker")
        report = parse_boot_report(read_text(serial_log))
        problems = check_report(report, args.expect_id, fw) if report else [reason]
        if report:
            seconds["marker"] = round(time.monotonic() - start, 1)

        if not problems and args.session:
            _, reason = wait_for(serial_log, proc, start + args.session_timeout,
                                 lambda text: parse_session(text)["status"] is not None,
                                 "the session verdict")
            session = parse_session(read_text(serial_log))
            problems = [reason] if reason else check_session(session, forbidden)
            if session["status"] == "ok":
                seconds["session_ok"] = round(time.monotonic() - start, 1)
                time.sleep(args.screen_delay)
                screen_facts = take_screen(qmp_socket, screen_ppm, session_png)
                if screen_facts:
                    # Informational until promoted (docs/development/test-plan.md).
                    print("SCREEN " + " ".join(f"{k}={v}" for k, v in screen_facts.items()),
                          flush=True)

        if not problems and args.wait_idle:
            _, reason = wait_for(serial_log, proc, start + args.idle_timeout,
                                 lambda text: parse_session(text)["stable_status"] is not None,
                                 "the stability verdict")
            session = parse_session(read_text(serial_log))
            problems = check_idle(session)
            if reason and session["stable_status"] is None:
                problems.append(reason)

        if problems and proc.poll() is None:
            try:
                qmp_execute(qmp_socket, "screendump", {"filename": screen_ppm})
            except (OSError, SetupError, ValueError) as err:
                print(f"warning: screendump failed: {err}", file=sys.stderr)
    finally:
        stop_qemu(proc, qmp_socket)
        shutil.rmtree(qmp_dir, ignore_errors=True)

    result = {
        "iso": os.path.basename(iso),
        "iso_bytes": os.path.getsize(iso),
        "firmware": fw,
        "profile": args.profile,
        "memory_mib": memory,
        "smp": PROFILES[args.profile]["smp"],
        "accel": accel,
        "qemu": qemu_version(qemu),
        "passed": not problems,
        "problems": problems,
        "report": report,
        "session": session,
        "screen": screen_facts,
        # Times from QEMU start, in CI. Not a performance claim.
        "seconds": seconds,
        "seconds_to_marker": seconds.get("marker"),
    }
    with open(os.path.join(log_dir, f"result-{fw}.json"), "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    print(json.dumps(result, indent=2))
    return 0 if not problems else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--iso", required=True, help="ISO image to boot")
    parser.add_argument("--firmware", choices=("uefi", "bios"), required=True)
    parser.add_argument("--timeout", type=int, default=300, help="seconds to wait for the marker")
    parser.add_argument("--log-dir", default="boot-logs")
    parser.add_argument("--profile", choices=sorted(PROFILES), default="minimal",
                        help="QEMU machine profile (graphical: 4 vCPU, 4 GiB, 1920x1080 VGA)")
    parser.add_argument("--memory", type=int, help="guest RAM in MiB (default: from the profile)")
    parser.add_argument("--session", action="store_true",
                        help="also wait for and check the M0.2 session report")
    parser.add_argument("--session-timeout", type=int, default=480,
                        help="seconds from QEMU start to wait for the session verdict")
    parser.add_argument("--screen-delay", type=int, default=20,
                        help="seconds between the session verdict and the screen dump")
    parser.add_argument("--wait-idle", action="store_true",
                        help="also wait for the idle report and the stability verdict")
    parser.add_argument("--idle-timeout", type=int, default=1080,
                        help="seconds from QEMU start to wait for the stability verdict")
    parser.add_argument("--expect-id", default="staros", help="expected ID in /etc/staros-release")
    parser.add_argument("--require-kvm", action="store_true",
                        help="fail instead of falling back to software emulation")
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--ovmf-code")
    parser.add_argument("--ovmf-vars")
    args = parser.parse_args(argv)
    if bool(args.ovmf_code) != bool(args.ovmf_vars):
        parser.error("--ovmf-code and --ovmf-vars must be given together")
    if args.wait_idle and not args.session:
        parser.error("--wait-idle needs --session")
    try:
        return run(args)
    except SetupError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
