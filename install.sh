#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! command -v uv >/dev/null 2>&1; then
    printf 'FEHLER: uv wurde nicht gefunden.\n' >&2
    exit 1
fi

exec uv run --quiet --python 3.14 --no-project -- python - "$SCRIPT_DIR" "$@" <<'PY'
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

MARKER = "# Managed by loclass-installer."
REQUIRED_IDS = {
    "loclass-ldl",
    "loclass-base",
    "loclass-tlp",
    "loclass-starter",
    "loclass-cockpit",
}
REQUIRED_COMMANDS = ("git", "uv", "lua", "fzf", "jq", "find", "realpath")

script_dir = Path(sys.argv[1]).resolve()
command = sys.argv[2] if len(sys.argv) > 2 else "install"
extra = sys.argv[3:]

manifest_path = Path(
    os.environ.get("LOCLASS_RELEASE_MANIFEST", script_dir / "release.toml")
).expanduser().resolve()
data_root = Path(
    os.environ.get(
        "LOCLASS_DATA_HOME",
        Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
        / "loclass",
    )
).expanduser().resolve()
bin_dir = Path(
    os.environ.get("LOCLASS_BIN_DIR", Path.home() / ".local/bin")
).expanduser().resolve()
releases_dir = data_root / "releases"
current_link = data_root / "current"


class InstallerError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise InstallerError(message)


def step(message: str) -> None:
    print(f"\n==> {message}")


def warn(message: str) -> None:
    print(f"WARNUNG: {message}", file=sys.stderr)


def usage() -> None:
    print(
        """loclass-installer

Verwendung:
  ./install.sh [install]
  ./install.sh doctor
  ./install.sh reinstall
  ./install.sh help

Umgebungsvariablen:
  LOCLASS_RELEASE_MANIFEST  Pfad zu release.toml
  LOCLASS_DATA_HOME         Installationswurzel
  LOCLASS_BIN_DIR           Verzeichnis für Wrapper
"""
    )


def run(*parts, cwd=None, env=None, capture=False):
    return subprocess.run(
        [os.fspath(part) for part in parts],
        cwd=cwd,
        env=env,
        check=True,
        text=True,
        capture_output=capture,
    )


def read_release():
    if not manifest_path.is_file():
        fail(f"Release-Manifest nicht gefunden: {manifest_path}")

    with manifest_path.open("rb") as file:
        data = tomllib.load(file)

    if data.get("schema") != 1:
        fail("Nicht unterstützte Manifest-Version.")

    distribution = data.get("distribution", {})
    version = distribution.get("version")
    python_requirement = distribution.get("python")
    components = data.get("components")

    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail("Ungültige Distributionsversion.")
    if not isinstance(python_requirement, str):
        fail("Python-Anforderung fehlt.")
    if not isinstance(components, list) or not components:
        fail("Keine Komponenten definiert.")

    seen = set()
    for component in components:
        required = {"id", "kind", "repository", "tag", "commit", "dependencies"}
        if not isinstance(component, dict) or not required <= component.keys():
            fail("Unvollständiger Komponenten-Eintrag.")
        if component["id"] in seen:
            fail(f"Doppelte Komponenten-ID: {component['id']}")
        if component["kind"] not in {"python", "starter", "lua"}:
            fail(f"Unbekannter Komponententyp: {component['kind']}")
        if not re.fullmatch(r"[0-9a-f]{40}", component["commit"]):
            fail(f"Ungültige Commit-ID für {component['id']}.")
        for dependency in component["dependencies"]:
            if dependency not in seen:
                fail(
                    f"Abhängigkeit {dependency!r} muss vor "
                    f"{component['id']!r} definiert werden."
                )
        seen.add(component["id"])

    missing = REQUIRED_IDS - seen
    if missing:
        fail("Erforderliche Komponenten fehlen: " + ", ".join(sorted(missing)))

    match = re.search(r"\d+\.\d+", python_requirement)
    if match is None:
        fail(f"Python-Anforderung kann nicht ausgewertet werden: {python_requirement}")

    return {
        "version": version,
        "python": match.group(0),
        "components": components,
    }


def check_prerequisites():
    step("Voraussetzungen prüfen")
    missing = [name for name in REQUIRED_COMMANDS if shutil.which(name) is None]
    if missing:
        fail("Erforderliche Kommandos fehlen: " + ", ".join(missing))
    print("Alle erforderlichen Kommandos sind vorhanden.")


def release_dir(release):
    return releases_dir / release["version"]


def source_dir(base, component_id):
    return base / "sources" / component_id


def verify_release(release, directory):
    errors = []
    if not directory.is_dir():
        return [f"Release-Verzeichnis fehlt: {directory}"]
    if not (directory / "release.toml").is_file():
        errors.append("Installiertes release.toml fehlt.")

    for component in release["components"]:
        source = source_dir(directory, component["id"])
        if not (source / ".git").is_dir():
            errors.append(f"Git-Checkout fehlt: {component['id']}")
            continue
        try:
            actual = run(
                "git", "-C", source, "rev-parse", "HEAD", capture=True
            ).stdout.strip()
        except subprocess.CalledProcessError:
            errors.append(f"Commit nicht lesbar: {component['id']}")
            continue
        if actual != component["commit"]:
            errors.append(
                f"{component['id']}: {actual} statt {component['commit']}"
            )

    loclass = directory / "environment/bin/loclass"
    if not os.access(loclass, os.X_OK):
        errors.append("loclass fehlt oder ist nicht ausführbar.")
    else:
        try:
            run(loclass, "--help", capture=True)
        except (OSError, subprocess.CalledProcessError) as error:
            errors.append(f"loclass kann nicht ausgeführt werden: {error}")

    if not os.access(
        source_dir(directory, "loclass-cockpit") / "bin/loclass-cockpit",
        os.X_OK,
    ):
        errors.append("loclass-cockpit fehlt oder ist nicht ausführbar.")
    if not source_dir(directory, "loclass-starter").is_dir():
        errors.append("loclass-starter fehlt.")
    return errors


def clone_components(release, target):
    (target / "sources").mkdir(parents=True)
    for component in release["components"]:
        destination = source_dir(target, component["id"])
        step(f"{component['id']} {component['tag']} herunterladen")
        run(
            "git", "clone", "--quiet",
            "--branch", component["tag"],
            "--depth", "1", "--",
            component["repository"], destination,
        )
        actual = run(
            "git", "-C", destination, "rev-parse", "HEAD", capture=True
        ).stdout.strip()
        if actual != component["commit"]:
            fail(
                f"{component['id']}: Tag {component['tag']} zeigt auf "
                f"{actual} statt {component['commit']}."
            )
        print(f"{component['id']}: Commit bestätigt ({actual[:12]})")


def install_python(release, target):
    environment = target / "environment"
    packages = [
        source_dir(target, component["id"])
        for component in release["components"]
        if component["kind"] == "python"
    ]
    step("Isolierte Python-Umgebung erstellen")
    run("uv", "venv", "--python", release["python"], environment)
    run(
        "uv", "pip", "install",
        "--python", environment / "bin/python",
        *packages,
    )
    discovered = run(
        environment / "bin/loclass", "packages", "list", capture=True
    ).stdout.splitlines()
    if "loclass.tlp" not in discovered:
        fail("loclass.tlp wurde nicht registriert.")


def smoke_test(directory):
    cockpit = source_dir(directory, "loclass-cockpit")
    script = cockpit / "tests/smoke.sh"
    if not os.access(script, os.X_OK):
        fail("Cockpit-Smoke-Test fehlt oder ist nicht ausführbar.")
    step("Cockpit-Smoke-Test ausführen")
    environment = os.environ.copy()
    environment["LOCLASS_COMMAND"] = os.fspath(
        directory / "environment/bin/loclass"
    )
    environment["LOCLASS_STARTER"] = os.fspath(
        source_dir(directory, "loclass-starter")
    )
    run(script, cwd=cockpit, env=environment)


def is_managed(path):
    if not path.exists() and not path.is_symlink():
        return True
    try:
        return MARKER in path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False


def write_atomic(path, content):
    temporary = path.with_name(f".{path.name}.tmp.{os.getpid()}")
    try:
        temporary.write_text(content, encoding="utf-8")
        temporary.chmod(0o755)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def write_wrappers():
    step("Programm-Wrapper installieren")
    bin_dir.mkdir(parents=True, exist_ok=True)
    loclass = bin_dir / "loclass"
    cockpit = bin_dir / "loclass-cockpit"
    for path in (loclass, cockpit):
        if not is_managed(path):
            fail(f"Vorhandene Datei wird nicht vom Installer verwaltet: {path}")

    write_atomic(
        loclass,
        f'''#!/bin/sh
{MARKER}
exec "{current_link}/environment/bin/loclass" "$@"
''',
    )
    write_atomic(
        cockpit,
        f'''#!/bin/sh
{MARKER}
export LOCLASS_COMMAND="{current_link}/environment/bin/loclass"
export LOCLASS_STARTER="{current_link}/sources/loclass-starter"
exec "{current_link}/sources/loclass-cockpit/bin/loclass-cockpit" "$@"
''',
    )
    print(f"Installiert: {loclass}")
    print(f"Installiert: {cockpit}")


def activate(directory):
    step("Distribution aktivieren")
    data_root.mkdir(parents=True, exist_ok=True)
    if current_link.exists() and not current_link.is_symlink():
        fail(f"{current_link} existiert, ist aber kein symbolischer Link.")
    temporary = data_root / f".current.tmp.{os.getpid()}"
    temporary.unlink(missing_ok=True)
    try:
        temporary.symlink_to(directory)
        os.replace(temporary, current_link)
    finally:
        temporary.unlink(missing_ok=True)
    write_wrappers()


def check_path():
    if os.fspath(bin_dir) not in os.environ.get("PATH", "").split(os.pathsep):
        warn(f"{bin_dir} ist nicht im PATH enthalten.")


def doctor(release):
    check_prerequisites()
    directory = release_dir(release)
    step(f"Release {release['version']} prüfen")
    errors = verify_release(release, directory)
    if errors:
        fail("\n".join(errors))
    if not current_link.is_symlink() or current_link.resolve() != directory.resolve():
        fail(f"Aktiver Release-Link ist nicht korrekt: {current_link}")

    loclass = directory / "environment/bin/loclass"
    run(loclass, "--help", capture=True)
    schema = json.loads(
        run(
            loclass, "packages", "describe", "loclass.tlp", "--json",
            capture=True,
        ).stdout
    )
    valid_label = any(
        field.get("name") == "label"
        and field.get("type") == "choice"
        and field.get("required") is True
        for field in schema.get("fields", [])
    )
    if schema.get("schema_version") != 1 or not valid_label:
        fail("Das Schema von loclass.tlp ist unerwartet.")

    smoke_test(directory)
    check_path()
    step("Ergebnis")
    print(f"loclass {release['version']} ist vollständig installiert.")
    print(f"Aktiver Release: {directory}")


def install(release):
    check_prerequisites()
    directory = release_dir(release)

    if directory.exists():
        step("Vorhandene Distribution prüfen")
        errors = verify_release(release, directory)
        if errors:
            fail(
                "Release ist unvollständig:\n"
                + "\n".join(errors)
                + "\nVerwende: ./install.sh reinstall"
            )
        print(f"Release {release['version']} ist bereits installiert.")
        activate(directory)
        doctor(release)
        return

    releases_dir.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=f".{release['version']}.tmp.", dir=releases_dir)
    )
    promoted = False
    try:
        shutil.copy2(manifest_path, staging / "release.toml")
        clone_components(release, staging)
        cockpit = source_dir(staging, "loclass-cockpit") / "bin/loclass-cockpit"
        cockpit.chmod(cockpit.stat().st_mode | 0o111)

        # Python virtual environments and their console scripts contain
        # absolute paths. Therefore the release directory must already have
        # its final name before the environment is created.
        os.replace(staging, directory)
        promoted = True

        install_python(release, directory)
        smoke_test(directory)
    except Exception:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        if promoted and directory.exists():
            shutil.rmtree(directory, ignore_errors=True)
        raise

    activate(directory)
    check_path()
    step("Installation abgeschlossen")
    print(f"Distribution: loclass {release['version']}")
    print(f"Daten:        {directory}")
    print(f"Programme:    {bin_dir / 'loclass'}")
    print(f"              {bin_dir / 'loclass-cockpit'}")


def reinstall(release):
    check_prerequisites()
    directory = release_dir(release)
    if current_link.is_symlink() and current_link.resolve() == directory.resolve():
        current_link.unlink()
    if directory.exists():
        if not (directory / "release.toml").is_file():
            fail(f"Löschen verweigert: Installer-Manifest fehlt in {directory}")
        step(f"Release {release['version']} entfernen")
        shutil.rmtree(directory)
    install(release)


def main():
    if extra:
        usage()
        return 2
    if command in {"help", "-h", "--help"}:
        usage()
        return 0

    release = read_release()
    if command == "install":
        install(release)
    elif command in {"doctor", "--doctor"}:
        doctor(release)
    elif command == "reinstall":
        reinstall(release)
    else:
        usage()
        return 2
    return 0


try:
    raise SystemExit(main())
except InstallerError as error:
    print(f"FEHLER: {error}", file=sys.stderr)
    raise SystemExit(1) from error
except subprocess.CalledProcessError as error:
    rendered = " ".join(map(str, error.cmd))
    print(f"FEHLER: Kommando fehlgeschlagen: {rendered}", file=sys.stderr)
    raise SystemExit(error.returncode or 1) from error
except OSError as error:
    print(f"FEHLER: Betriebssystemfehler: {error}", file=sys.stderr)
    raise SystemExit(1) from error
PY
