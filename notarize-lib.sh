#!/bin/bash
# Gemeinsame Signier- und Notarisierungs-Helfer für install.sh, release.sh und
# wrappers/sign-and-release.sh. Wird gesourct, nicht ausgeführt.
# Credential-Werte bleiben ausschließlich im macOS-Schlüsselbund; hier steht nur
# der Profil-NAME.

# Team-ID und Developer-ID-Identity sind public-safe (stehen ohnehin in LICENSE,
# Info.plist und jeder signierten Binary).
NOTARY_TEAM_ID="${APPLE_TEAM_ID:-9QSWKSR4NQ}"
NOTARY_IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application: Daniel Mueller ($NOTARY_TEAM_ID)}"

# Profilnamen bestimmen: Umgebung schlägt clone-lokale Git-Konfiguration.
# Kein fester Default mehr — ein eingecheckter Name existiert auf fremden Macs
# nicht und lässt den Lauf erst nach dem Bauen scheitern. Keychain-Profile sind
# ohnehin pro Mac lokal und werden nicht synchronisiert.
require_notary_profile() {
    if [[ -z "${NOTARY_PROFILE:-}" ]]; then
        NOTARY_PROFILE="$(git config --local --get exploids.notaryProfile 2>/dev/null || true)"
    fi
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "FEHLER: Kein Notary-Profil bekannt." >&2
        echo "Entweder NOTARY_PROFILE setzen oder einmalig für diesen Clone:" >&2
        echo "  git config --local exploids.notaryProfile <profil>" >&2
        echo "Das Profil selbst einmal pro Mac anlegen:" >&2
        echo "  xcrun notarytool store-credentials <profil> --apple-id <apple-id> --team-id $NOTARY_TEAM_ID" >&2
        return 2
    fi
    export NOTARY_PROFILE

    # Nur ein echter Aufruf erkennt, ob das Profil auf diesem Mac benutzbar ist.
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "FEHLER: Das Notary-Profil '$NOTARY_PROFILE' ist auf diesem Mac nicht verwendbar." >&2
        echo "Über SSH ist der Login-Schlüsselbund gesperrt — dann in einer lokalen" >&2
        echo "Terminalsitzung erneut versuchen." >&2
        return 2
    fi
}

# App-Bundle mit Developer ID signieren. build-app.sh signiert bewusst nicht;
# ein reiner Testbuild soll ohne Zertifikat durchlaufen.
# --options runtime: Hardened Runtime (Pflicht für Notarisierung).
# --timestamp:       Apple-Zeitstempel → Signatur bleibt nach Zert-Ablauf gültig.
# Exploids ist ein reines SwiftPM-Executable ohne eingebettete Frameworks —
# darum genügt es, das Bundle selbst zu signieren.
sign_app() {
    local app="$1"
    if ! security find-identity -v -p codesigning | grep -Fq "$NOTARY_IDENTITY"; then
        echo "FEHLER: Signing-Identität nicht gefunden: $NOTARY_IDENTITY" >&2
        security find-identity -v -p codesigning >&2
        return 1
    fi
    echo "=== Signiere App ($NOTARY_IDENTITY) ==="
    codesign --force --options runtime --timestamp --sign "$NOTARY_IDENTITY" "$app"
    codesign --verify --strict --verbose=2 "$app"
}

# App-Bundle notarisieren und das Ticket anheften. notarytool nimmt kein nacktes
# .app entgegen, deshalb der Umweg über ein ZIP. Das angeheftete Ticket ist der
# eigentliche Punkt: Damit startet die App auch dann ohne Gatekeeper-Meckern,
# wenn jemand sie aus dem DMG herauszieht oder offline ist.
notarize_app() {
    local app="$1"
    local archive
    archive="$(mktemp -d)/Exploids.zip"

    if ! codesign --verify --strict "$app" >/dev/null 2>&1; then
        echo "FEHLER: '$app' ist nicht gültig signiert — Notarisierung sinnlos." >&2
        return 1
    fi
    if codesign -dvv "$app" 2>&1 | grep -q '^Signature=adhoc$'; then
        echo "FEHLER: '$app' ist nur ad-hoc signiert. Für die Notarisierung ist eine" >&2
        echo "Developer-ID-Signatur nötig (sign_app)." >&2
        return 1
    fi

    echo "=== Notarisiere App (Profil: $NOTARY_PROFILE) ==="
    ditto -c -k --keepParent "$app" "$archive"
    xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    spctl -a -t exec -vv "$app" 2>&1 | tail -2
    rm -rf "$(dirname "$archive")"
}
