# Software Design Description – iPS2PDF

## 1. Zweck

iPS2PDF ist eine iOS-/iPadOS-App mit SwiftUI und eine native MacOS-App mit AppKit. Sie nimmt eine beliebige reguläre Datei entgegen, konvertiert diese über Ghostscript in eine PDF-Datei und zeigt das erzeugte PDF anschließend systemnah an.

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
- MacOS 15 oder neuer
- SwiftUI für iOS und iPadOS
- AppKit für MacOS
- Swift
- PDFKit
- Ghostscript als statisch eingebundene Library

Die iOS-/iPadOS-App unterstützt Hoch- und Querformat. Das native MacOS-Target baut universal für `arm64` und `x86_64`.

Die iOS-/iPadOS-App ist eine **Single-Scene-/Single-Window-App**. Mehrere unabhängige iPS2PDF-Fenster werden auf iPadOS nicht unterstützt. Das MacOS-Target ist dagegen dokumentbasiert und unterstützt mehrere unabhängige PDF-Fenster.

Neue Swift-Dateien enthalten möglichst genau einen obersten nominalen Typ (`class`, `struct`, `enum`, `actor` oder `protocol`). iOS und iPadOS verwenden SwiftUI. Das MacOS-App-Target verwendet ausschließlich AppKit und linkt SwiftUI nicht. Gemeinsame Fachlogik bleibt UI-unabhängig.

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

Der Segmented Controller hat eine feste Breite und wird nicht auf die gesamte verfügbare Bildschirmbreite gestreckt.

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

Auf dem Mac, wenn die iPad-Version der App ausgeführt wird, kann eine einzelne Datei auch aus dem Finder in das App-Fenster gezogen werden. Sie durchläuft anschließend denselben Verarbeitungsworkflow wie eine über den Datei-Picker ausgewählte Datei.

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

# 5. Externe Übergaben

## 5.1 Grundprinzip

Die App unterstützt die Übergabe von Dateien über den iOS-/iPadOS-Mechanismus **„Öffnen mit iPS2PDF“**.

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

## 5.5 Markierter PostScript-Text über die Share Extension

Für markierten Text existiert eine schlanke Share Extension. Sie akzeptiert genau Text, schreibt ihn als `SharedText.ps` in die gemeinsame App Group und aktiviert die Haupt-App über das registrierte URL-Schema `ips2pdf://share-pending`.

Die Share Extension führt ausdrücklich keine Konvertierung aus. Sie enthält und linkt weder Ghostscript noch PDFKit und besitzt keinen eigenen Konvertierungshelper. Ihre sichtbare Oberfläche ist vollständig leer. Nach `viewDidAppear` und erfolgreicher Dateiablage wartet sie 550 ms. Danach ermittelt sie die öffentliche `UIWindowScene` ihrer sichtbaren Extension-Ansicht, beendet die Share-Anfrage und ruft erst im Completion-Handler von `completeRequest` die öffentliche Methode `UIScene.open(_:options:completionHandler:)` auf. Diese Reihenfolge verhindert, dass das Schließen der noch aktiven Share-Session eine bereits angeforderte App-Aktivierung verwirft.

Die Haupt-App beansprucht die hinterlegte Datei genau einmal, kopiert sie in ein privates temporäres Staging-Verzeichnis und startet denselben Verarbeitungsworkflow wie bei allen anderen Eingaben. Läuft bereits eine Konvertierung, wird die Share-Übergabe still verworfen. Die eigentliche Ghostscript-Konvertierung wird von der Haupt-App an `iPS2PDFSecurity` delegiert. Nach erfolgreicher Konvertierung zeigt die Haupt-App das PDF automatisch an.

App, Share Extension und Ghostscript-Extension besitzen dieselbe App Group. In ihr liegen ausschließlich der aktive Übergabe- bzw. Konvertierungsjob und keine dauerhaften Einstellungen, Joboptions oder ICC-Profile.

Ist beim Aktivierungsversuch noch keine `UIWindowScene` verfügbar, bleibt die leere Extension-Ansicht sichtbar und kann über die Systemgeste geschlossen werden. Lehnt das System das Öffnen erst nach dem Beenden der Share-Anfrage ab, bleibt die bereits abgelegte Übergabe für einen manuellen App-Start erhalten.

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
Copy source file into the private app workspace
      |
      v
Stage input and active Joboptions in ConversionInput
      |
      v
Trigger Ghostscript through XPC
      |
      v
Read output.pdf from ConversionOutput
      |
      v
Validate generated PDF
      |
      v
Present PDF
```

Die Dateiendung beeinflusst die Ghostscript-Argumente nicht.

---

# 7. Arbeits- und Übergabeverzeichnisse

## 7.1 Privates Arbeitsverzeichnis der App

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

Zusätzlich enthält die gemeinsame App Group genau drei app-eigene, flüchtige Verzeichnisse:

```text
ShareInbox/       Share Extension → Haupt-App
ConversionInput/ Haupt-App → Ghostscript-Extension
ConversionOutput/Ghostscript-Extension → Haupt-App
```

Es gibt keine Job-UUID, keine Queue und keine parallelen Jobs. Die Haupt-App legt `ConversionInput/ready` erst nach vollständiger Vorbereitung des Jobs an. Die XPC-Nachricht startet lediglich die Verarbeitung und enthält keinen Dokumentinhalt.

Dauerhafte Joboptions und ICC-Profile liegen ausschließlich im privaten Application-Support-Verzeichnis der Haupt-App. Für einen aktiven Job benötigte Daten werden nach `ConversionInput` kopiert.

---

## 7.2 Bereinigung beim App-Start

Beim Start der App werden das Verzeichnis `Current conversion` und veraltete app-eigene Inhalte der App Group asynchron bereinigt. Eine bereits vollständig bereitgestellte `ShareInbox` bleibt erhalten, bis die App sie beansprucht. Systemverwaltete Einträge des App-Group-Containers werden nie gelöscht.

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

Nach einem Fehler während Dateiübernahme oder Konvertierung werden das private Arbeitsverzeichnis und alle app-eigenen Übergabeverzeichnisse vollständig bereinigt, bevor der Fehlerzustand abgeschlossen wird. Dies gilt auch dann, wenn der Ghostscript-Prozess unerwartet stirbt.

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

Im privaten Arbeitsverzeichnis erfolgt keine generische Umbenennung in `input`. Für die anschließende Übergabe an die Ghostscript-Extension wird dieselbe Datei unverändert nach `ConversionInput/input` kopiert. Der Inhalt wird weder klassifiziert noch verändert.

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

Ist die letzte Dateiendung bereits `pdf`, bleibt der abgeleitete Ausgabename unverändert. Eingabe und Ausgabe kollidieren trotzdem nicht, weil die Ausgabe in einem eigenen Unterverzeichnis liegt. Ghostscript schreibt die PDF dabei vollständig neu.

Beispiele:

```text
Dokument.pdf
→ Dokument.pdf

Dokument.PDF
→ Dokument.pdf

Dokument.Pdf
→ Dokument.pdf
```

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

1. Die Bytes aus `stdout` und `stderr` werden in der Reihenfolge ihrer Callback-Aufrufe unverändert in `ConversionOutput/journal.log` geschrieben.
2. Die App fügt keine Präfixe, Start-/End-Markierungen oder sonstigen eigenen Logging-Zeilen in dieses Journal ein.
3. Das Journal ist als Schutz vor unbegrenztem Wachstum auf 1 MiB begrenzt. Bis zu dieser Sicherheitsgrenze bleibt die Ghostscript-Ausgabe bytegetreu erhalten.
4. Der Fehlerdialog zeigt die letzten 2.000 Zeichen der erfassten Diagnose; die Detailansicht zeigt das vollständig erfasste Journal.
5. Zusätzlich wird der numerische Ghostscript-Return-Code angezeigt, sofern Ghostscript einen geliefert hat.

Der Ghostscript-Text wird nicht übersetzt oder semantisch interpretiert.

Er darf technisch bzw. kryptisch sein, da er primär der Diagnose dient.

---

# 16. Ghostscript-Build

## 16.1 Upstream-Code

Das Ghostscript-Archiv liegt im Projekt unter:

```text
Vendor/Ghostscript/*.tar.gz
```

Die Build-Einstellung `GHOSTSCRIPT_ARCHIVE_PATH` des Aggregate-Targets verweist auf das konkrete Archiv. Ändert sich bei einem Update dessen Dateiname, wird diese Einstellung entsprechend angepasst.

Beim Build wird der Sourcecode in ein nur für diesen Build erzeugtes Arbeitsverzeichnis nach folgendem Muster entpackt:

```text
$(PROJECT_TEMP_DIR)/GhostscriptBuild.<variant>.<zufall>/
```

Dieser Bereich liegt standardmäßig in Xcodes Derived Data und wird nach Abschluss oder Abbruch des Ghostscript-Builds entfernt. Nur die benötigten Build-Artefakte bleiben erhalten.

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
<temporäres Upstream-Verzeichnis>/ios/build_ios_gslib.sh
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

Device und Simulator sowie unterschiedliche SDK-, Architektur- und Deployment-Target-Varianten verwenden getrennte Ghostscript-Artefakte.

Konzeptionell:

```text
$(PROJECT_TEMP_DIR)/GhostscriptArtifacts/
└── <SDK>-<Architektur>-ios<Deployment-Target>/
    ├── lib/
    │   └── libgs.a
    ├── include/
    │   ├── iapi.h
    │   └── gserrors.h
    ├── resources/
    │   ├── PDFA_def.ps
    │   └── srgb.icc
    └── build.stamp
```

Die genaue interne Pfadstruktur darf technisch angepasst werden, solange inkompatible Varianten getrennt bleiben.

---

## 16.7 Inkrementeller Aggregate-Build

Ein gemeinsames Xcode-Aggregate-Target `Build Ghostscript` ist eine Dependency des Haupt-App-Konvertierungshelpers `iPS2PDFSecurity`. Die Share Extension besitzt keine Abhängigkeit auf dieses Aggregate-Target.

Das Build-Script deklariert mindestens folgende Inputs:

```text
Scripts/build_ghostscript_iOS.sh
Vendor/Ghostscript/<Ghostscript source archive>.tar.gz
```

Als Outputs werden die statische Library, benötigte Header, PDF/A-Ressourcen und ein erst nach vollständigem Erfolg erzeugter Build-Stamp deklariert.

Die Xcode-Dependency-Analysis entscheidet anhand dieser Inputs und Outputs, ob das Aggregate-Build-Script ausgeführt werden muss. Unveränderte Artefakte werden ohne erneuten Scriptaufruf wiederverwendet. Der Build-Stamp enthält zusätzlich Diagnoseinformationen und Prüfsummen, ist jedoch keine separate Versionsdatenbank.

Das Aggregate-Target ist ausdrücklich auf `arm64` konfiguriert, da die integrierte Patchlogik nur diese Architektur unterstützt.

---

## 16.8 Ghostscript-Update

Ein Ghostscript-Update erfolgt durch Ersetzen des Archivs unter:

```text
Vendor/Ghostscript/*.tar.gz
```

Ändert sich der Dateiname, wird zusätzlich `GHOSTSCRIPT_ARCHIVE_PATH` im Aggregate-Target angepasst. Da das konkrete Archiv als Build-Input deklariert ist, baut Xcode die betroffene Ghostscript-Variante beim nächsten Build automatisch neu. Das manuelle Löschen von Derived Data ist dafür nicht erforderlich.

Ein Clean oder das Löschen von Derived Data entfernt die erzeugten Artefakte weiterhin vollständig und erzwingt beim nächsten Build einen Neuaufbau.

---

## 16.9 Statisches Linken

Die erzeugte `libgs.a` wird vor dem Linken bereitgestellt und aus dem gemeinsamen Artefaktverzeichnis statisch ausschließlich in das Executable von `iPS2PDFSecurity` gelinkt.

Die statische Library wird nicht nachträglich als ungenutzte `.a`-Datei in das fertige App-Bundle kopiert.

Der Helper besitzt eine kleine, inkrementelle Build-Phase `Install Ghostscript Resources`. Sie kopiert die benötigten Ghostscript-Ressourcen aus dem gemeinsamen Artefaktverzeichnis in sein Bundle. Der ressourcenspezifische Kopiervorgang ist vom Ghostscript-Compiler-Build getrennt. Das Bundle der Share Extension enthält keine Ghostscript-Ressourcen.

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
clear ConversionInput and ConversionOutput
        |
        v
copy source unchanged to ConversionInput/input
        |
        v
copy active Joboptions and required user profiles to ConversionInput
        |
        v
publish ConversionInput/ready
        |
        v
send scalar control metadata through XPC
        |
        v
create new Ghostscript instance in iPS2PDFSecurity
        |
        v
run Ghostscript
        |
        v
destroy Ghostscript instance
        |
        v
publish ConversionOutput/output.pdf and journal.log
        |
        v
copy the PDF into the private app workspace
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

- Die erste Seite wird initial vollständig im verfügbaren Viewer-Bereich dargestellt.
- normales Scrollen mehrseitiger PDFs
- Pinch-to-Zoom
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

`stdout` und `stderr` werden nicht getrennt priorisiert. Beide Ghostscript-Streams gelangen in der Reihenfolge ihrer Callback-Aufrufe unverändert in dasselbe Journal. Der Fehlerdialog zeigt dessen letzte 2.000 Zeichen, während die Detailansicht die vollständig erfasste Diagnose bis zur Sicherheitsgrenze von 1 MiB enthält.

Soweit vorhanden, wird der numerische Ghostscript-Return-Code separat ergänzt. Dieser Zusatz verändert den Ghostscript-Text selbst nicht.

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

# 27. Swift- und Projektstruktur

```text
Sources/
├── Shared/
│   ├── AppCore/
│   │   ├── Conversion/
│   │   ├── Joboptions/
│   │   ├── Models/
│   │   └── Services/
│   ├── GhostscriptClient/
│   ├── GhostscriptRuntime/
│   │   ├── GhostscriptBridge/
│   │   ├── Profiles/
│   │   ├── RequestHandling/
│   │   └── Resources/
│   ├── IPC/
│   │   ├── AppGroup/
│   │   ├── GhostscriptControl/
│   │   ├── iOSShare/
│   │   └── MacOSXPC/
│   ├── MacOSGhostscriptRuntime/
│   └── Resources/
└── Targets/
    ├── iOSApp/
    │   └── AppUI/
    ├── iOSShareExtension/
    ├── iOSGhostscriptExtension/
    ├── MacOSApp/
    │   └── Settings/
    ├── MacOSGhostscriptRuntime/
    ├── MacOSGhostscriptXPC/
    ├── MacOSQuickLookPreview/
    └── MacOSThumbnailExtension/
BuildSupport/
└── Targets/        # Info.plist und Entitlements ohne Target-Membership
```

Die physische Struktur und Xcodes Navigatorstruktur sind identisch. `Sources` ist als eine einzige blaue `PBXFileSystemSynchronizedRootGroup` eingebunden; `Shared`, `Targets` und alle fachlichen Zwischenordner erscheinen dadurch ebenfalls durchgehend als reale, synchronisierte Ordner. `BuildSupport`, `Scripts`, `BundledResources`, `Vendor` und `Tests` bleiben ebenfalls synchronisierte Root-Gruppen. Alle von mehreren Targets kompilierten Quellen stehen sichtbar unter `Sources/Shared`, targetspezifische Implementierungen unter `Sources/Targets`. Plists und Entitlements liegen im nicht kompilierten `BuildSupport/Targets`-Baum und erzeugen dadurch keine impliziten Resource-Memberships.

Jedes Produkt-Target verwendet ausschließlich die konkreten synchronisierten Komponenten, die es kompiliert. Diese Build-Wurzeln werden nicht zusätzlich im Navigator angezeigt. Die globale `Sources`-Navigatorwurzel ist bei keinem Target Build-Eingang. Es gibt weder `EXCLUDED_SOURCE_FILE_NAMES`-/`INCLUDED_SOURCE_FILE_NAMES`-Filter noch `PBXFileSystemSynchronizedBuildFileExceptionSet`-Objekte. Jede Swift-Datei enthält höchstens einen obersten nominalen Typ; Erweiterungen werden bei Bedarf in einer eigenen `Typ+Rolle.swift`-Datei abgelegt.

Projekteigene Plattformbezeichner verwenden durchgehend `MacOS`. Von Apple definierte technische Schreibweisen wie `#if os(macOS)`, `SDKROOT = macosx` und `MACOSX_DEPLOYMENT_TARGET` bleiben unverändert. Die Projektdatei bleibt im Xcode-26-kompatiblen Format und verwendet keine erst mit Xcode 27 eingeführten Projektobjekttypen.

Weitere unveränderte Projektbereiche:

```text
BundledResources/
Scripts/
Tests/
Vendor/
└── Ghostscript/
    └── <Ghostscript source archive>.tar.gz
```

Der entpackte, unveränderte Ghostscript-Sourcecode liegt nur in einem temporären Arbeitsverzeichnis unter `$(PROJECT_TEMP_DIR)` und wird nach dem Build entfernt. Die benötigten Ergebnisse liegen unter `$(PROJECT_TEMP_DIR)/GhostscriptArtifacts/`.

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
- Markierter PostScript-Text kann über die Share Extension an die Haupt-App übergeben werden.
- Die Share Extension konvertiert nicht und enthält weder Ghostscript noch PDFKit.
- Mehrfachübergaben werden vollständig abgelehnt.
- Jede akzeptierte Datei wird ohne Typ-/Inhaltsprüfung an denselben Ghostscript-Workflow gegeben.
- Es gibt genau ein privates Arbeitsverzeichnis `Current conversion` und genau die drei flüchtigen App-Group-Verzeichnisse `ShareInbox`, `ConversionInput` und `ConversionOutput`.
- App, Share Extension und Ghostscript-Extension verwenden dieselbe App Group.
- Die App Group enthält keine dauerhaften Joboptions, Einstellungen oder ICC-Profile.
- XPC überträgt nur Steuerdaten und keinen Dateiinhalt.
- Es gibt keine Job-UUID und keine parallelen Jobs.
- Das Arbeitsverzeichnis wird beim App-Start asynchron bereinigt.
- Das Arbeitsverzeichnis wird vor jeder neuen Dateiübernahme geleert.
- Jede externe Datei wird vor Ghostscript lokal kopiert.
- Security-Scoped Access wird nur für die lokale Übernahme gehalten.
- Die Quelldatei behält im Arbeitsverzeichnis ihren ursprünglichen Namen.
- Die PDF-Ausgabe erhält den definierten endgültigen Namen.
- `.pdf` wird immer klein geschrieben.
- Eine vorhandene Nicht-PDF-Endung wird ersetzt.
- Bei fehlender Endung wird `.pdf` angehängt.
- Bei vorhandener PDF-Endung bleibt der Ausgabename auf `.pdf`; Ghostscript schreibt die Datei im getrennten Ausgabeverzeichnis neu.
- Nach Annahme einer konkreten Datei wird die UI sofort deaktiviert.
- Der 0,5-Sekunden-Timer startet sofort mit Annahme der Datei.
- Nach 0,5 Sekunden erscheint bei noch laufendem Vorgang das abgedunkelte Warte-Overlay.
- Es gibt keinen Cancel-Button.
- Nicht-UI-Arbeit ist `async`/`await`-basiert und blockiert den MainActor nicht.
- Die Ghostscript-Shellskripte werden unter iOS nicht ausgeführt.
- Ihre relevante Argumentsemantik wird in der Bridge nachgebildet.
- Für jede Konvertierung wird eine neue Ghostscript-Instanz erzeugt.
- Ghostscripts `stderr` und `stdout` werden unverändert für Fehlerdiagnosen erfasst; eigene Start-/End-Markierungen werden nicht ergänzt.
- Der Fehlerdialog zeigt die letzten 2.000 Diagnosezeichen; die Detailansicht enthält die vollständig erfasste Ausgabe bis zur Sicherheitsgrenze von 1 MiB.
- Der Ghostscript-Return-Code wird angezeigt, sofern vorhanden.
- Ghostscript wird über das offizielle Upstream-iOS-Buildscript gebaut.
- Die App besitzt kein separates eigenes Ghostscript-Buildsystem.
- Das Originalscript im Upstream wird nicht dauerhaft verändert.
- Eine Arbeitskopie darf für moderne Xcode-Ziele gepatcht werden.
- Device, Simulator und inkompatible Build-Varianten verwenden getrennte `libgs.a`-Artefakte.
- Ein gemeinsames Aggregate-Target baut jede benötigte Ghostscript-Variante innerhalb eines Build-Graphen höchstens einmal.
- Xcodes Input-/Output-Dependency-Analysis entscheidet über einen Ghostscript-Rebuild.
- Ein Austausch des deklarierten Ghostscript-Archivs löst automatisch einen Neuaufbau aus.
- `libgs.a` wird aus einem gemeinsamen Artefaktverzeichnis statisch ausschließlich in `iPS2PDFSecurity` gelinkt.
- Ghostscript- und PDF/A-Ressourcen werden ausschließlich im Konvertierungshelper installiert.
- Eine erfolgreiche Konvertierung erzeugt eine existierende, nicht leere und von PDFKit lesbare PDF-Datei.
- Das PDF wird anschließend automatisch vollflächig angezeigt.
- Die erste PDF-Seite wird initial vollständig angezeigt; PDFKit unterstützt anschließend Scrollen und Pinch-to-Zoom.
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

Nicht Bestandteil der iOS-/iPadOS-Oberfläche bzw. der plattformübergreifenden ersten Version sind:

- Bearbeitung von Eingabedateien
- Bearbeitung von PDFs
- PDF-Annotation
- Dokumentenbibliothek
- Konvertierungshistorie
- Cloud-Synchronisation
- Batch-Konvertierung
- parallele Konvertierung
- eine vom Benutzer verwaltete Batch- oder Conversion Queue
- Mehrfensterbetrieb auf iOS/iPadOS
- Dateityp- oder Inhaltsanalyse vor Ghostscript
- eigene Parser für Shell-Skripte
- eigene Parser für Dateinamen
- eigene manuelle Ghostscript-Source-Dateilisten
- eigener Ghostscript-Buildsystem-Ersatz
- weitere PDF-Versionen
- Benutzerabbruch einer laufenden Konvertierung
- garantierte Hintergrundkonvertierung
- eine Quick-Look-Extension für PostScript oder EPS

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
Clear ConversionInput and ConversionOutput
            |
            v
Stage input, active Joboptions and profiles in ConversionInput
            |
            v
Publish ready marker
            |
            v
Trigger Ghostscript extension through control-only XPC
            |
            v
Ghostscript reads ConversionInput and publishes ConversionOutput/output.pdf
            |
            v
Validate PDF
            |
            v
Copy PDF into the private Output directory
            |
            v
Clear transient App Group job data
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
2. **Klare Trennung zwischen plattformspezifischer UI, Workflow, Dateioperationen und Ghostscript.**
3. **Möglichst geringe eigene Ghostscript-Buildlogik bei gleichzeitig reproduzierbarer iOS-Integration.**

---

# 31. Native MacOS-Erweiterung

## 31.1 Target und Plattform

Das Projekt enthält zusätzlich das native App-Target `iPS2PDF MacOS` und den eingebetteten XPC-Service `iPS2PDFMacOSGhostscript`. Beide haben ein Deployment-Target von MacOS 15.0 und werden universal für `arm64` und `x86_64` gebaut.

Die MacOS-App enthält keine Share Extension. Eine Quick-Look-Extension für `.ps` oder `.eps` ist ausdrücklich zurückgestellt.

## 31.2 Dokumentfenster und Eingaben

Die akzeptierten Dateitypen werden gegenüber iOS nicht erweitert oder eingeschränkt:

- `de.cafe-megabyte.joboptions` als `Owner`;
- `public.data` als `Alternate`.

Eine Datei kann über **Ablage > Öffnen**, Finder-Doppelklick bzw. **Öffnen mit** oder durch Ziehen auf das App-Icon übergeben werden. Jede Konvertierungsdatei erzeugt sofort ein eigenes `NSDocument`-Fenster. Mehrere Fenster dürfen unabhängig voneinander auf ihr PDF warten und bereits fertige PDFs anzeigen, obwohl Ghostscript-Jobs seriell abgearbeitet werden. Die inhaltliche Unterscheidung zwischen Joboptions-Import und Konvertierung erfolgt im gemeinsamen Router.

## 31.3 AppKit und Einstellungen

Die sichtbare MacOS-Oberfläche wird vollständig mit AppKit implementiert. Das MacOS-App-Target enthält weder `import SwiftUI` noch einen `NSHostingController` und linkt SwiftUI nicht.

Unter **iPS2PDF > Einstellungen** erscheint zunächst ein kompakter AppKit-Auswahlscreen für aktive Joboptions, PDF-Version und PDF/A-Kompatibilität. **Konfigurieren** öffnet einen nativen, Distiller-artig gegliederten Detail-Editor mit den Bereichen Allgemein, Bilder, Schriften, Farbe, Erweitert, Standards und Zusätzlich. Die Verwaltung der Joboptions und die Bildrichtlinien sind ebenfalls native AppKit-Sheets.

Der Detail-Editor arbeitet in einer eigenen temporären Bearbeitungssitzung. Jede Änderung wird sofort und verlustfrei in eine isolierte Arbeitskopie geschrieben. Konsistenzreparaturen betreffen ebenfalls nur diese Kopie. **OK** übernimmt geänderte Benutzer-Joboptions atomar beziehungsweise legt für geänderte gebündelte Joboptions genau eine Benutzerkopie an; **Abbrechen** verwirft die gesamte Sitzung. Verwaiste Sitzungsverzeichnisse werden beim nächsten Öffnen der Einstellungen bereinigt.

Die zugrunde liegende Joboptions-Schicht ist für beide Plattformen identisch: verschachtelte Schlüsselpfade, String- und Encoding-Erhalt, zusammengesetzte semantische Aktionen sowie die deterministische Konsistenzanalyse liegen unter `Shared/AppCore`. Der Konverter erhält ausschließlich einen bereits analysierten effektiven Snapshot und nimmt keine versteckten Zweitkorrekturen vor.

Im Bereich **Zusätzlich** steuert ein app-eigener Joboptions-Schlüssel, ob das ausgewählte Output-Intent-ICC-Profil eingebettet wird. Die Auswahl steht in den Joboptions unter `PDFXOutputIntentProfile` – auch für normales PDF und PDF/A – und ist vom Ghostscript-Farbkonvertierungsprofil `OutputICCProfile` zu unterscheiden. Normales PDF und PDF/A übernehmen den gespeicherten Schalterwert. Für PDF/X erzwingt die Konsistenzanalyse den Wert ausschließlich im effektiven Konvertierungs-Snapshot; fehlt ein Output-Intent-Profil, gilt der Schalter effektiv als ausgeschaltet. Die Detailbedienelemente bleiben dabei bedienbar, und Abweichungen erscheinen weiterhin als sichtbare Konsistenzprobleme.

Unter MacOS werden gebündelte Profilverzeichnisse vor der Übergabe an Ghostscript kanonisiert. Damit verwenden die `SAFER`-Lesefreigabe und der vom Profil-Resolver erzeugte Dateipfad dieselbe Darstellung und umgehen nicht über unterschiedliche Framework-Symlinks die exakte Ghostscript-Pfadprüfung. Die Freigabe gilt ausdrücklich nur für unmittelbare Dateien des Profilverzeichnisses.

Für PDF/X wird der effektive `OutputConditionIdentifier` an das ausgewählte Ausgabeprofil gekoppelt. Die Profilanalyse liest eine nach ICC spezifizierte `ICCHDAT`-Referenz aus dem `targ`-Tag sowie eindeutig erkennbare FOGRA-Deskriptoren älterer Charakterisierungsdaten. Für bekannte gebündelte Altprofile ohne maschinenlesbare Referenz existiert eine explizite Zuordnung. Andernfalls bleibt eine nichtleere Anwenderangabe erhalten oder es wird effektiv `Custom` verwendet; als `Info` gelangt der Anzeigename des Profils ins PDF. `OutputCondition` und `RegistryName` bleiben optional, `Trapped` wird für PDF/X effektiv auf `True` oder `False` begrenzt. Die Standards-Oberfläche zeigt die effektiven Werte, schreibt Vorschläge jedoch erst bei einer ausdrücklichen Reparatur oder direkten Anwenderänderung in die Joboptions. Das für den Auftrag bereitgestellte Ghostscript-`PDFX_def.ps` wird mit genau diesen effektiven Metadaten angepasst, sodass keine fest codierten Beispielwerte in das Ergebnis gelangen.

## 31.4 Ein gemeinsamer App-Group-Job und mehrere Fenster

Jedes MacOS-Dokument besitzt ein eigenes privates temporäres Verzeichnis. Darin werden seine Eingabe, seine effektiven Joboptions und nach Erfolg sein fertiges PDF aufbewahrt. Diese dokumentlokalen Dateien sind unabhängig von der App Group.

Ein Actor-basierter Koordinator vergibt den Zugriff auf die App Group in FIFO-Reihenfolge. Genau ein Auftrag besitzt zu einem Zeitpunkt die festen Verzeichnisse `ConversionInput` und `ConversionOutput`. Der Besitz umfasst den vollständigen Ablauf von der Bereinigung und Veröffentlichung der Eingabe bis zum Kopieren des fertigen PDFs in das dokumentlokale Verzeichnis. Erst danach wird die App Group geleert und der nächste wartende Auftrag fortgesetzt.

Damit passt ein einzelner gemeinsamer App-Group-Job zu mehreren Dokumentfenstern: Ein fertiges PDF ist bereits aus der App Group herauskopiert und bleibt im privaten Dokument-Workspace verfügbar, während der nächste Auftrag dieselben festen Übergabeverzeichnisse wiederverwendet.

Konzeptionell:

```text
Document window A ----+
Document window B ----+--> FIFO coordinator
Document window C ----+          |
                                v
                     exactly one App Group job
                                |
                                v
                         MacOS XPC service
                                |
                                v
                  copy PDF to owning document workspace
                                |
                                v
                     clear App Group, release next job
```

Es gibt keine parallelen Ghostscript-Aufrufe. Fehler eines Auftrags geben den Koordinator ebenfalls frei und blockieren nachfolgende Dokumente nicht.

## 31.5 XPC-Prozesstrennung

Ghostscript wird auf MacOS ausschließlich durch den privaten, in `Contents/XPCServices` eingebetteten Service `iPS2PDFMacOSGhostscript.xpc` geladen und ausgeführt. Nur dessen Binary linkt `libgs.a` und enthält Ghostscript-/PDF-A-Ressourcen. Die MacOS-Haupt-App linkt Ghostscript nicht.

Die Haupt-App öffnet eine `NSXPCConnection` über den Bundle-Identifier des Services. Der Service verwendet `NSXPCListener.service()` mit einem `NSRunLoop`-Service-Runloop, exportiert eine kleine Objective-C-kompatible Schnittstelle und reicht ausschließlich Property-List-codierte Steuerdaten weiter. Eingabe, Joboptions, ICC-Profile, Journal und PDF werden nicht als XPC-Nutzlast übertragen, sondern über den einen App-Group-Job ausgetauscht.

Verbindungsfehler, ungültige Antworten und das Überschreiten der Konvertierungsfrist beenden den jeweiligen Dokumentauftrag kontrolliert. Eine Antwort-Guard stellt sicher, dass konkurrierende Reply-, Fehler- und Timeout-Callbacks eine Swift-Continuation höchstens einmal fortsetzen.

## 31.6 Ghostscript-Build auf MacOS

Auch MacOS erhält Ghostscript ausschließlich als unverändertes `.tar.gz` unter `Vendor/Ghostscript`. Das Aggregate-Target `Build Ghostscript MacOS` führt folgende Schritte ausschließlich unter `$(PROJECT_TEMP_DIR)` aus:

1. Archiv in ein temporäres Buildverzeichnis entpacken;
2. das offizielle Upstream-Script `toolbin/macos_build_uni_dylib.sh` in eine Arbeitskopie kopieren;
3. die kleine deterministische Patchdatei `Scripts/ghostscript_MacOS_static.patch` auf diese Kopie anwenden;
4. statische Slices für `x86_64` und `arm64` mit Xcodes ausgewähltem MacOS-SDK und Deployment-Target 15.0 bauen;
5. beide Slices mit `lipo` zu einer universellen `libgs.a` verbinden;
6. Library, öffentliche Header und erforderliche Ressourcen atomar unter `$(PROJECT_TEMP_DIR)/GhostscriptArtifacts/` veröffentlichen.

Das Archiv und sein entpackter Inhalt werden nicht in den Projektbaum geschrieben oder dauerhaft verändert. Ein inhaltlicher Fingerprint von Archiv, Script, Patch, SDK und Deployment-Target erlaubt die Wiederverwendung unveränderter Artefakte.

## 31.7 Anzeige- und Speicherlebenszyklus

Solange noch kein PDF vorliegt, bleibt das Dokumentfenster zunächst ruhig. Nach exakt 0,5 Sekunden zeigt es einen AppKit-Fortschrittsindikator, sofern die Konvertierung noch läuft. Sobald ein PDF vollständig geschrieben und mit PDFKit validiert wurde, zeigt das Fenster es mit `PDFView` an.

Ein erzeugtes PDF ist zunächst ein ungespeichertes `NSDocument`; seine erste Speicherung ist daher **Sichern unter**. Beim Schließen eines ungespeicherten PDF-Fensters sowie beim Beenden der App verwendet AppKit die üblichen Optionen **Sichern**, **Nicht sichern** und **Abbrechen**. Während einer laufenden Konvertierung ist der Schließen-Button deaktiviert. Eine Beendigungsanforderung wartet ohne Abbruch des Ghostscript-Auftrags, bis alle laufenden Konvertierungen einen terminalen Zustand erreicht haben, und setzt danach den normalen Dokument-Speicherdialog fort.

## 31.8 Signierung

MacOS-App und XPC-Service sind sandboxed und besitzen dieselbe App-Group-Entitlement `group.de.cafe-megabyte.iPS2PDF`. Für einen produktiven oder vollständigen lokalen Lauf müssen beide neuen Bundle-Identifier sowie der App-Group-Zugriff im verwendeten Apple-Developer-Team registriert sein und mit zueinander passenden Profilen bzw. Identitäten signiert werden.
