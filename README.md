# Schulferien MQTT Bridge für LoxBerry

Dieses Plugin bezieht alle deutschen Schulferienperioden über die kostenlose [schulferien-api.de](https://schulferien-api.de) und veröffentlicht sie kompakt als JSON über MQTT — bereit für den Loxone MQTT Gateway mit JSON-Expansion.

## Features

- Alle 16 Bundesländer wählbar
- Zeigt: Heute Ferientag?, Name, Start, Ende, verbleibende Tage
- Nächste Ferien: Name, Start, Ende, Tage bis dahin, Dauer
- Daten für aktuelle und nächstes Jahr (kein Jahreswechselproblem)
- Automatischer Reload bei Datumswechsel
- Config-Reload ohne Daemon-Neustart

## MQTT-Topics

| Topic | Beschreibung |
|-------|-------------|
| `loxberry/schulferien/<slug>/data` | Kompaktes JSON-Payload |
| `loxberry/schulferien/<slug>/availability` | `online` / `offline` |

## Payload-Felder

| Feld | Typ | Beschreibung |
|------|-----|-------------|
| `is_holiday` | 0/1 | Heute Schulferien? |
| `holiday_name` | Text | Aktueller Ferienname |
| `holiday_start` | YYYY-MM-DD | Startdatum |
| `holiday_end` | YYYY-MM-DD | Enddatum |
| `holiday_days_left` | Zahl | Noch verbleibende Tage |
| `next_name` | Text | Nächste Ferien Name |
| `next_start` | YYYY-MM-DD | Nächste Ferien Start |
| `next_end` | YYYY-MM-DD | Nächste Ferien Ende |
| `next_days` | Zahl | Tage bis nächste Ferien |
| `next_duration` | Zahl | Dauer nächste Ferien (Tage) |

## Beispiel-Payload (BY, während Sommerferien)

```json
{
  "is_holiday": 1,
  "holiday_name": "Sommerferien",
  "holiday_start": "2026-08-03",
  "holiday_end": "2026-09-14",
  "holiday_days_left": 22,
  "next_name": "Herbstferien",
  "next_start": "2026-11-02",
  "next_end": "2026-11-06",
  "next_days": 71,
  "next_duration": 5
}
```

## Loxone Konfiguration

1. MQTT Gateway → **JSON expandieren** aktivieren
2. Subscription: `loxberry/schulferien/by/#`
3. In *Incoming Overview* Felder anlegen:
   - `loxberry_schulferien_by_data_is_holiday` → Virtual Input (digital)
   - `loxberry_schulferien_by_data_holiday_days_left` → Virtual Input (analog)
   - `loxberry_schulferien_by_data_next_days` → Virtual Input (analog)
   - `loxberry_schulferien_by_data_holiday_name` → Virtual Text Input
   - `loxberry_schulferien_by_data_next_name` → Virtual Text Input

## Requirements

- LoxBerry ≥ 2.0
- Perl-Module: `LWP::UserAgent`, `JSON::PP` (normalerweise vorinstalliert)
- Internetzugang für schulferien-api.de

## Version

0.1.2
