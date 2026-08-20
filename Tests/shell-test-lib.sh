#!/bin/bash
# Gemeinsame Helfer fuer Shell-Integrationstests. Die Tests schneiden damit
# echten Produktionscode aus den Skripten und pruefen Mach-O-Dateien mit genau
# derselben, auf macOS verifizierten Byte-Suche.

# Gibt den ersten Block von einer Start- bis zu einer Endzeile aus. Beide
# Argumente sind regulaere Ausdruecke fuer awk.
extract_block() {   # $1 = Datei, $2 = Startmuster, $3 = Endmuster
    awk -v start="$2" -v end="$3" '
        $0 ~ start { printing=1 }
        printing { print }
        printing && $0 ~ end { exit }
    ' "$1"
}

# Gibt ab der ersten passenden Zeile bis zum Dateiende aus.
extract_from() {   # $1 = Datei, $2 = Startmuster
    awk -v start="$2" '
        $0 ~ start { printing=1 }
        printing { print }
    ' "$1"
}

extract_function() {   # $1 = Datei, $2 = Funktionsname
    extract_block "$1" "^$2[(][)] [{]" '^[}]$'
}

# Bricht laut ab, wenn eine erwartete Funktion umbenannt oder umgebaut wurde,
# statt einen leeren Test-Doppelgaenger weiterlaufen zu lassen.
append_function() {   # $1 = Quelldatei, $2 = Funktionsname, $3 = Zieldatei
    local body
    body="$(extract_function "$1" "$2")"
    if [ -z "$body" ]; then
        echo "FEHLER: Funktion $2 nicht in $1 gefunden — Test veraltet." >&2
        return 1
    fi
    printf '%s\n' "$body" >> "$3"
}

# `strings -` liest auf macOS jedes Byte. `strings` ohne Schalter und `-a`
# beschraenken sich auf Objektdatei-Sektionen und uebersehen __LINKEDIT; dort
# standen die ausgelieferten Build-Mac-Pfade.
binary_hits() {   # $1 = Datei, $2 = gesuchter fester Text
    strings - "$1" 2>/dev/null | grep -F "$2"
}

# Dieses Mach-O-Symbol bleibt auch mit Chained Fixups und nach `strip -S`
# erhalten. `dyld_stub_binder` verschwindet dagegen ab macOS-Target 12.
MACHO_PROBE_SYMBOL="__mh_execute_header"

binary_probe_is_visible() {   # $1 = Mach-O-Datei
    [ -n "$(binary_hits "$1" "$MACHO_PROBE_SYMBOL")" ]
}
