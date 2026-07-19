# loclass-installer

`loclass-installer` installiert eine fest definierte, reproduzierbare
loclass-Distribution im Benutzerkonto.

Der Installer lädt die freigegebenen Git-Tags aller benötigten Komponenten,
prüft die zugehörigen Commit-IDs, erzeugt eine isolierte Python-Umgebung und
stellt die Programme `loclass` und `loclass-cockpit` unter `~/.local/bin`
bereit.

Er verwendet kein `sudo`, installiert keine Betriebssystempakete und verändert
keine Entwicklungs-Repositories.

## Aktuelle Distribution

Die Distribution `loclass 0.3.0` besteht aus:

| Komponente | Version |
|---|---:|
| `loclass-ldl` | `v0.2.0` |
| `loclass-base` | `v0.4.0` |
| `loclass-mermaid` | `v0.1.0` |
| `loclass-tlp` | `v0.1.0` |
| `loclass-review` | `v0.2.0` |
| `loclass-starter` | `v0.2.0` |
| `loclass-cockpit` | `v0.1.1` |

Die vollständige Zuordnung von Repository, Tag und Commit-ID steht in
[`release.toml`](release.toml).

## Warum ein eigener Installer?

loclass besteht aus mehreren eigenständigen Repositories:

- LDL-Parser und Dokumentmodell,
- loclass-CLI,
- optionale Packages,
- Dokument-Starter,
- Terminal-Cockpit.

Die jeweils neuesten Branch-Stände müssen nicht automatisch zueinander passen.
Der Installer verwendet deshalb keine schwebenden Branches, sondern eine
explizite Release-Matrix.

Für jede Komponente werden festgelegt:

- Repository-URL,
- Git-Tag,
- vollständige Commit-ID,
- Komponententyp,
- Abhängigkeiten.

Nach dem Klonen prüft der Installer, ob der ausgecheckte Commit exakt der
freigegebenen Commit-ID entspricht. Erst danach wird die Komponente verwendet.

## Voraussetzungen

Folgende Programme müssen vorhanden sein:

- `git`
- `uv`
- `lua`
- `luac`
- `fzf`
- `jq`
- `find`
- `realpath`

Die aktuelle Distribution verwendet Python 3.14. Der Installer startet über
`uv` und lässt `uv` eine geeignete Python-3.14-Laufzeit auswählen
beziehungsweise bereitstellen.

Da die derzeitigen Repository-URLs auf die interne Gitea-Instanz zeigen,
werden außerdem benötigt:

- Zugriff auf `git.home.arpa`,
- ein berechtigter SSH-Schlüssel,
- bei verschlüsseltem Schlüssel ein entsperrter SSH-Agent oder die Eingabe der
  Passphrase.

Die Voraussetzungen können vorab geprüft werden:

```sh
for command in git uv lua luac fzf jq find realpath; do
    command -v "$command" >/dev/null 2>&1 ||
        printf 'Fehlt: %s\n' "$command"
done
```

## Repository-Inhalt

```text
loclass-installer/
├── .gitignore
├── install.sh
├── README.md
└── release.toml
```

`install.sh`
: Installiert, prüft oder installiert die Distribution neu.

`release.toml`
: Definiert die unveränderliche Zusammensetzung der Distribution.

`.gitignore`
: Ignoriert lokale Testinstallationen und temporäre Dateien.

## Installation

Das Skript ausführbar machen:

```sh
chmod +x install.sh
```

Die Standardinstallation starten:

```sh
./install.sh
```

Standardmäßig werden die Daten hier abgelegt:

```text
~/.local/share/loclass/
```

Die Programm-Wrapper werden hier installiert:

```text
~/.local/bin/loclass
~/.local/bin/loclass-cockpit
```

`~/.local/bin` muss im `PATH` enthalten sein:

```sh
case ":$PATH:" in
    *":$HOME/.local/bin:"*)
        printf '%s\n' '~/.local/bin ist im PATH.'
        ;;
    *)
        printf '%s\n' '~/.local/bin fehlt im PATH.'
        ;;
esac
```

Für Zsh kann der Pfad beispielsweise in `~/.zshenv` ergänzt werden:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Installationsstruktur

Nach einer erfolgreichen Installation sieht die Struktur ungefähr so aus:

```text
~/.local/share/loclass/
├── current -> releases/0.2.0
└── releases/
    └── 0.2.0/
        ├── environment/
        │   ├── bin/
        │   ├── lib/
        │   └── pyvenv.cfg
        ├── release.toml
        └── sources/
            ├── loclass-base/
            ├── loclass-cockpit/
            ├── loclass-ldl/
├── loclass-mermaid/
            ├── loclass-review/
            ├── loclass-starter/
            └── loclass-tlp/
```

Die Verknüpfung:

```text
~/.local/share/loclass/current
```

zeigt auf die aktive Distribution.

Die beiden Wrapper unter `~/.local/bin` greifen immer über diese Verknüpfung
auf die aktive Installation zu.

## Mermaid-Voraussetzungen

Die Distribution enthält das optionale Package `loclass.mermaid`. Für das
Rendern von Mermaid-Diagrammen müssen zusätzlich vorhanden sein:

- Mermaid CLI als Kommando `mmdc`,
- ein Chromium-kompatibler Browser.

Der Browser wird automatisch gesucht. Alternativ kann er über
`LOCLASS_MERMAID_BROWSER` oder `PUPPETEER_EXECUTABLE_PATH` festgelegt werden.

## Installierte Programme

### loclass

```sh
loclass --help
```

Installierte Packages anzeigen:

```sh
loclass packages list
```

Package-Konfiguration anzeigen:

```sh
loclass packages describe loclass.tlp
loclass packages describe loclass.review
loclass packages describe loclass.mermaid
```

Maschinenlesbare Ausgabe:

```sh
loclass packages describe loclass.tlp --json
loclass packages describe loclass.review --json
loclass packages describe loclass.mermaid --json
```

### loclass-cockpit

```sh
loclass-cockpit --help
```

Cockpit mit einem Dokument-Root starten:

```sh
loclass-cockpit ~/Dokumente/Adam
```

Der installierte Wrapper setzt automatisch:

- `LOCLASS_COMMAND` auf die loclass-CLI der aktiven Distribution,
- `LOCLASS_STARTER` auf den installierten `loclass-starter`.

Bei einer normalen Installation müssen diese Variablen daher nicht manuell
gesetzt werden.

## Kommandos

### Installieren

```sh
./install.sh
```

Ohne Argument wird `install` ausgeführt.

Existiert dieselbe Distribution bereits, wird sie geprüft, erneut aktiviert
und anschließend mit dem Doctor kontrolliert. Sie wird nicht blind
überschrieben.

Explizit ist ebenfalls möglich:

```sh
./install.sh install
```

### Installation prüfen

```sh
./install.sh doctor
```

Der Doctor prüft:

- externe Voraussetzungen,
- das Release-Verzeichnis,
- alle geklonten Git-Checkouts,
- die Commit-IDs,
- die isolierte Python-Umgebung,
- den `loclass`-Entrypoint,
- die Schemata von `loclass.tlp`, `loclass.review` und `loclass.mermaid`,
- einen echten Mermaid-Render-Smoke-Test mit PNG- und ODT-Ausgabe,
- den Cockpit-Smoke-Test,
- die aktive `current`-Verknüpfung,
- den Installationspfad der Wrapper.

Ein erfolgreicher Lauf endet ungefähr so:

```text
==> Ergebnis
loclass 0.3.0 ist vollständig installiert.
Aktiver Release: /home/USER/.local/share/loclass/releases/0.2.0
```

### Neu installieren

```sh
./install.sh reinstall
```

`reinstall` entfernt die aktuell definierte Distributionsversion und erstellt
sie vollständig neu.

Zum Schutz vor versehentlichem Löschen verweigert der Installer das Entfernen
eines Release-Verzeichnisses, wenn darin das installierte `release.toml`
fehlt.

### Hilfe

```sh
./install.sh help
```

Alternativ:

```sh
./install.sh --help
```

## Isolierter Test

Eine vollständige Testinstallation kann innerhalb des Installer-Repositories
angelegt werden, ohne die normale Benutzerinstallation zu verändern:

```sh
LOCLASS_DATA_HOME="$PWD/.install-test/data" \
LOCLASS_BIN_DIR="$PWD/.install-test/bin" \
./install.sh
```

Anschließend den Doctor mit denselben Pfaden ausführen:

```sh
LOCLASS_DATA_HOME="$PWD/.install-test/data" \
LOCLASS_BIN_DIR="$PWD/.install-test/bin" \
./install.sh doctor
```

Die installierten Programme direkt prüfen:

```sh
TEST_BIN="$PWD/.install-test/bin"

"$TEST_BIN/loclass" --help
"$TEST_BIN/loclass" packages list
"$TEST_BIN/loclass" packages describe loclass.tlp --json
"$TEST_BIN/loclass" packages describe loclass.review --json
"$TEST_BIN/loclass-cockpit" --help
```

Die Warnung, dass `.install-test/bin` nicht im normalen `PATH` liegt, ist bei
diesem Testaufbau erwartbar.

Testinstallation entfernen:

```sh
rm -rf .install-test
```

## Umgebungsvariablen

### `LOCLASS_RELEASE_MANIFEST`

Pfad zu einem alternativen Release-Manifest.

Standard:

```text
<Installer-Verzeichnis>/release.toml
```

Beispiel:

```sh
LOCLASS_RELEASE_MANIFEST="$PWD/release-next.toml" \
./install.sh
```

### `LOCLASS_DATA_HOME`

Installationswurzel für Distributionen.

Standard:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/loclass
```

Beispiel:

```sh
LOCLASS_DATA_HOME="$HOME/test/loclass-data" \
./install.sh
```

### `LOCLASS_BIN_DIR`

Zielverzeichnis für die Programm-Wrapper.

Standard:

```text
$HOME/.local/bin
```

Beispiel:

```sh
LOCLASS_BIN_DIR="$HOME/test/bin" \
./install.sh
```

Für spätere Doctor- oder Reinstall-Aufrufe müssen dieselben Pfade erneut
angegeben werden:

```sh
LOCLASS_DATA_HOME="$HOME/test/loclass-data" \
LOCLASS_BIN_DIR="$HOME/test/bin" \
./install.sh doctor
```

## Release-Manifest

Das Release-Manifest verwendet TOML:

```toml
schema = 1

[distribution]
name = "loclass"
version = "0.3.0"
python = ">=3.14"

[installation]
data_directory = "~/.local/share/loclass"
binary_directory = "~/.local/bin"

[[components]]
id = "loclass-ldl"
kind = "python"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-ldl.git"
tag = "v0.2.0"
commit = "8f488dbd896b68d82524bcab979e32987d7cd150"
dependencies = []

[[components]]
id = "loclass-base"
kind = "python"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-base.git"
tag = "v0.4.0"
commit = "681a41ad1f87d5c206d55fe7321b0117dbb1d0bd"
dependencies = ["loclass-ldl"]

[[components]]
id = "loclass-mermaid"
kind = "python"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-mermaid.git"
tag = "v0.1.0"
commit = "7b2d705c44ddd6eeca3ba441f3bcab14d5e23473"
dependencies = ["loclass-base"]

[[components]]
id = "loclass-tlp"
kind = "python"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-tlp.git"
tag = "v0.1.0"
commit = "8d777fe9dd4ae4ed9145b48d12bd1543fbb62ca7"
dependencies = ["loclass-base"]

[[components]]
id = "loclass-review"
kind = "python"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-review.git"
tag = "v0.2.0"
commit = "b9add04ad5cd4ef115b890e4daed9ad4e8b93f9b"
dependencies = ["loclass-base"]

[[components]]
id = "loclass-starter"
kind = "starter"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-starter.git"
tag = "v0.2.0"
commit = "fd155ab18015409e73a0dea1feaece71ca2e02e8"
dependencies = []

[[components]]
id = "loclass-cockpit"
kind = "lua"
repository = "ssh://git@git.home.arpa:2222/loclass/loclass-cockpit.git"
tag = "v0.1.1"
commit = "e9544ef340ccefcfa51427a5d2237ba9526d88a5"
dependencies = ["loclass-base", "loclass-starter"]
```

Die Komponenten müssen in Abhängigkeitsreihenfolge aufgeführt sein. Eine
Komponente darf nur Abhängigkeiten benennen, die im Manifest bereits vorher
definiert wurden.

Unterstützte Komponententypen:

```text
python
starter
lua
```

Die aktuelle Release-Matrix lautet:

```text
loclass-ldl
  Tag:    v0.2.0
  Commit: 8f488dbd896b68d82524bcab979e32987d7cd150

loclass-base
  Tag:    v0.4.0
  Commit: 681a41ad1f87d5c206d55fe7321b0117dbb1d0bd

loclass-mermaid
  Tag:    v0.1.0
  Commit: 7b2d705c44ddd6eeca3ba441f3bcab14d5e23473

loclass-tlp
  Tag:    v0.1.0
  Commit: 8d777fe9dd4ae4ed9145b48d12bd1543fbb62ca7

loclass-review
  Tag:    v0.2.0
  Commit: b9add04ad5cd4ef115b890e4daed9ad4e8b93f9b

loclass-starter
  Tag:    v0.2.0
  Commit: fd155ab18015409e73a0dea1feaece71ca2e02e8

loclass-cockpit
  Tag:    v0.1.1
  Commit: e9544ef340ccefcfa51427a5d2237ba9526d88a5
```

## Installationsablauf

Der Installer führt folgende Schritte aus:

1. Voraussetzungen prüfen.
2. `release.toml` lesen und validieren.
3. Temporäres Release-Verzeichnis anlegen.
4. Komponenten anhand ihrer Tags klonen.
5. Commit-IDs mit dem Manifest vergleichen.
6. Release-Verzeichnis an seinen endgültigen Pfad verschieben.
7. Dort die isolierte Python-Umgebung erzeugen.
8. Python-Komponenten aus den verifizierten Quellen installieren.
9. Package-Discovery prüfen.
10. Cockpit-Smoke-Test ausführen.
11. Distribution über `current` aktivieren.
12. Programm-Wrapper atomar schreiben.
13. Ergebnis und Installationspfade ausgeben.

Die virtuelle Python-Umgebung wird bewusst erst am endgültigen Release-Pfad
erzeugt. Python-Konsolenskripte enthalten absolute Pfade in ihren
Shebang-Zeilen; eine nachträglich verschobene Umgebung wäre daher nicht
zuverlässig ausführbar.

## Integritätsprüfung

Ein Tag allein ist keine ausreichende unveränderliche Freigabeinformation,
weil Git-Tags technisch neu gesetzt werden können.

Der Installer prüft deshalb zusätzlich die vollständige Commit-ID:

```text
Komponente: loclass-review
Tag:        v0.2.0
Erwartet:   b9add04ad5cd4ef115b890e4daed9ad4e8b93f9b
```

Weicht der ausgecheckte Commit ab, wird die Installation abgebrochen.

Der Doctor wiederholt diese Prüfung für die installierten Checkouts.

## Python-Umgebung

Alle Python-Komponenten werden gemeinsam in einer isolierten Umgebung
installiert:

```text
releases/0.3.0/environment/
```

Dazu gehören:

- `loclass`,
- `loclass-ldl`,
- `loclass-tlp`,
- `loclass-review`,
- `loclass-mermaid`,
- deren Laufzeitabhängigkeiten.

Installiert werden die innerhalb des Releases geklonten und verifizierten
Quellen. Die Entwicklungs-Repositories unter `~/git/loclass` werden nicht als
editierbare Quellen eingebunden.

## Cockpit-Smoke-Test

Vor der Aktivierung führt der Installer den Smoke-Test aus dem
`loclass-cockpit`-Release aus.

Er prüft unter anderem:

- Lua- und Cockpit-Abhängigkeiten,
- Syntax der Lua-Dateien,
- Laden der Cockpit-Module,
- Export von `app.run`,
- Dokumenterkennung,
- Erreichbarkeit der loclass-CLI,
- Package-Discovery,
- Schema von `loclass.tlp`.

Eine neue Installation wird erst aktiviert, wenn dieser Test erfolgreich
durchgelaufen ist.

## Programm-Wrapper

Die Wrapper enthalten den Marker:

```text
# Managed by loclass-installer.
```

Nur Dateien mit diesem Marker dürfen vom Installer ersetzt werden.

Existiert unter einem vorgesehenen Wrapper-Namen bereits eine fremde Datei,
bricht der Installer ab, statt sie zu überschreiben.

Die Wrapper verwenden den stabilen Pfad:

```text
~/.local/share/loclass/current
```

Dadurch bleiben die aufgerufenen Programmpfade unverändert, wenn später eine
andere Distribution aktiviert wird.

## Entwicklungs- und Anwenderinstallation

Die Entwicklungsinstallation bleibt unabhängig:

```text
~/git/loclass/
├── loclass-base/
├── loclass-cockpit/
├── loclass-installer/
├── loclass-ldl/
├── loclass-mermaid/
├── loclass-review/
├── loclass-starter/
└── loclass-tlp/
```

Dort können Branches, editierbare Abhängigkeiten und uncommittete Änderungen
existieren.

Die Anwenderinstallation liegt dagegen unter:

```text
~/.local/share/loclass/releases/
```

Sie enthält ausschließlich festgelegte Tags, verifizierte Commit-IDs und eine
isolierte Laufzeitumgebung.

Der Installer verändert die Entwicklungs-Repositories nicht.

## Fehlerdiagnose

### Repository kann nicht geklont werden

Zugriff auf einen Tag prüfen:

```sh
git ls-remote \
  ssh://git@git.home.arpa:2222/frank/loclass-base.git \
  refs/tags/v0.3.0
```

SSH-Verbindung prüfen:

```sh
ssh -p 2222 git@git.home.arpa
```

Gitea beendet die Verbindung möglicherweise ohne interaktive Shell. Relevant
ist, ob die Authentifizierung erfolgreich war.

### SSH-Passphrase wird mehrfach abgefragt

SSH-Agent starten und Schlüssel hinzufügen:

```sh
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Danach den Installer erneut ausführen.

### Wrapper-Verzeichnis fehlt im PATH

Temporär:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

Dauerhaft beispielsweise in `~/.zshenv`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

### Vorhandener Wrapper wird nicht überschrieben

Der Installer überschreibt keine fremde Datei unter:

```text
~/.local/bin/loclass
~/.local/bin/loclass-cockpit
```

Die vorhandene Datei zuerst prüfen:

```sh
sed -n '1,10p' ~/.local/bin/loclass
```

Nur vom Installer verwaltete Wrapper enthalten:

```text
# Managed by loclass-installer.
```

Eine fremde Datei muss bewusst umbenannt oder entfernt werden, bevor der
Installer fortgesetzt wird.

### Release ist unvollständig

Doctor ausführen:

```sh
./install.sh doctor
```

Anschließend neu installieren:

```sh
./install.sh reinstall
```

### Installiertes Package wird nicht gefunden

```sh
loclass packages list
```

Erwartet werden mindestens:

```text
loclass.mermaid
loclass.review
loclass.tlp
```

Schemata prüfen:

```sh
loclass packages describe loclass.review --json
loclass packages describe loclass.tlp --json
loclass packages describe loclass.mermaid --json
```

### Cockpit startet nicht

```sh
loclass-cockpit --help
```

Danach:

```sh
./install.sh doctor
```

## Neue Distribution vorbereiten

Vor einer neuen Distribution müssen alle beteiligten Komponenten:

1. einen sauberen Arbeitsbaum besitzen,
2. vollständig getestet sein,
3. committed und gepusht sein,
4. einen veröffentlichten Release-Tag besitzen.

Danach werden in `release.toml` aktualisiert:

- Distributionsversion,
- Komponententags,
- Commit-IDs,
- gegebenenfalls Repository-URLs,
- gegebenenfalls Abhängigkeiten.

Anschließend ist eine frische isolierte Installation erforderlich:

```sh
rm -rf .install-test

LOCLASS_DATA_HOME="$PWD/.install-test/data" \
LOCLASS_BIN_DIR="$PWD/.install-test/bin" \
./install.sh

LOCLASS_DATA_HOME="$PWD/.install-test/data" \
LOCLASS_BIN_DIR="$PWD/.install-test/bin" \
./install.sh doctor
```

Erst nach einem erfolgreichen Installations- und Doctor-Lauf sollte der
Installer selbst getaggt werden.

## Entwicklung

Shell-Syntax prüfen:

```sh
sh -n install.sh
```

Hilfe prüfen:

```sh
./install.sh help
```

Release-Manifest lesen:

```sh
uv run --quiet --python 3.14 --no-project -- python - <<'PY'
from pathlib import Path
import tomllib

with Path("release.toml").open("rb") as file:
    release = tomllib.load(file)

print(
    release["distribution"]["name"],
    release["distribution"]["version"],
)

for component in release["components"]:
    print(
        component["id"],
        component["tag"],
        component["commit"],
    )
PY
```

Git-Diff prüfen:

```sh
git diff --check
```

Vollständigen Test ausführen:

```sh
rm -rf .install-test

LOCLASS_DATA_HOME="$PWD/.install-test/data" \
LOCLASS_BIN_DIR="$PWD/.install-test/bin" \
./install.sh

LOCLASS_DATA_HOME="$PWD/.install-test/data" \
LOCLASS_BIN_DIR="$PWD/.install-test/bin" \
./install.sh doctor
```

## Release-Verfahren

Arbeitsbaum prüfen:

```sh
git status --short
git diff --check
```

Release-Dateien übernehmen:

```sh
git add .gitignore install.sh release.toml README.md
```

Staging prüfen:

```sh
git diff --cached --check
git diff --cached --stat
```

Commit erstellen:

```sh
git commit -m "chore: release distribution 0.2.0"
```

Annotierten Tag setzen:

```sh
git tag -a v0.2.0 -m "loclass-installer 0.2.0"
```

Branch und Tag pushen:

```sh
git push --atomic origin main v0.2.0
```

## Derzeitige Einschränkungen

Version 0.2.0 ist auf die interne loclass-Infrastruktur ausgerichtet:

- Die Repository-URLs zeigen auf `git.home.arpa`.
- Zugriff über SSH ist erforderlich.
- Betriebssystempakete werden nicht automatisch installiert.
- Es gibt noch keinen automatischen Update-Befehl.
- Es gibt noch keinen Uninstall-Befehl.
- Das Release-Manifest ist noch nicht kryptografisch signiert.
- Es existiert noch kein öffentlicher Download-Endpunkt.

Diese Einschränkungen sind für die interne Distribution bewusst akzeptiert.

## Lizenz

Eine Lizenz ist derzeit noch nicht festgelegt.

Vor einer öffentlichen Veröffentlichung sollte eine passende `LICENSE`-Datei
ergänzt werden.
