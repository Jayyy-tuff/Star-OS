#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Star Storage end to end on the CI-built ISO (M0.4, ADR-0011), UEFI only.

A 10 GiB scratch image (a file on the runner; never a real disk) is a second
virtio disk. Three boots share it and the OVMF variables file:

  B1 live session: the helper lists the scratch disk as usable; Star Storage
     is opened from the launcher and used by keyboard as a person would:
     the disk is selected, its name typed, "Erase and set up" run (pkexec,
     the live polkit rule, the helper), then "Restart into Star Storage"
     sets systemd-boot's one-shot entry and restarts (QEMU exits: -no-reboot).
  B2 the one-shot entry: cow_label=STAROS_DATA on the kernel command line,
     the copy-on-write space is the scratch disk's ext4 partition, the
     taskbar's System status says "Star Storage"; a marker file is written
     in liveuser's home; "Always start with Star Storage" is switched on in
     the app; the guest powers off.
  B3 systemd-boot's default is now Star Storage: the marker is still there.

Prints 'EVIDENCE <step> PASS|FAIL|INFO <detail>' lines and writes
storage-result.json. Exit status: 0 passed, 1 a check failed, 2 setup error.
"""

import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "session"))
sys.path.insert(0, os.path.join(HERE, "..", "iso"))

import boot_test  # noqa: E402
import qga  # noqa: E402
import session_test  # noqa: E402
from session_test import BUTTON, CheckFailed, find, named_objects, wait_tree  # noqa: E402

HELPER = "/usr/lib/staros/staros-storage-helper"
SCRATCH_BYTES = 10 * 1024 ** 3
MARKER = "/home/liveuser/staros-storage-marker.txt"
MARKER_TEXT = "kept by Star Storage"
STORAGE_PARAM = "cow_label=STAROS_DATA"
STORAGE = "org.staros.storage"


def scratch_args(disk):
    """QEMU arguments for the scratch image as a virtio disk."""
    if "," in disk:
        raise boot_test.SetupError(f"QEMU cannot take paths containing ',': {disk}")
    return ["-drive", f"if=virtio,format=raw,file={disk}"]


def boot(s, iso, name, vars_file, disk):
    """Starts QEMU and waits for the session, the guest agent and helpers."""
    s.start(iso, name=name, vars_file=vars_file, extra=scratch_args(disk))
    session = s.wait_session_ok()
    problems = boot_test.check_session(session, boot_test.read_forbidden_env())
    s.check(name, not problems, "session report: " + ("; ".join(problems) or "ok"))
    err = s.connect_agent()
    s.check(name, err is None, f"guest agent answers{'' if err is None else f': {err}'}")
    script_id, err = s.install_helpers()
    s.check(name, script_id not in (None, "-1"), f"KWin oracle loaded (id {script_id}) {err}")
    s.atspi("enable")
    code, out, _ = s.guest(["/usr/bin/cat", "/proc/cmdline"])
    s.record(name, "INFO", f"kernel command line: {out.strip()}")
    return out.split()


def scratch_disk(s, name):
    """The helper's view of the scratch disk, run as liveuser."""
    code, out, err = s.as_user([HELPER, "list"], timeout=60)
    listed = json.loads(out[out.find("{"):]) if "{" in out else {}
    disks = [d for d in listed.get("disks", []) if d.get("size") == SCRATCH_BYTES]
    s.check(name, code == 0 and len(disks) == 1,
            f"the helper lists one {SCRATCH_BYTES}-byte disk: exit {code}, {out.strip()[:600]} {err.strip()}")
    return listed, disks[0]


def open_star_storage(s, name):
    """Starts Star Storage from the launcher and waits for its disk list."""
    session_test.launch(s, "star stor")
    report = s.wait_oracle(lambda e: session_test.is_active(e, STORAGE), 45, f"active {STORAGE}")
    s.check(name, True, f"Star Storage active per KWin: {json.dumps(report)}")
    tree = wait_tree(s, "staros-storage", lambda t: find(t, role="list", name="Disks")
                     and not find(t, name="Looking for disks…"), 60)
    with open(os.path.join(s.log_dir, f"atspi-storage-{name}.json"), "w") as f:
        json.dump(tree, f, indent=1)
    s.check(name, bool(find(tree, role="list", name="Disks")),
            f"Star Storage shows its 'Disks' list: {named_objects(tree, 60)}")
    return tree


def focus_by_tab(s, role, name, keys=("tab",), tries=6):
    """Presses KEYS until ROLE NAME has the focus; returns the focus."""
    focus = {}
    for _ in range(tries):
        focus = s.wait_focus(role, name, seconds=2)
        if focus.get("name") == name:
            return focus
        s.keys(*keys)
    return s.wait_focus(role, name, seconds=3)


def wait_qemu_exit(s, seconds):
    try:
        s.proc.wait(timeout=seconds)
        return True
    except subprocess.TimeoutExpired:
        return False


def boot1(s, iso, vars_file, disk):
    args = boot(s, iso, "B1", vars_file, disk)
    s.check("B1", STORAGE_PARAM not in args, "the first start is the live session (no cow_label)")
    listed, scratch = scratch_disk(s, "B1")
    s.check("B1", scratch["usable"] and not scratch["starStorage"],
            f"the scratch disk {scratch['name']} can be used: {json.dumps(scratch)}")
    s.record("B1", "INFO", f"uefi={listed.get('uefi')} systemdBoot={listed.get('systemdBoot')} "
             f"always={listed.get('always')}")

    open_star_storage(s, "B1")
    s.screenshot("B1-storage")
    # The list has the focus and its first (only) disk selected; the field
    # for the typed name follows it.
    focus = focus_by_tab(s, "text", "Disk name to confirm")
    s.check("B1", focus.get("name") == "Disk name to confirm",
            f"Tab reaches 'Disk name to confirm': {json.dumps(focus)}")
    s.type_text(scratch["name"])
    s.keys("ret")
    ready = f"Star Storage is ready on /dev/{scratch['name']}1."
    tree = wait_tree(s, "staros-storage", lambda t: find(t, name=ready) or any(
        str(n.get("name") or "").startswith("Star Storage was not set up.") for n in find(t)), 240)
    s.screenshot("B1-storage-done")
    s.check("B1", bool(find(tree, name=ready)),
            f"Erase and set up says {ready!r}: {named_objects(tree, 60)}")
    code, out, _ = s.guest(["/usr/bin/blkid", "-p", "-o", "export", f"/dev/{scratch['name']}1"])
    s.check("B1", code == 0 and "LABEL=STAROS_DATA" in out and "TYPE=ext4" in out,
            f"/dev/{scratch['name']}1 is ext4 labelled STAROS_DATA: {' '.join(out.split())}")

    focus = s.wait_focus(BUTTON, "Restart into Star Storage", seconds=10)
    s.check("B1", focus.get("name") == "Restart into Star Storage",
            f"'Restart into Star Storage' has the focus: {json.dumps(focus)}")
    s.keys("ret")
    s.check("B1", wait_qemu_exit(s, 180), "the guest restarted (QEMU exited, -no-reboot)")
    return scratch["name"]


def boot2(s, iso, vars_file, disk, name):
    args = boot(s, iso, "B2", vars_file, disk)
    s.check("B2", STORAGE_PARAM in args, f"the one-shot entry started Star Storage ({STORAGE_PARAM})")
    code, out, _ = s.guest(["/usr/bin/findmnt", "-n", "-o", "SOURCE,FSTYPE", "/run/archiso/cowspace"])
    s.check("B2", out.split() == [f"/dev/{name}1", "ext4"],
            f"the copy-on-write space is /dev/{name}1 (ext4): {out.strip()!r}")
    tree = wait_tree(s, "plasmashell", lambda t: find(t, role=BUTTON, name="System status"), 60)
    meters = find(tree, role=BUTTON, name="System status")
    detail = meters[0].get("description", "") if meters else ""
    s.check("B2", detail.startswith("Star Storage: "), f"'System status' says: {detail!r}")

    s.guest(["/usr/bin/sh", "-c", f"printf '%s\\n' '{MARKER_TEXT}' >{MARKER} && chown liveuser: {MARKER} && sync"])
    code, out, _ = s.guest(["/usr/bin/cat", MARKER])
    s.check("B2", out.strip() == MARKER_TEXT, f"marker written: {out.strip()!r}")

    open_star_storage(s, "B2")
    # From the disk list, Shift+Tab reaches the switch above it.
    focus = focus_by_tab(s, "check box", "Always start with Star Storage", keys=("shift", "tab"))
    s.check("B2", focus.get("name") == "Always start with Star Storage",
            f"Shift+Tab reaches 'Always start with Star Storage': {json.dumps(focus)}")
    s.keys("spc")
    done = "Star OS now starts with Star Storage every time."
    tree = wait_tree(s, "staros-storage", lambda t: find(t, name=done) or any(
        str(n.get("name") or "").startswith("The start was not changed.") for n in find(t)), 60)
    s.screenshot("B2-storage-always")
    s.check("B2", bool(find(tree, name=done)), f"the app says {done!r}: {named_objects(tree, 60)}")
    listed, scratch = scratch_disk(s, "B2")
    s.record("B2", "INFO", f"helper list: always={listed.get('always')} reason={scratch.get('reason')}")
    s.guest(["/usr/bin/systemctl", "poweroff"], wait=False)
    s.check("B2", wait_qemu_exit(s, 180), "the guest powered off")


def boot3(s, iso, vars_file, disk, name):
    args = boot(s, iso, "B3", vars_file, disk)
    s.check("B3", STORAGE_PARAM in args, f"the default entry is now Star Storage ({STORAGE_PARAM})")
    code, out, _ = s.guest(["/usr/bin/cat", MARKER])
    s.check("B3", code == 0 and out.strip() == MARKER_TEXT,
            f"the marker from the previous start is still there: {out.strip()!r}")
    code, out, _ = s.guest(["/usr/bin/findmnt", "-n", "-o", "SOURCE", "/run/archiso/cowspace"])
    s.record("B3", "INFO", f"copy-on-write space: {out.strip()}")
    s.screenshot("B3-desktop")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--iso", required=True)
    parser.add_argument("--log-dir", default="storage-logs")
    parser.add_argument("--qemu", default="qemu-system-x86_64")
    parser.add_argument("--session-timeout", type=int, default=480)
    args = parser.parse_args(argv)

    log_dir = os.path.abspath(args.log_dir)
    os.makedirs(log_dir, exist_ok=True)
    iso = os.path.abspath(args.iso)
    disk = os.path.join(log_dir, "scratch.img")
    vars_file = os.path.join(log_dir, "ovmf-vars-storage.fd")
    s = session_test.Session(args, log_dir)
    status = 0
    error = None
    try:
        pair = boot_test.find_ovmf()
        if pair is None:
            raise boot_test.SetupError("OVMF firmware not found")
        with open(pair[1], "rb") as src, open(vars_file, "wb") as dst:
            dst.write(src.read())
        with open(disk, "wb") as f:
            f.truncate(SCRATCH_BYTES)  # sparse
        name = boot1(s, iso, vars_file, disk)
        s.stop()
        boot2(s, iso, vars_file, disk, name)
        s.stop()
        boot3(s, iso, vars_file, disk, name)
    except CheckFailed as err:
        error = str(err)
    except (boot_test.SetupError, qga.GuestAgentError, OSError, ValueError) as err:
        error = f"setup: {err}"
        status = 2
    finally:
        if (s.failed or error) and s.proc and s.proc.poll() is None:
            try:
                if s.agent:
                    s.record("debug", "INFO", "shell log: " + " | ".join(s.journal_shell()[-20:]))
                    code, out, _ = s.guest(["/usr/bin/journalctl", "-b", "-o", "cat", "--no-pager",
                                            "-q", "-t", "pkexec", "-t", "polkitd"], timeout=60)
                    s.record("debug", "INFO", "polkit: " + " | ".join(out.splitlines()[-20:]))
                s.screenshot("failure")
            except Exception as err:  # diagnostics must not hide the failure
                print(f"warning: diagnostics failed: {err}", file=sys.stderr)
        s.stop()
        if os.path.exists(disk):
            os.remove(disk)
    if s.failed and status == 0:
        status = 1
    result = {"passed": status == 0, "error": error, "evidence": s.evidence}
    with open(os.path.join(log_dir, "storage-result.json"), "w") as f:
        json.dump(result, f, indent=2)
    if error:
        print(f"error: {error}", file=sys.stderr)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("### Star Storage test (QEMU/KVM, UEFI, scratch image)\n\n"
                    "| Step | Status | Detail |\n|---|---|---|\n")
            for e in s.evidence:
                f.write(f"| {e['scenario']} | {e['status']} | {e['detail'][:200].replace('|', '/')} |\n")
    return status


if __name__ == "__main__":
    sys.exit(main())
