# Software Design Description – iPS2PDF

## 1. Zweck

iPS2PDF ist eine SwiftUI-App für iOS und iPadOS, die eine beliebige reguläre Datei entgegennimmt, diese über Ghostscript in eine PDF-Datei konvertiert und das erzeugte PDF anschließend systemnah anzeigt.

Die App unterstützt zwei Eingangswege:

1. Auswahl einer Datei innerhalb der App.
2. Übergabe einer Datei über **„Öffnen mit iPS2PDF“**.

Beide Wege münden in denselben Konvertierungsworkflow.

Die App untersucht den Dateityp oder Dateiinhalt vor der Konvertierung nicht. Jede akzeptierte Datei wird identisch an Ghostscript übergeben. Ob der Dateiinhalt von Ghostscript verarbeitet werden kann, entscheidet ausschließlich Ghostscript.

---

# 2. Zielplattform und Entwicklungsregeln

## 2.1 Plattform

- iOS 26 oder neuer
- iPadOS 26 oder neuer
- SwiftUI
- Swift
- PDFKit
- Ghostscript als statisch eingebundene Library

Die App unterstützt Hoch- und Querformat.

Die App ist eine **Single-Scene-/Single-Window-App**. Mehrere unabhängige iPS2PDF-Fenster werden auch auf iPadOS nicht unterstützt.

---

## 2.2 Sprache und Lokalisierung

Die Entwicklungssprache des Projekts ist Englisch.

Englisch wird verwendet für:

- Quellcode
- Typnamen
- Variablennamen
- Funktionsnamen
- Kommentare
- interne technische Bezeichnungen
- technische Projektdokumentation

Die Benutzeroberfläche wird von Anfang an lokalisierbar implementiert.

Unterstützte UI-Sprachen der ersten Version:

- Englisch als Basissprache
- Deutsch

UI-Texte dürfen nicht unstrukturiert als fest codierte Strings über den Swift-Code verteilt werden.

---

# 3. Hauptscreen

Der Hauptscreen enthält dauerhaft:

1. einen Button zum Öffnen einer Datei;
2. einen Segmented Controller zur Auswahl der PDF-Version.

Unterstützte PDF-Versionen:

- PDF 1.2
- PDF 1.3
- PDF 1.4

Standardwert:

- PDF 1.3

Weitere dauerhaft sichtbare Funktionen sind auf dem Hauptscreen nicht erforderlich.

---

# 4. Dateiauswahl

## 4.1 Öffnen-Dialog

Der Öffnen-Button öffnet den systemeigenen Dateiauswahldialog.

Der Benutzer darf **jede reguläre Datei** auswählen.

Es findet keine Einschränkung statt anhand von:

- Dateiendung
- UTType der konkreten Datei
- Groß-/Kleinschreibung der Dateiendung
- Inhalt der Datei

Insbesondere sind auch Dateien ohne Dateiendung zulässig.

Verzeichnisse bzw. Ordner sind keine gültigen Eingaben.

Der Datei-Picker erlaubt ausschließlich **Einzelauswahl**.

---

## 4.2 Zeitpunkt des Verarbeitungsstarts

Das Öffnen des Datei-Pickers startet noch keine Verarbeitung.

Erst nachdem der Benutzer eine konkrete Datei ausgewählt hat, gilt der Verarbeitungsvorgang als gestartet.

Ab diesem Zeitpunkt:

1. werden alle interaktiven Bedienelemente sofort deaktiviert;
2. wird die aktuelle PDF-Version für diesen Vorgang festgeschrieben;
3. startet sofort der 0,5-Sekunden-Timer für die Warteanzeige;
4. beginnt der eigentliche Verarbeitungsworkflow.

---

# 5. „Öffnen mit iPS2PDF“

## 5.1 Grundprinzip

Die App unterstützt die Übergabe von Dateien über den iOS-/iPadOS-Mechanismus **„Öffnen mit iPS2PDF“**.

Eine separate Share Extension wird nicht implementiert.

Die App akzeptiert dabei dieselben Eingaben wie über den internen Datei-Picker:

> jede reguläre Datei, unabhängig von Typ, Endung oder Inhalt.

`LSSupportsOpeningDocumentsInPlace` wird aktiviert.

---

## 5.2 Cold Start

Wird iPS2PDF durch die Übergabe einer Datei gestartet, wird die Datei ohne weitere Benutzerbestätigung sofort verarbeitet.

Der Benutzer hat durch die Auswahl von „Öffnen mit iPS2PDF“ die Verarbeitung bereits ausgelöst.

Daher beginnen sofort:

- UI-Sperre
- 0,5-Sekunden-Timer
- Verarbeitungsworkflow

---

## 5.3 Übergabe während geöffnetem Datei-Picker

Kommt eine Datei über „Öffnen mit iPS2PDF“ herein, während der interne Datei-Picker geöffnet ist, hat die externe Übergabe Vorrang.

Der Datei-Picker wird beendet und die externe Datei wird verarbeitet.

---

## 5.4 Mehrere gleichzeitig übergebene Dateien

Werden in einem Übergabevorgang mehrere Dateien gleichzeitig angeboten, wird der **gesamte Vorgang abgelehnt**.

Keine der Dateien wird übernommen.

Die App zeigt einen modalen Hinweis mit einem Button:

`Dismiss`

---

# 6. Einheitliche Behandlung aller Eingaben

Es existiert keine Dateityperkennung vor Ghostscript.

Es gibt keine Sonderbehandlung für:

- `.ps`
- `.eps`
- `.pdf`
- `.txt`
- Dateien ohne Endung
- beliebige andere Endungen

Jede reguläre Datei durchläuft denselben Ablauf:

```text
File received
      |
      v
Wait for startup cleanup if necessary
      |
      v
Clear current working directory
      |
      v
Copy source file
      |
      v
Run Ghostscript
      |
      v
Validate generated PDF
      |
      v
Present PDF
```

Die Dateiendung beeinflusst die Ghostscript-Argumente nicht.

---

# 7. Arbeitsverzeichnis

## 7.1 Genau ein Arbeitsverzeichnis

Die App verwendet genau ein Arbeitsverzeichnis:

```swift
FileManager.default.temporaryDirectory
    .appendingPathComponent("Current conversion", isDirectory: true)
```

Konzeptionell:

```text
<App Sandbox>/tmp/Current conversion/
```

Es werden keine UUID-Unterverzeichnisse angelegt.

Es wird keine Historie geführt.

Es werden keine alten Konvertierungen gesammelt.

---

## 7.2 Bereinigung beim App-Start

Beim Start der App wird das Verzeichnis `Current conversion` asynchron bereinigt.

Die Benutzeroberfläche bleibt währenddessen bedienbar.

Eine tatsächliche Dateiübernahme bzw. Konvertierung darf jedoch erst fortgesetzt werden, nachdem dieses Startup-Cleanup erfolgreich abgeschlossen wurde.

Wählt der Benutzer bereits während des Startup-Cleanups eine Datei aus bzw. trifft eine externe Datei ein, gilt:

1. UI sofort deaktivieren;
2. 0,5-Sekunden-Timer sofort starten;
3. laufendes Startup-Cleanup per `await` abwarten;
4. danach normalen Workflow fortsetzen.

Es wird keine zweite Cleanup-Operation parallel zum bereits laufenden Startup-Cleanup gestartet.

---

## 7.3 Bereinigung vor einer neuen Verarbeitung

Vor der Übernahme jeder neuen Datei wird `Current conversion` vollständig geleert.

Kann das Arbeitsverzeichnis nicht vollständig bereinigt werden, wird die neue Datei nicht übernommen und Ghostscript nicht gestartet.

---

## 7.4 Bereinigung nach erfolgreicher Anzeige

Wird der PDF-Viewer vom Benutzer geschlossen, wird das Arbeitsverzeichnis vollständig geleert.

Beginnt bei geöffnetem PDF-Viewer eine neue Konvertierung, gilt:

1. PDF-Viewer schließen;
2. Arbeitsverzeichnis vollständig leeren;
3. neue Datei übernehmen;
4. neue Konvertierung starten.

---

## 7.5 Bereinigung nach Fehlern

Nach einem Fehler während Dateiübernahme oder Konvertierung wird das Arbeitsverzeichnis vollständig bereinigt, bevor der Fehlerzustand abgeschlossen wird.

Scheitert eine Dateiübernahme teilweise, wird ebenfalls versucht, das gesamte Arbeitsverzeichnis wieder zu bereinigen.

Die SDD spezifiziert keine weiteren rekursiven Sonderfälle für Fehler innerhalb einer solchen Fehlerbereinigung.

---

# 8. Übernahme der Eingabedatei

## 8.1 Lokale Kopie

Jede Eingabedatei wird vor der Ghostscript-Verarbeitung in `Current conversion` kopiert.

Ghostscript arbeitet niemals direkt mit einer externen Datei-URL.

Für die Kopie wird die normale Foundation-Dateioperation verwendet.

Copy-on-write soll genutzt werden, wenn das zugrunde liegende Dateisystem dies unterstützt.

Ist Copy-on-write technisch nicht möglich, ist eine normale physische Kopie zulässig.

---

## 8.2 Security-Scoped Resources

Ist für die externe Datei Security-Scoped Access erforderlich, gilt:

```text
Acquire security-scoped access
        |
        v
Copy file into Current conversion
        |
        v
Release security-scoped access
```

Der externe Zugriff wird nur so lange gehalten, wie er für die lokale Übernahme benötigt wird.

Ghostscript erhält ausschließlich die lokale Datei.

---

## 8.3 Dateiname der Quelldatei

Die Quelldatei wird im Arbeitsverzeichnis unter dem Dateinamen gespeichert, unter dem sie eingetroffen ist.

Beispiel:

```text
Original:
Schöne Datei.test.xyz

Temporary:
Current conversion/Schöne Datei.test.xyz
```

Es erfolgt keine generische Umbenennung in `input`.

---

# 9. Name der erzeugten PDF-Datei

Der Name der PDF-Ausgabedatei wird aus dem ursprünglichen Dateinamen abgeleitet.

Für die Zerlegung des Dateinamens werden ausschließlich die normalen Foundation-URL-/Path-Extension-Funktionen verwendet.

Es wird kein eigener Dateinamen-Parser implementiert.

Die erzeugte PDF-Endung wird immer als

```text
.pdf
```

in Kleinbuchstaben geschrieben.

---

## 9.1 Datei mit normaler Endung

Ist eine Dateiendung vorhanden und lautet diese nicht `pdf`, wird die letzte Dateiendung durch `.pdf` ersetzt.

Beispiele:

```text
input.ps
→ input.pdf

Schöne Datei.test.xyz
→ Schöne Datei.test.pdf

ABC.EPS
→ ABC.pdf
```

---

## 9.2 Datei ohne Endung

Hat die Eingabedatei keine von Foundation erkannte Dateiendung, wird `.pdf` angehängt.

Beispiel:

```text
PostScript Input
→ PostScript Input.pdf
```

---

## 9.3 Eingabedatei mit PDF-Endung

Ist die letzte Dateiendung bereits `pdf`, wird sie nicht ersetzt.

Stattdessen wird eine zusätzliche `.pdf`-Endung angehängt.

Die Prüfung erfolgt case-insensitive.

Beispiele:

```text
Dokument.pdf
→ Dokument.pdf.pdf

Dokument.PDF
→ Dokument.PDF.pdf

Dokument.Pdf
→ Dokument.Pdf.pdf
```

Damit können Eingabe- und Ausgabedatei niemals allein aufgrund der PDF-Endung denselben Pfad erhalten.

---

# 10. PDF-Version

## 10.1 Modell

```swift
enum PDFVersion: String, CaseIterable {
    case v12 = "1.2"
    case v13 = "1.3"
    case v14 = "1.4"
}
```

---

## 10.2 Persistenz

Die ausgewählte PDF-Version wird in `UserDefaults` gespeichert.

Der Zugriff erfolgt ausschließlich über eine gekapselte Getter-/Setter-API.

Direkte Bindung der UI an `UserDefaults` über `@AppStorage` ist nicht vorgesehen.

Konzeptionell:

```swift
var pdfVersion: PDFVersion {
    get {
        // Read stored value.
        // If missing or invalid:
        //   store PDFVersion.v13
        //   return PDFVersion.v13
    }

    set {
        // Persist new value.
    }
}
```

---

## 10.3 Ungültige oder fehlende Werte

Ist kein Wert gespeichert oder kann der gespeicherte Wert nicht auf

- `1.2`
- `1.3`
- `1.4`

abgebildet werden, gilt:

1. `1.3` wird in `UserDefaults` geschrieben;
2. `PDFVersion.v13` wird zurückgegeben.

Der Getter ist damit selbstheilend.

---

# 11. UI-Verhalten während der Verarbeitung

## 11.1 Sofortige Sperre

Sobald eine konkrete Datei zur Verarbeitung angenommen wurde, werden **sämtliche interaktiven Bedienelemente sofort deaktiviert**.

Dies gilt insbesondere für:

- Öffnen-Button
- PDF-Version-Segmented-Control
- sonstige interaktive Elemente des Hauptscreens

Die für diesen Vorgang ausgewählte PDF-Version bleibt dadurch unverändert.

---

## 11.2 0,5-Sekunden-Timer

Gleichzeitig mit der UI-Sperre startet ein Timer von:

```text
0.5 seconds
```

Der Timer umfasst den gesamten Vorgang.

Es spielt keine Rolle, ob die App währenddessen:

- auf das Startup-Cleanup wartet;
- das Arbeitsverzeichnis bereinigt;
- die Eingabedatei kopiert;
- Ghostscript ausführt;
- die PDF-Ausgabe validiert.

---

## 11.3 Warteanzeige

Ist der Vorgang nach 0,5 Sekunden noch nicht beendet:

1. wird der aktuelle Screen leicht abgedunkelt;
2. wird mittig ein systemnaher `ProgressView` angezeigt.

Endet der Vorgang vor Ablauf der 0,5 Sekunden, wird die Warteanzeige nicht eingeblendet.

---

## 11.4 Kein Benutzerabbruch

Es gibt keinen Cancel- bzw. Abbrechen-Button.

Eine gestartete Verarbeitung läuft bis zu:

- Erfolg oder
- Fehler.

---

# 12. Nebenläufigkeit

## 12.1 Swift Concurrency

Alle Operationen außerhalb unmittelbarer UI-Aktualisierungen werden über Swift Concurrency mit `async`/`await` organisiert.

Dazu gehören insbesondere:

- Startup-Cleanup
- Arbeitsverzeichnis-Cleanup
- Dateiübernahme
- Ghostscript-Konvertierung
- PDF-Validierung
- sonstige potentiell blockierende I/O-Arbeit

Diese Operationen dürfen den `MainActor` nicht blockieren.

---

## 12.2 MainActor

Der `MainActor` ist für UI-Zustandsänderungen zuständig.

Beispiele:

- Buttons aktivieren/deaktivieren
- Overlay präsentieren
- Fehlerdialog präsentieren
- PDF-Viewer präsentieren
- Share-Sheet-Zustand aktualisieren

---

## 12.3 GCD

Explizite GCD-Konstruktionen wie

```swift
DispatchQueue.global().async
```

sind nicht das primäre Concurrency-Modell.

Falls eine interne C-API-Integration technisch eine solche Brücke benötigt, muss sie innerhalb der Integrationsschicht gekapselt bleiben.

Die öffentliche Swift-API bleibt `async`/`await`-basiert.

---

# 13. Ghostscript-Konvertierungssemantik

## 13.1 Ziel

Die drei PDF-Versionen sollen sich semantisch so verhalten wie die mit Ghostscript ausgelieferten Programme:

- `ps2pdf12`
- `ps2pdf13`
- `ps2pdf14`

Die Shell-Skripte selbst werden **nicht zur Laufzeit unter iOS ausgeführt**.

Es wird kein Shell-Interpreter und kein Parser für die Ghostscript-Skripte implementiert.

---

## 13.2 Abbildung der ps2pdf-Skripte

Die Ghostscript-Integrationsschicht bildet die Argumente nach, die durch die entsprechende Kette

```text
ps2pdf12 / ps2pdf13 / ps2pdf14
              |
              v
          ps2pdfwr
              |
              v
             gs
```

an Ghostscript übergeben würden.

Die aktuellen Upstream-Skripte ergänzen für die drei Varianten jeweils:

```text
PDF 1.2:
-dCompatibilityLevel=1.2
-dWriteXRefStm=false
-dWriteObjStms=false

PDF 1.3:
-dCompatibilityLevel=1.3
-dWriteXRefStm=false
-dWriteObjStms=false

PDF 1.4:
-dCompatibilityLevel=1.4
-dWriteXRefStm=false
-dWriteObjStms=false
```



`ps2pdfwr` ergänzt unter anderem die `pdfwrite`-Konfiguration und übergibt seine gesammelten Optionen bewusst zweimal. Diese Argumentreihenfolge wird in der Bridge ebenfalls nachgebildet.

Die konkrete Argumentbildung liegt ausschließlich in der Ghostscript-Integrationsschicht.

Der restliche Swift-Code kennt keine Ghostscript-Kommandozeilenparameter.

---

# 14. Ghostscript-Bridge

## 14.1 Stabile Grenze

Swift importiert nicht direkt große Mengen Ghostscript-interner Header.

Zwischen Swift und Ghostscript liegt eine kleine eigene C-Bridge.

Konzeptionell:

```c
int gs_convert_to_pdf(
    const char *input_path,
    const char *output_path,
    const char *pdf_version
);
```

Die endgültige Bridge darf zusätzlich strukturierte Diagnoseinformationen zurückgeben.

---

## 14.2 Ghostscript-C-API

Die Bridge verwendet die Ghostscript Interpreter API.

Die Ghostscript-API stellt unter anderem Instanzerzeugung, stdio-Callbacks, `gsapi_init_with_args`, `gsapi_exit` und Instanzfreigabe bereit.

---

## 14.3 Neue Instanz pro Konvertierung

Für jede einzelne Konvertierung wird eine neue Ghostscript-Instanz erzeugt.

Konzeptionell:

```text
gsapi_new_instance
        |
        v
configure callbacks
        |
        v
gsapi_init_with_args
        |
        v
conversion
        |
        v
gsapi_exit
        |
        v
gsapi_delete_instance
```

Ghostscript-Zustand wird niemals zwischen zwei Konvertierungen wiederverwendet.

Die Ghostscript-Dokumentation verlangt insbesondere `gsapi_exit` vor `gsapi_delete_instance`, wenn die Instanz initialisiert wurde.

---

# 15. Ghostscript-Diagnoseausgabe

Die Bridge registriert Ghostscript-Callbacks für `stdout` und `stderr`.

Ghostscript unterstützt dafür explizit stdio-Callback-Funktionen.

Bei einem Ghostscript-Fehler gilt:

1. Ist `stderr` nicht leer, werden dessen erste 300 Zeichen verwendet.
2. Ist `stderr` leer, werden die ersten 300 Zeichen von `stdout` verwendet.
3. Längere Ausgabe wird nach 300 Zeichen abgeschnitten.
4. Eine gekürzte Ausgabe wird entsprechend kenntlich gemacht.
5. Zusätzlich wird der numerische Ghostscript-Return-Code angezeigt.

Der Ghostscript-Text wird nicht übersetzt oder semantisch interpretiert.

Er darf technisch bzw. kryptisch sein, da er primär der Diagnose dient.

---

# 16. Ghostscript-Build

## 16.1 Upstream-Code

Der Ghostscript-Sourcecode liegt vollständig unter:

```text
Vendor/Ghostscript/upstream/
```

Dieser Bereich wird als austauschbarer Upstream-Bereich behandelt.

Eigener App-Code wird dort nicht dauerhaft gepflegt.

---

## 16.2 Kein eigenes Ghostscript-Buildsystem

iPS2PDF implementiert kein eigenes Ghostscript-Buildsystem und pflegt keine eigene Liste einzelner Ghostscript-Quelldateien.

Insbesondere entfallen Konzepte wie:

```text
GhostscriptSources.xcfilelist
GhostscriptHeaders.xcfilelist
```

als Grundlage für einen manuell zusammengestellten Ghostscript-Build.

---

## 16.3 Offizielles iOS-Buildscript

Grundlage für den Ghostscript-Build ist das mit der jeweiligen Ghostscript-Version gelieferte offizielle Script:

```text
Vendor/Ghostscript/upstream/ios/build_ios_gslib.sh
```

Das aktuelle Upstream-Script enthält noch historische Architektur- und Universal-Library-Annahmen und wird daher nicht zwingend unverändert ausgeführt.

---

## 16.4 Kompatibilitätspatch

Der originale Upstream wird nicht dauerhaft verändert.

Beim Build wird:

1. das offizielle Script als Ausgangspunkt verwendet;
2. bei Bedarf eine Arbeitskopie des Scripts erzeugt;
3. diese Arbeitskopie mit kleinen deterministischen Kompatibilitätsanpassungen, z. B. per `sed`, an das aktuelle Xcode-Ziel angepasst;
4. anschließend weiterhin die offizielle Ghostscript-Buildlogik ausgeführt.

Es wird damit **kein eigener Ersatz für die Ghostscript-Buildlogik** implementiert.

---

## 16.5 Erkennung bekannter Scriptversionen

Die App-Buildlogik darf erkennen, ob die vorliegende Version des offiziellen Scripts bereits bekannt ist.

Ist sie unbekannt:

1. wird eine deutliche Build-Warnung ausgegeben;
2. die bestehende Patchlogik wird trotzdem versucht;
3. der Build wird nicht allein wegen der unbekannten Scriptversion abgebrochen.

Scheitert dagegen tatsächlich:

- der Patch,
- der Ghostscript-Build oder
- das spätere Linken,

schlägt der App-Build regulär fehl.

---

## 16.6 Getrennte Build-Artefakte

Device und Simulator verwenden getrennte Ghostscript-Artefakte.

Konzeptionell:

```text
Vendor/Ghostscript/upstream/ios/build/
├── iphoneos/
│   └── libgs.a
└── iphonesimulator/
    └── libgs.a
```

Die genaue interne Pfadstruktur darf technisch angepasst werden, solange die Trennung zwischen Device und Simulator erhalten bleibt.

---

## 16.7 Einfache Existenzprüfung

Der App-Build entscheidet ausschließlich anhand der Existenz des für das aktuelle Ziel benötigten Ghostscript-Artefakts, ob Ghostscript gebaut werden muss.

Beispiel:

```text
Build target: iphoneos
        |
        v
iphoneos/libgs.a exists?
   |              |
  yes             no
   |              |
 reuse      run Ghostscript build
```

Es werden ausdrücklich keine zusätzlichen Mechanismen verwendet wie:

- Source-Hashes
- Verzeichnis-Hashes
- Zeitstempelvergleich
- Versionsdatenbank
- automatische Source-Change-Erkennung

---

## 16.8 Ghostscript-Update

Ein Ghostscript-Update erfolgt konzeptionell durch vollständiges Ersetzen von:

```text
Vendor/Ghostscript/upstream/
```

Da die erzeugten Ghostscript-Buildartefakte innerhalb dieses austauschbaren Upstream-Bereichs liegen, verschwinden sie beim Ersetzen automatisch.

Der nächste Xcode-Build stellt dadurch über die Existenzprüfung fest, dass `libgs.a` fehlt, und baut Ghostscript erneut.

---

## 16.9 Statisches Linken

Die erzeugte `libgs.a` wird vor dem Linken der App bereitgestellt und statisch in das App-Executable gelinkt.

Die statische Library wird nicht nachträglich als ungenutzte `.a`-Datei in das fertige App-Bundle kopiert.

---

# 17. Architektur

## 17.1 Schichten

```text
SwiftUI UI
    |
    v
Conversion workflow / ViewModel
    |
    +-------------------+
    |                   |
    v                   v
File services       Settings store
    |
    v
File converter abstraction
    |
    v
GhostscriptConverter
    |
    v
GhostscriptBridge
    |
    v
Ghostscript C API
```

---

## 17.2 UI-Schicht

Verantwortlich für:

- Hauptscreen
- Öffnen-Button
- PDF-Version-Segmented-Control
- Dateiauswahldialog
- Warte-Overlay
- Fehler-/Hinweisdialoge
- PDF-Präsentation
- Share-Sheet
- Schließen des PDF-Viewers

Die UI ruft Ghostscript niemals direkt auf.

---

## 17.3 Conversion Workflow

Ein zentraler Coordinator bzw. ein `@MainActor`-ViewModel koordiniert den Ablauf.

Konzeptionell:

```swift
@MainActor
final class ConversionViewModel: ObservableObject {
    func handleSelectedFile(_ url: URL)
    func handleIncomingFile(_ url: URL)
}
```

Beide Einstiegswege führen intern in denselben Verarbeitungsworkflow.

---

## 17.4 Converter-Abstraktion

Da die App nicht mehr ausschließlich PostScript-Dateien akzeptiert, wird kein semantisch zu enges Protokoll wie `PostScriptConverting` verwendet.

Beispielsweise:

```swift
protocol FileConverting {
    func convert(
        sourceURL: URL,
        outputURL: URL,
        pdfVersion: PDFVersion
    ) async throws
}
```

Implementierung:

```swift
final class GhostscriptConverter: FileConverting {
}
```

---

## 17.5 Settings Store

Ein eigener Settings-Baustein kapselt `UserDefaults`.

Beispielsweise:

```text
SettingsStore
    └── pdfVersion
```

Die UI kennt den konkreten Persistenzmechanismus nicht.

---

## 17.6 File Service

Ein eigener Service kapselt:

- Arbeitsverzeichnis
- Cleanup
- Security-Scoped Access
- Kopieren der Datei
- Bildung des PDF-Dateinamens
- Existenz-/Größenprüfungen

---

# 18. Verarbeitung einer Datei

Der vollständige Ablauf lautet:

```text
Concrete file accepted
        |
        +--> disable all controls immediately
        |
        +--> snapshot selected PDF version
        |
        +--> start 0.5 s wait timer immediately
        |
        v
await startup cleanup if still running
        |
        v
clear Current conversion
        |
        v
acquire external file access if required
        |
        v
copy source into Current conversion
        |
        v
release external file access
        |
        v
derive final PDF filename
        |
        v
create new Ghostscript instance
        |
        v
run Ghostscript
        |
        v
destroy Ghostscript instance
        |
        v
validate output
        |
        v
open with PDFKit
        |
        v
present PDF viewer
```

---

# 19. Erfolgskriterien einer einzelnen Konvertierung

Eine Konvertierung gilt nur dann als erfolgreich, wenn alle folgenden Bedingungen erfüllt sind:

1. Ghostscript beendet die Konvertierung ohne relevanten Conversion-Fehler.
2. Die erwartete PDF-Ausgabedatei existiert.
3. Die PDF-Ausgabedatei ist nicht leer.
4. PDFKit kann daraus ein gültiges `PDFDocument` erzeugen.

Erst danach wird der PDF-Viewer präsentiert.

---

# 20. PDF-Viewer

## 20.1 Präsentation

Nach erfolgreicher Konvertierung wird der PDF-Viewer automatisch als vollflächige systemkonforme modale Ansicht präsentiert.

Konzeptionell kann hierfür SwiftUI `fullScreenCover` verwendet werden.

Eine bestimmte Einflugrichtung oder eigene Präsentationsanimation wird nicht vorgeschrieben.

Die Standardanimation des Systems wird verwendet.

---

## 20.2 PDFKit

Die PDF-Darstellung basiert auf PDFKit.

Anforderungen:

- automatische initiale Skalierung (`autoScales`)
- normales Scrollen mehrseitiger PDFs
- Pinch-to-Zoom
- automatische Anpassung an Orientierungsänderungen
- keine PDF-Bearbeitung
- keine Annotationen
- keine Thumbnail-Navigation
- keine zusätzliche Seitenleiste

---

## 20.3 Toolbar

Die obere Steuerleiste enthält:

```text
[ Share ]                                  [ Close ]
```

Share befindet sich ganz links.

Close befindet sich ganz rechts.

Die sichtbaren Texte werden lokalisiert.

---

# 21. Status des PDF-Viewers

Die Konvertierung ist **bereits abgeschlossen**, sobald:

1. das erzeugte PDF erfolgreich validiert wurde und
2. der PDF-Viewer präsentiert wird.

Der Zustand

```text
showingPDF
```

ist kein Busy-Zustand der Conversion Engine.

Der Viewer zeigt lediglich das Ergebnis einer bereits abgeschlossenen Konvertierung.

---

## 21.1 Neue Datei bei geöffnetem Viewer

Wird bei geöffnetem PDF-Viewer eine neue Datei zur Verarbeitung angenommen:

1. wird der Viewer geschlossen;
2. das Arbeitsverzeichnis wird vollständig geleert;
3. der neue Verarbeitungsworkflow startet.

Die neue Datei ersetzt somit das bisher angezeigte Ergebnis.

---

# 22. Teilen des PDFs

Der Share-Button öffnet das systemeigene Share-Sheet für genau die PDF-Datei, die auch im Viewer angezeigt wird.

Es wird keine separate Share-Kopie erzeugt.

Der sichtbare und tatsächlich verwendete Dateiname ist der bereits unter Abschnitt 9 berechnete PDF-Dateiname.

---

## 22.1 Verhalten nach dem Share-Sheet

Wird das Share-Sheet geschlossen:

- unabhängig davon, ob tatsächlich geteilt wurde oder der Benutzer abgebrochen hat;
- bleibt der PDF-Viewer geöffnet;
- bleibt das Arbeitsverzeichnis unverändert;
- bleibt dieselbe PDF-Datei verfügbar.

---

## 22.2 Share-Sheet als Busy-Zustand

Solange das Share-Sheet geöffnet ist, gilt die App für neue Dateiübernahmen als beschäftigt.

Eine neu eingehende Datei wird in diesem Zustand nicht angenommen.

Es gibt keine Warteschlange.

---

# 23. Busy-Verhalten

## 23.1 Laufende Verarbeitung

Während einer laufenden Verarbeitung wird keine zweite Datei angenommen.

Eine neu eingehende Datei:

- wird nicht kopiert;
- wird nicht vorgemerkt;
- startet keine zweite Konvertierung;
- beeinflusst die laufende Konvertierung nicht.

Es erscheint ein modaler Hinweis mit:

`Dismiss`

---

## 23.2 Keine Queue

Die App führt keine Warteschlange für Konvertierungen.

Es gibt höchstens einen aktiven Verarbeitungsauftrag.

---

## 23.3 Fehlerdialog als Fortsetzung des Vorgangs

Nach einem Konvertierungsfehler gilt der Vorgang logisch solange als aktiv, wie der Fehlerdialog sichtbar ist.

Erst wenn der Benutzer auf

`Dismiss`

tippt, wird der alte Vorgang logisch abgeschlossen und die App kehrt in den normalen bereiten Zustand zurück.

Eine während des Fehlerdialogs eintreffende Datei wird behandelt, als würde die vorherige Konvertierung noch laufen.

---

# 24. Fehlerbehandlung

Mindestens folgende Fehlergruppen werden unterschieden:

- Startup-/Working-Directory-Cleanup fehlgeschlagen
- Eingabedatei kann nicht gelesen werden
- Security-Scoped Access kann nicht sinnvoll genutzt werden
- Eingabedatei kann nicht kopiert werden
- Ghostscript-Instanz kann nicht erzeugt werden
- Ghostscript kann nicht initialisiert werden
- Ghostscript-Konvertierung schlägt fehl
- PDF-Ausgabedatei fehlt
- PDF-Ausgabedatei ist leer
- PDFKit kann das erzeugte PDF nicht öffnen

Die UI interpretiert keine Ghostscript-internen Return-Codes.

Die Ghostscript-Integrationsschicht liefert strukturierte Fehlerinformationen an Swift.

---

## 24.1 Fehlerdialog

Bei einem Verarbeitungsfehler erscheint ein modaler Dialog mit:

- verständlicher allgemeiner Fehlermeldung;
- Ghostscript-Diagnose, falls vorhanden;
- Ghostscript-Return-Code, falls vorhanden;
- Button `Dismiss`.

Die sichtbaren UI-Bestandteile werden lokalisiert.

Die technische Ghostscript-Diagnose selbst wird nicht übersetzt.

---

## 24.2 Ghostscript-Diagnose

Priorität:

```text
stderr available?
    |
   yes --> first 300 characters of stderr
    |
    no
    |
stdout available?
    |
   yes --> first 300 characters of stdout
```

Danach wird, soweit vorhanden, der numerische Ghostscript-Return-Code ergänzt.

---

## 24.3 UI nach Fehler

Während der Fehlerdialog sichtbar ist:

- bleiben die regulären Bedienelemente deaktiviert;
- wird keine neue Konvertierung angenommen.

Nach `Dismiss`:

```text
error state
    |
    v
Dismiss
    |
    v
idle
```

---

# 25. Zustandsmodell

Die Implementierung soll Verarbeitung und Präsentation logisch trennen.

Ein mögliches Modell ist:

```text
Processing:
    idle
    processing

Presentation:
    none
    pdf
    shareSheet
    error
    notice
```

Wesentliche Regeln:

- `processing` ist busy.
- `shareSheet` ist für neue Dateien busy.
- ein Conversion-`error` bleibt bis `Dismiss` logisch busy.
- `pdf` allein ist **nicht** busy.
- bei `pdf` darf eine neue Konvertierung beginnen; der Viewer wird dafür geschlossen.

Die konkrete Swift-Typstruktur kann davon abweichen, solange diese Semantik eingehalten wird.

---

# 26. Verhalten im Hintergrund

Es wird keine spezielle Background-Execution-Infrastruktur implementiert.

Wechselt die App während einer Konvertierung in den Hintergrund:

- darf iOS die App suspendieren;
- die App garantiert keine Fertigstellung im Hintergrund;
- beim späteren Fortsetzen wird der bestehende Vorgang soweit vom System ermöglicht fortgeführt.

---

# 27. Vorgeschlagene Swift-Struktur

```text
App/
├── iPS2PDFApp.swift
│
├── Models/
│   ├── PDFVersion.swift
│   ├── ProcessingState.swift
│   └── ConversionError.swift
│
├── Views/
│   ├── ContentView.swift
│   ├── PDFViewer.swift
│   └── ProcessingOverlay.swift
│
├── ViewModels/
│   └── ConversionViewModel.swift
│
├── Services/
│   ├── FileConverting.swift
│   ├── GhostscriptConverter.swift
│   ├── WorkingDirectoryService.swift
│   ├── IncomingFileHandler.swift
│   └── SettingsStore.swift
│
└── Localization/
    ├── English
    └── German
```

Zusätzlich:

```text
GhostscriptIntegration/
├── GhostscriptBridge.h
├── GhostscriptBridge.c
└── BuildIntegration/
```

und:

```text
Vendor/
└── Ghostscript/
    └── upstream/
        └── <unmodified Ghostscript source tree>
```

Die konkrete Xcode-Gruppenstruktur darf abweichen, sofern die beschriebenen Verantwortlichkeiten erhalten bleiben.

---

# 28. Abnahmekriterien

Die erste Version gilt als funktional umgesetzt, wenn alle folgenden Anforderungen erfüllt sind:

- iOS 26 und iPadOS 26 werden unterstützt.
- Die App verwendet eine einzige Scene bzw. ein einziges Fenster.
- Englisch ist Entwicklungssprache und Basissprache.
- Deutsche UI-Lokalisierung ist vollständig vorhanden.
- Der Hauptscreen enthält Öffnen-Button und PDF-Version-Segmented-Control.
- PDF 1.2, 1.3 und 1.4 sind auswählbar.
- PDF 1.3 ist der Default.
- Die Einstellung wird über gekapselte `UserDefaults`-Getter/-Setter persistiert.
- Fehlende oder ungültige Settings werden auf PDF 1.3 repariert.
- Der Datei-Picker akzeptiert jede reguläre Datei.
- Ordner werden nicht akzeptiert.
- Der Datei-Picker erlaubt nur eine Datei.
- „Öffnen mit iPS2PDF“ wird unterstützt.
- Eine separate Share Extension existiert nicht.
- Mehrfachübergaben werden vollständig abgelehnt.
- Jede akzeptierte Datei wird ohne Typ-/Inhaltsprüfung an denselben Ghostscript-Workflow gegeben.
- Es gibt genau ein Arbeitsverzeichnis `Current conversion`.
- Das Arbeitsverzeichnis wird beim App-Start asynchron bereinigt.
- Das Arbeitsverzeichnis wird vor jeder neuen Dateiübernahme geleert.
- Jede externe Datei wird vor Ghostscript lokal kopiert.
- Security-Scoped Access wird nur für die lokale Übernahme gehalten.
- Die Quelldatei behält im Arbeitsverzeichnis ihren ursprünglichen Namen.
- Die PDF-Ausgabe erhält den definierten endgültigen Namen.
- `.pdf` wird immer klein geschrieben.
- Eine vorhandene Nicht-PDF-Endung wird ersetzt.
- Bei fehlender Endung wird `.pdf` angehängt.
- Bei vorhandener PDF-Endung wird zusätzlich `.pdf` angehängt.
- Nach Annahme einer konkreten Datei wird die UI sofort deaktiviert.
- Der 0,5-Sekunden-Timer startet sofort mit Annahme der Datei.
- Nach 0,5 Sekunden erscheint bei noch laufendem Vorgang das abgedunkelte Warte-Overlay.
- Es gibt keinen Cancel-Button.
- Nicht-UI-Arbeit ist `async`/`await`-basiert und blockiert den MainActor nicht.
- Die Ghostscript-Shellskripte werden unter iOS nicht ausgeführt.
- Ihre relevante Argumentsemantik wird in der Bridge nachgebildet.
- Für jede Konvertierung wird eine neue Ghostscript-Instanz erzeugt.
- `stderr` bzw. ersatzweise `stdout` wird für Fehlerdiagnosen erfasst.
- Maximal die ersten 300 Diagnosezeichen werden angezeigt.
- Der Ghostscript-Return-Code wird angezeigt, sofern vorhanden.
- Ghostscript wird über das offizielle Upstream-iOS-Buildscript gebaut.
- Die App besitzt kein separates eigenes Ghostscript-Buildsystem.
- Das Originalscript im Upstream wird nicht dauerhaft verändert.
- Eine Arbeitskopie darf für moderne Xcode-Ziele gepatcht werden.
- Device und Simulator verwenden getrennte `libgs.a`-Artefakte.
- Die Entscheidung über einen Ghostscript-Rebuild erfolgt allein per Existenzprüfung.
- Das Ersetzen des Upstream-Ordners entfernt auch die darin liegenden Buildartefakte.
- `libgs.a` wird statisch in die App gelinkt.
- Eine erfolgreiche Konvertierung erzeugt eine existierende, nicht leere und von PDFKit lesbare PDF-Datei.
- Das PDF wird anschließend automatisch vollflächig angezeigt.
- PDFKit unterstützt Scrollen, Auto-Scaling und Pinch-to-Zoom.
- Der Viewer bietet keine Bearbeitungs- oder Annotationsfunktionen.
- Share befindet sich oben links.
- Close befindet sich oben rechts.
- Das Share-Sheet teilt exakt die angezeigte PDF-Datei.
- Nach Schließen des Share-Sheets bleibt der PDF-Viewer geöffnet.
- Ein offenes Share-Sheet blockiert neue Dateien.
- Ein normal geöffneter PDF-Viewer blockiert neue Konvertierungen nicht.
- Bei einer neuen Konvertierung wird der vorhandene Viewer geschlossen und das Temp-Verzeichnis geleert.
- Parallele Konvertierungen und Conversion-Queues existieren nicht.
- Fehler werden über modale Dialoge mit `Dismiss` angezeigt.
- Während eines Fehlerdialogs gilt der alte Vorgang bis `Dismiss` weiterhin als aktiv.
- Nach Schließen des PDF-Viewers wird das Arbeitsverzeichnis geleert.

---

# 29. Nicht-Ziele

Nicht Bestandteil der ersten Version sind:

- Bearbeitung von Eingabedateien
- Bearbeitung von PDFs
- PDF-Annotation
- Dokumentenbibliothek
- Konvertierungshistorie
- Cloud-Synchronisation
- Batch-Konvertierung
- parallele Konvertierung
- Conversion Queue
- Mehrfensterbetrieb
- Share Extension
- Dateityp- oder Inhaltsanalyse vor Ghostscript
- eigene Parser für Shell-Skripte
- eigene Parser für Dateinamen
- eigene manuelle Ghostscript-Source-Dateilisten
- eigener Ghostscript-Buildsystem-Ersatz
- weitere PDF-Versionen
- vom Benutzer konfigurierbare Ghostscript-Optionen
- Benutzerabbruch einer laufenden Konvertierung
- garantierte Hintergrundkonvertierung

---

# 30. Zusammenfassung

Der zentrale Runtime-Workflow lautet:

```text
Open file / Open with iPS2PDF
            |
            v
Concrete file accepted
            |
            +--> lock UI immediately
            |
            +--> start 0.5 s timer
            |
            v
Await startup cleanup if necessary
            |
            v
Clear Current conversion
            |
            v
Copy input locally
            |
            v
Ghostscript conversion
            |
            v
Validate PDF
            |
            v
Present PDF
            |
       +----+----+
       |         |
     Share      Close
```

Der zentrale Build-Workflow lautet:

```text
Xcode build
    |
    v
required libgs.a exists?
    |
 +--+--+
 |     |
yes    no
 |     |
 |     v
 |  use official Ghostscript iOS build script
 |     |
 |  patch working copy if necessary
 |     |
 |  build platform-specific libgs.a
 |     |
 +-----+
    |
    v
link libgs.a statically
    |
    v
build iPS2PDF
```

Das Design verfolgt damit drei zentrale Prinzipien:

1. **Ein einziger deterministischer Datei-Workflow für alle Eingaben.**
2. **Klare Trennung zwischen SwiftUI, Workflow, Dateioperationen und Ghostscript.**
3. **Möglichst geringe eigene Ghostscript-Buildlogik bei gleichzeitig reproduzierbarer iOS-Integration.**