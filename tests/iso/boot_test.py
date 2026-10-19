#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Boots a Star OS ISO in QEMU and waits for the live boot report.

The ISO is attached as a read-only CD-ROM and no disk images are attached, so
this test cannot modify any disk. Inside the live system, staros-boot-check
writes a report line and a marker to the first serial port; QEMU saves the
serial output to a log file, which this script reads.

Writes serial-<firmware>.log, qemu-<firmware>.log and result-<firmware>.json to
the log directory, plus screen-<firmware>.ppm when a boot fails while QEMU is
still running.

Exit status: 0 boot passed, 1 boot failed, 2 usage or environment error.
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

MARKER = "STAROS-LIVE-BOOT-OK"
REPORT_PREFIX = "STAROS-BOOT-CHECK "

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


def build_qemu_command(qemu, iso, firmware, accel, memory_mib, serial_log, qmp_socket,
                       ovmf_code=None, ovmf_vars=None):
    """Returns the QEMU argument list. The only drives are the ISO and firmware."""
    for path in (iso, serial_log, qmp_socket, ovmf_code, ovmf_vars):
        if path is not None and "," in path:
            raise SetupError(f"QEMU cannot take paths containing ',': {path}")
    cmd = [qemu, "-machine", "q35", "-m", str(memory_mib), "-smp", "2"]
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
        "-vga", "std",
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

    log_dir = os.path.abspath(args.log_dir)
    os.makedirs(log_dir, exist_ok=True)
    fw = args.firmware
    serial_log = os.path.join(log_dir, f"serial-{fw}.log")
    qemu_log = os.path.join(log_dir, f"qemu-{fw}.log")
    screen = os.path.join(log_dir, f"screen-{fw}.ppm")
    for stale in (serial_log, qemu_log, screen):
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
    cmd = build_qemu_command(qemu, iso, fw, accel, args.memory, serial_log, qmp_socket,
                             ovmf_code, ovmf_vars)
    print("+ " + shlex.join(cmd), flush=True)

    report = None
    reason = None
    start = time.monotonic()
    with open(qemu_log, "wb") as qemu_out:
        proc = subprocess.Popen(cmd, stdout=qemu_out, stderr=subprocess.STDOUT)
    try:
        while True:
            report = parse_boot_report(read_text(serial_log))
            if report is not None:
                break
            if proc.poll() is not None:
                reason = f"QEMU exited with status {proc.returncode} before the boot marker"
                break
            if time.monotonic() - start > args.timeout:
                reason = f"timed out after {args.timeout} s without the boot marker"
                break
            time.sleep(1)
        elapsed = round(time.monotonic() - start, 1)
        problems = check_report(report, args.expect_id, fw) if report else [reason]
        if problems and proc.poll() is None:
            try:
                qmp_execute(qmp_socket, "screendump", {"filename": screen})
            except (OSError, SetupError, ValueError) as err:
                print(f"warning: screendump failed: {err}", file=sys.stderr)
    finally:
        stop_qemu(proc, qmp_socket)
        shutil.rmtree(qmp_dir, ignore_errors=True)

    result = {
        "iso": os.path.basename(iso),
        "iso_bytes": os.path.getsize(iso),
        "firmware": fw,
        "accel": accel,
        "qemu": qemu_version(qemu),
        "passed": not problems,
        "problems": problems,
        "report": report,
        # Time from QEMU start to the marker, in CI. Not a performance claim.
        "seconds_to_marker": elapsed if report else None,
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
    parser.add_argument("--memory", type=int, default=2048, help="guest RAM in MiB")
    parser.add_argument("--expect-id", default="staros", help="expected ID in /etc/staros-release")
    parser.add_argument("--require-kvm", action="store_true",
                        help="fail instead of falling back to software emulation")
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--ovmf-code")
    parser.add_argument("--ovmf-vars")
    args = parser.parse_args(argv)
    if bool(args.ovmf_code) != bool(args.ovmf_vars):
        parser.error("--ovmf-code and --ovmf-vars must be given together")
    try:
        return run(args)
    except SetupError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
