#!/usr/bin/python3 -I
"""Herd advisories (updateinfo) for the signed update repository.

Called by publish-repo.sh; not run directly in normal use.

  herd-updateinfo.py new ADVISORY_DIR --id ID --type TYPE --severity SEV
                     --title TITLE [--description TEXT] [--cve CVE ...] RPM...
      Writes ADVISORY_DIR/ID.xml: one <update> for the given RPMs, read from
      their headers (name, epoch, version, release, arch, file name). Refuses
      to overwrite an existing file.

  herd-updateinfo.py build ADVISORY_DIR PACKAGE_DIR OUTPUT
      Writes OUTPUT (updateinfo.xml) with every advisory whose packages are
      ALL present in PACKAGE_DIR with the same NEVRA and file name, and prints
      their number on stdout (0: nothing written). The attached and skipped
      IDs go to stderr. Stops with an error when an advisory is malformed, or
      when it names a file of PACKAGE_DIR with a different NEVRA, or when
      only some of its packages are present.

Each <update> written to OUTPUT is rebuilt from the validated fields of the
advisory file, never copied as it is.
"""
import argparse
import datetime
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ID_RE = re.compile(r"^HERD-[0-9]{4}-[0-9]{4}$")
CVE_RE = re.compile(r"^CVE-[0-9]{4}-[0-9]{4,}$")
DATE_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$")
CTRL_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")
TYPES = ("security", "bugfix", "enhancement")
SEVERITIES = ("Critical", "Important", "Moderate", "Low", "None")
NEVRA = ("name", "epoch", "version", "release", "arch")
QF = "%{NAME}\t%{EPOCHNUM}\t%{VERSION}\t%{RELEASE}\t%{ARCH}\t%{SOURCERPM}\n"


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def text_ok(value, what):
    if not value or not value.strip():
        die(f"{what} is empty")
    if CTRL_RE.search(value):
        die(f"{what} contains control characters")
    return value


def src_ok(src):
    return src.endswith(".src.rpm") and "/" not in src and not CTRL_RE.search(src)


def rpm_header(path):
    out = subprocess.run(["rpm", "-qp", "--nosignature", "--qf", QF, path],
                         check=True, capture_output=True, text=True).stdout
    name, epoch, version, release, arch, src = out.rstrip("\n").split("\t")
    return {"name": name, "epoch": epoch, "version": version,
            "release": release, "arch": arch, "src": src,
            "filename": os.path.basename(path)}


def make_update(adv):
    """Builds an <update> element from a dict of validated fields."""
    upd = ET.Element("update", {"from": "capivaraos-bot@users.noreply.github.com",
                                "status": "stable", "type": adv["type"],
                                "version": "1"})
    ET.SubElement(upd, "id").text = adv["id"]
    ET.SubElement(upd, "title").text = adv["title"]
    ET.SubElement(upd, "issued", {"date": adv["issued"]})
    ET.SubElement(upd, "severity").text = adv["severity"]
    ET.SubElement(upd, "description").text = adv["description"]
    refs = ET.SubElement(upd, "references")
    for c in adv["cves"]:
        ET.SubElement(refs, "reference", {
            "href": f"https://www.cve.org/CVERecord?id={c}",
            "id": c, "type": "cve", "title": c})
    coll = ET.SubElement(ET.SubElement(upd, "pkglist"), "collection",
                         {"short": "capivaraos-herd"})
    ET.SubElement(coll, "name").text = "CapivaraOS Herd"
    for p in adv["packages"]:
        pkg = ET.SubElement(coll, "package", {k: p[k] for k in NEVRA + ("src",)})
        ET.SubElement(pkg, "filename").text = p["filename"]
    return upd


def cmd_new(a):
    if not ID_RE.match(a.id):
        die(f"advisory id must look like HERD-2026-0001: {a.id}")
    for c in a.cve:
        if not CVE_RE.match(c):
            die(f"not a CVE id: {c}")
    if not a.rpms:
        die("pass at least one .rpm")
    os.makedirs(a.dir, exist_ok=True)
    out = os.path.join(a.dir, f"{a.id}.xml")
    adv = {
        "id": a.id, "type": a.type, "severity": a.severity,
        "title": text_ok(a.title, "--title"),
        "description": text_ok(a.description or a.title, "--description"),
        "issued": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
        "cves": a.cve,
        "packages": [rpm_header(p) for p in a.rpms],
    }
    for p in adv["packages"]:
        if not src_ok(p["src"]):
            die(f"{p['filename']}: unexpected source package name {p['src']!r}")
    upd = make_update(adv)
    ET.indent(upd)
    try:
        with open(out, "x", encoding="utf-8") as f:
            f.write(ET.tostring(upd, encoding="unicode") + "\n")
    except FileExistsError:
        die(f"{out} already exists; 'advisory' does not overwrite an advisory file")
    print(out)


def read_advisory(path):
    """Parses and validates one advisory file; returns its fields."""
    fn = os.path.basename(path)
    try:
        upd = ET.parse(path).getroot()
    except ET.ParseError as e:
        die(f"{fn}: not valid XML ({e})")
    if upd.tag != "update":
        die(f"{fn}: root element is not <update>")
    adv = {"id": upd.findtext("id") or "", "type": upd.get("type", ""),
           "severity": upd.findtext("severity") or "",
           "title": upd.findtext("title") or "",
           "description": upd.findtext("description") or "",
           "issued": (upd.find("issued").get("date", "")
                      if upd.find("issued") is not None else "")}
    if not ID_RE.match(adv["id"]) or adv["id"] != fn[:-4]:
        die(f"{fn}: <id> is not a HERD id matching the file name")
    if adv["type"] not in TYPES:
        die(f"{fn}: type {adv['type']!r} is not one of {', '.join(TYPES)}")
    if adv["severity"] not in SEVERITIES:
        die(f"{fn}: severity {adv['severity']!r} is not one of {', '.join(SEVERITIES)}")
    if not DATE_RE.match(adv["issued"]):
        die(f"{fn}: issued date must be 'YYYY-MM-DD HH:MM:SS'")
    text_ok(adv["title"], f"{fn}: <title>")
    text_ok(adv["description"], f"{fn}: <description>")
    adv["cves"] = []
    for r in upd.findall("./references/reference"):
        c = r.get("id", "")
        if r.get("type") != "cve" or not CVE_RE.match(c):
            die(f"{fn}: reference {c!r} is not a CVE id")
        adv["cves"].append(c)
    adv["packages"] = []
    for p in upd.findall("./pkglist/collection/package"):
        d = {k: p.get(k, "") for k in NEVRA + ("src",)}
        d["filename"] = p.findtext("filename") or ""
        if not all(d[k] for k in NEVRA) or not d["filename"].endswith(".rpm") \
                or "/" in d["filename"] or not src_ok(d["src"]) \
                or any(CTRL_RE.search(d[k]) for k in NEVRA + ("filename",)):
            die(f"{fn}: a package entry is incomplete")
        adv["packages"].append(d)
    if not adv["packages"]:
        die(f"{fn}: no packages")
    return adv


def cmd_build(a):
    present = {}
    for fn in sorted(os.listdir(a.pkgdir)):
        if fn.endswith(".rpm"):
            h = rpm_header(os.path.join(a.pkgdir, fn))
            present[fn] = tuple(h[k] for k in NEVRA)
    root = ET.Element("updates")
    names = sorted(f for f in os.listdir(a.dir) if f.endswith(".xml")) \
        if os.path.isdir(a.dir) else []
    for fn in names:
        path = os.path.join(a.dir, fn)
        if os.path.islink(path) or not os.path.isfile(path):
            die(f"{fn}: not a regular file")
        adv = read_advisory(path)
        here = []
        for p in adv["packages"]:
            want = tuple(p[k] for k in NEVRA)
            got = present.get(p["filename"])
            if got is not None and got != want:
                die(f"{adv['id']}: {p['filename']} in the channel is a different build "
                    f"than the advisory names")
            here.append(got is not None)
        if all(here):
            root.append(make_update(adv))
            print(f"  attached {adv['id']}", file=sys.stderr)
        elif any(here):
            missing = [p["filename"] for p, h in zip(adv["packages"], here) if not h]
            die(f"{adv['id']}: only part of its packages are in the channel; "
                f"missing: {' '.join(missing)}")
        else:
            print(f"  skipped {adv['id']} (its packages are not in this channel)",
                  file=sys.stderr)
    n = len(root)
    if n:
        ET.indent(root)
        data = '<?xml version="1.0" encoding="UTF-8"?>\n' + \
            ET.tostring(root, encoding="unicode") + "\n"
        ET.fromstring(data.encode("utf-8"))  # must parse back
        with open(a.output, "w", encoding="utf-8") as f:
            f.write(data)
    print(n)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    n = sub.add_parser("new")
    n.add_argument("dir")
    n.add_argument("--id", required=True)
    n.add_argument("--type", required=True, choices=TYPES)
    n.add_argument("--severity", required=True, choices=SEVERITIES)
    n.add_argument("--title", required=True)
    n.add_argument("--description", default="")
    n.add_argument("--cve", action="append", default=[])
    n.add_argument("rpms", nargs="*")
    b = sub.add_parser("build")
    b.add_argument("dir")
    b.add_argument("pkgdir")
    b.add_argument("output")
    a = ap.parse_args()
    {"new": cmd_new, "build": cmd_build}[a.cmd](a)


if __name__ == "__main__":
    main()
