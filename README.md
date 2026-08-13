# 🏠 Homeassist Archive

**Homeassist Archive** archiviert historische Home-Assistant-Statistikdaten langfristig in einer eigenen PostgreSQL-Datenbank.

Home Assistant stellt Statistikdaten unter anderem als Parquet-Dateien bereit. Dieses Projekt holt die entsprechenden Dateien automatisiert per SSH/SFTP vom Home-Assistant-System ab, verarbeitet sie und importiert die enthaltenen Daten in PostgreSQL.

Damit können historische Messwerte langfristig aufbewahrt und unabhängig von der internen Home-Assistant-Datenhaltung ausgewertet werden.

> 💡 Das Projekt ist insbesondere interessant, wenn Home-Assistant-Daten über einen längeren Zeitraum archiviert und später mit SQL, Grafana oder anderen Werkzeugen ausgewertet werden sollen.

## ✨ Features

- 📥 Automatischer Download der Home-Assistant-Statistikdaten
- 🔐 Zugriff auf Home Assistant per SSH mit Ed25519-Key
- 📦 Verarbeitung von Parquet-Dateien
- 🐘 Speicherung in PostgreSQL
- ♻️ Verhindert den mehrfachen Import bereits verarbeiteter Dateien
- 🗂️ Lokales Zwischenarchiv der heruntergeladenen Dateien
- 🕒 Speicherung von Zeitstempeln als UTC
- 📊 Verwaltung der Statistik-Metadaten
- 📝 Import-Historie mit Anzahl der importierten Datensätze
- 📋 Logging der einzelnen Verarbeitungsschritte

## 🔄 Funktionsweise

Der Datenfluss sieht vereinfacht so aus:

```text
┌─────────────────────┐
│    Home Assistant   │
│                     │
│ /share/export       │
│ statistics*.parquet │
└──────────┬──────────┘
           │
           │ SSH / SFTP
           ▼
┌─────────────────────┐
│   Homeassist        │
│      Archive        │
│                     │
│ /opt/homeassist/    │
│ ├── incoming/       │
│ └── archive/        │
└──────────┬──────────┘
           │
           │ Pandas
           │ SQLAlchemy
           ▼
┌─────────────────────┐
│     PostgreSQL      │
│                     │
│ statistics_meta     │
│ statistics_short_   │
│ term                │
│ import_history      │
└─────────────────────┘
```

Das Python-Skript sucht auf dem Home-Assistant-System gezielt nach Dateien, deren Name mit `statistics` beginnt und die auf `.parquet` enden. Bereits lokal vorhandene Dateien werden nicht erneut heruntergeladen.

Anschließend wird geprüft, ob eine Datei bereits importiert wurde. Die Import-Historie verhindert dadurch doppelte Importe.

## 📁 Projektstruktur

```text
Homeassist-Archive/
├── SQL/
│   └── ...
├── fetchhomeassist.py
├── requirements.txt
├── README.md
└── LICENSE
```

## 🛠️ Voraussetzungen

Benötigt werden:

- Linux/Unix-System
- Python 3
- PostgreSQL
- SSH-Zugriff auf Home Assistant
- Python Virtual Environment
- SSH-Schlüssel für den Zugriff auf Home Assistant

Das Skript verwendet unter anderem Paramiko für SSH/SFTP, Pandas für die Verarbeitung der Parquet-Dateien und SQLAlchemy für den Zugriff auf PostgreSQL.

## 🚀 Installation

### 1. Benutzer anlegen

Beispielsweise kann ein eigener Systembenutzer für das Archiv verwendet werden:

```bash
sudo useradd --system --create-home --home-dir /opt/homeassist homeassist
```

### 2. Repository klonen

```bash
sudo -u homeassist git clone \
  https://github.com/JPT77/Homeassist-Archive.git \
  /opt/homeassist/Homeassist-Archive
```

### 3. Python Virtual Environment erstellen

```bash
cd /opt/homeassist/Homeassist-Archive

sudo -u homeassist python3 -m venv .venv

sudo -u homeassist .venv/bin/pip install \
  -r requirements.txt
```

### 4. Verzeichnisse vorbereiten

```bash
sudo -u homeassist mkdir -p \
  /opt/homeassist/incoming \
  /opt/homeassist/archive
```

## 🔑 SSH-Zugriff auf Home Assistant

Das Skript verwendet standardmäßig:

```text
Host: homeassistant
User: root
Key: ~/.ssh/id_ed25519
Remote directory: /share/export
```

Diese Werte sind aktuell direkt im Python-Skript hinterlegt.

Der SSH-Key muss für den Benutzer vorhanden sein, unter dem das Skript ausgeführt wird.

Test:

```bash
ssh -i ~/.ssh/id_ed25519 root@homeassistant
```

Wenn der Hostname `homeassistant` nicht per DNS/mDNS aufgelöst werden kann, kann alternativ ein entsprechender Eintrag in `/etc/hosts` oder der SSH-Konfiguration verwendet werden.

## 🐘 PostgreSQL

Das Skript erwartet eine PostgreSQL-Datenbank mit dem Namen:

```text
homeassist
```

Der Datenbankbenutzer wird standardmäßig aus

```text
PG_USER
```

gelesen und verwendet standardmäßig den Benutzer:

```text
homeassist
```

Der PostgreSQL-Host kann über

```text
PG_HOST
```

gesetzt werden.

Das Passwort wird **nicht** im Skript hinterlegt, sondern über die Umgebungsvariable

```text
PG_PW
```

bereitgestellt.

Beispiel:

```bash
export PG_USER=homeassist
export PG_HOST=localhost
export PG_PW='DEIN_PASSWORT'
```

> ⚠️ Das Passwort sollte nicht in das Git-Repository eingecheckt werden.

## 🗄️ Datenbankschema

Im Repository befindet sich ein eigener `SQL`-Bereich für die benötigten Datenbankstrukturen.

Das Skript verwendet insbesondere folgende Tabellen:

### `statistics_meta`

Enthält die Metadaten der einzelnen Home-Assistant-Statistiken, beispielsweise:

- `statistic_id`
- Quelle
- Einheit
- Name
- Informationen über Mean/Sum

### `statistics_short_term`

Enthält die eigentlichen archivierten Statistikdaten.

### `import_history`

Dokumentiert bereits importierte Dateien und die Anzahl der importierten Datensätze.

Dadurch kann das Skript erkennen, ob eine Datei bereits verarbeitet wurde.

## ▶️ Manueller Start

Nach der Installation kann das Skript direkt gestartet werden:

```bash
cd /opt/homeassist/Homeassist-Archive

PG_PW='DEIN_PASSWORT' \
  .venv/bin/python fetchhomeassist.py
```

Mit Logdatei:

```bash
PG_PW='DEIN_PASSWORT' \
  .venv/bin/python fetchhomeassist.py \
  >> /opt/homeassist/import.log 2>&1
```

## 🕐 Automatischer täglicher Import

Da der Rechner nicht dauerhaft eingeschaltet ist, ist ein klassischer Cronjob wie

```cron
0 2 * * *
```

nicht ideal.

Der Job würde nur um 02:00 Uhr ausgeführt. Ist der Rechner zu diesem Zeitpunkt ausgeschaltet, findet der Lauf nicht statt.

### Empfehlung: anacron

`anacron` führt einen täglichen Job aus und holt ihn nach, wenn der Rechner zwischenzeitlich ausgeschaltet war.

Beispiel:

```text
/etc/cron.daily/homeassist-archive
```

Inhalt:

```bash
#!/bin/sh

set -eu

APP_DIR="/opt/homeassist/Homeassist-Archive"
VENV="$APP_DIR/.venv/bin/python"
LOG="/opt/homeassist/import.log"

export PG_USER="homeassist"
export PG_HOST="localhost"
export PG_PW="DEIN_PASSWORT"

cd "$APP_DIR"

exec "$VENV" fetchhomeassist.py >> "$LOG" 2>&1
```

Ausführbar machen:

```bash
sudo chmod 750 /etc/cron.daily/homeassist-archive
```

Damit wird der Import **einmal pro Tag** ausgeführt, ohne dass eine bestimmte Uhrzeit erforderlich ist.

> Hinweis: Das genaue Verhalten hängt davon ab, wie `anacron` bzw. `cron.daily` auf dem verwendeten Linux-System konfiguriert ist.

## 🔐 Passwort besser über eine separate Datei

Statt das PostgreSQL-Passwort direkt in `/etc/cron.daily/homeassist-archive` einzutragen, kann eine separate Datei verwendet werden.

Beispielsweise:

```bash
sudo nano /etc/homeassist-archive.env
```

```text
PG_USER=homeassist
PG_HOST=localhost
PG_PW=DEIN_PASSWORT
```

Berechtigungen:

```bash
sudo chown root:root /etc/homeassist-archive.env
sudo chmod 600 /etc/homeassist-archive.env
```

Der Cronjob kann dann so aussehen:

```bash
#!/bin/sh

set -eu

APP_DIR="/opt/homeassist/Homeassist-Archive"
VENV="$APP_DIR/.venv/bin/python"
LOG="/opt/homeassist/import.log"

. /etc/homeassist-archive.env

cd "$APP_DIR"

exec "$VENV" fetchhomeassist.py >> "$LOG" 2>&1
```

Das ist deutlich besser, als ein Datenbankpasswort direkt im Repository oder in einer versionierten Konfigurationsdatei zu speichern.

## 📋 Logging

Das Skript verwendet Python-Logging und protokolliert unter anderem:

- Verbindung zu Home Assistant
- heruntergeladene Dateien
- bereits vorhandene Dateien
- übersprungene Dateien
- gestartete Importe
- Anzahl importierter Datensätze
- Fehler beim Import



Beispielsweise können die letzten Einträge mit folgendem Befehl angesehen werden:

```bash
tail -100 /opt/homeassist/import.log
```

## 🔍 Kontrolle

Manuell testen:

```bash
sudo -u homeassist \
  env PG_PW='DEIN_PASSWORT' \
  /opt/homeassist/Homeassist-Archive/.venv/bin/python \
  /opt/homeassist/Homeassist-Archive/fetchhomeassist.py
```

Danach das Log prüfen:

```bash
tail -100 /opt/homeassist/import.log
```

Und anschließend beispielsweise PostgreSQL überprüfen:

```sql
SELECT *
FROM import_history
ORDER BY id DESC
LIMIT 10;
```

## 💡 Warum dieses Projekt?

Home-Assistant-Daten sind besonders interessant, wenn sie über lange Zeiträume betrachtet werden können.

Mit einem separaten Archiv lassen sich beispielsweise langfristige Entwicklungen untersuchen:

- 📈 Energieverbrauch
- 🌡️ Temperaturen
- 💧 Luftfeuchtigkeit
- ⚡ Stromproduktion
- 🔌 Stromverbrauch
- 🏠 Gebäudezustände
- 📊 weitere Home-Assistant-Statistiken

Die Daten können anschließend mit SQL oder Visualisierungswerkzeugen weiterverarbeitet werden.

## ⚠️ Hinweise

Dieses Projekt ist auf eine konkrete Home-Assistant-/Serverumgebung zugeschnitten.

Insbesondere folgende Werte müssen gegebenenfalls angepasst werden:

```python
SSH_HOST
SSH_USER
SSH_KEY
REMOTE_DIR
BASE_DIR
```

Die aktuelle Implementierung erwartet die Home-Assistant-Dateien unter:

```text
/share/export
```

und verarbeitet ausschließlich Dateien mit dem Namenspräfix:

```text
statistics
```

sowie der Endung:

```text
.parquet
```



## 📜 Lizenz

Dieses Projekt steht unter der **GNU General Public License v3.0 (GPL-3.0)**.

## ⭐ Credits

Entwickelt von [JPT77](https://github.com/JPT77).

Wenn dir das Projekt hilft, freue ich mich über einen ⭐ auf GitHub!
