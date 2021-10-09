# fhemDLJK
#### FHEM Module zur Anbindung eine Ultraschall Sensor Moduls

<p align="center">
  <img src=pic/Sensor_1.jpg height="450"/>
  <img src=pic/DeviceOverview.png height="450"/>
</p>

### Hardware

#### Sensor
Der Sensor ermittelt den Wasserabstand über Ultraschall. Wichtig dabei ist es daher, dass der Sensor in diesem Einsatzgebiet einen engen Winkel besitzt, da ansonsten die Zisternenwand erkannt wird und so undefinierte Abstandswerte ausgegeben werden würden.
Mit dem oben dargestellten Sensor ist diese Bedinunge gegeben. Diesen findet man z.B. hier: https://de.aliexpress.com/item/4000055598556.html oder über die G-Suche mit "Waterproof ultrasonic RS485".

#### Gehäuse
Zusätzlich wurde der Sensor in ein "Spelsberg TK PS 99-6" Leergehäuse eingebaut. So ist er zusätzlich geschützt und man kann in dem Gehäuse mit "offenen" Klemmen arbeiten. 

#### Kabel und Abschlusswiderstand
Zum Einsatz kommt eine KNX Busleitung oder Telefonleitung. Wichtig ist es, dass ein verdrilltes Adernpaar vorhanden ist, über welches der RS485 Bus angebunden ist. Zusätzlich wird am Sensor paralell zum Bus ein 120 Ohm Widerstand eingebaut, da unklar ist, ob ein solcher im Sensor vorhanden ist.

Die Belegung des Sensors ist wie folgt:
- schwarz -> GND
- braun -> 5V
- gelb -> RS485 Bus A
- blau -> RS485 Bus B

#### Schnittstelle am Server
Es genügt hierfür ein USB<->RS485 Adapter

<p align="center">
<img src="https://user-images.githubusercontent.com/48262831/110222604-b6806880-7ed3-11eb-9222-cb7f73c09996.jpg" alt="RS485 oben" height="300"/>
<img src="https://user-images.githubusercontent.com/48262831/110222514-0874be80-7ed3-11eb-9424-000616daa5ba.jpg" alt="RS485 unten" height="300"/>
</p>

*Ich selbst habe den nicht isolierten USB -> RS485 Adapter (ganz unten) im Einsatz*

### Software

#### Quelle
Da dieses Modul "inoffiziell" ist, muss man die benötigte Dateien "70_DLJK.pm" händisch in den FHEM Ordner hinein kopieren. 
Wen FHEM auf einem Linux Server läuft, muss man wie folgt vorgehen:

1. Terminal öffnen
2. Git-Repository herunterladen: `git clone https://github.com/ahermann86/fhemDLJK`
3. "70_DLJK.pm" in den FHEM Ordner kopieren `sudo cp fhemDLJK/70_DLJK.pm /opt/fhem/FHEM/`
4. Aufräumen: `sudo rm -r fhemDLJK`
5. FHEM Weboberfläche im Browser öffnen
6. Über die FHEM Befehlszeile das Modul mit reload 70_DLJK laden.

*Wenn man bereits als "admin" über das Terminal eingeloggt ist, wird "sudo" vor den cp/rm-Befehlen nicht benötigt.*

#### Rechte anpassen (Linux/Teminal)

Da das Modul mit einer Hardwareschnittstelle "redet", benötigt der FHEM Benutzer noch die nötigen Rechte dafür. Das wird über das Terminal mit folgenden Befehlen durchgeführt:

`sudo usermod -a -G dialout pi`

`sudo usermod -a -G dialout fhem`

#### Definition
Pfad der Schnittstelle herausfinden

Vor der Definition des Moduls, muss der Pfad der Schnittstelle herausgefunden werden. Das geht am einfachsten, indem man den USB<->RS485 Adapter zunächst nicht in die USB Buchse eingesteckt hat. Nun führt man im Terminal den Befehl `ls -l /dev/serial/by-path` aus. Dann steckt man den USB<->RS485 ein und führt den Befehl nochmal aus. Nach dem zweiten Ausführen ist eine Zeile hinzu gekommen, welcher der benötigte Pfad ist.

##### Syntax

`define <name> DLJK <device>`

Beispiel:

`define Zisterne_Level DLJK /dev/ttyUSB0`

oder: (wie es meiner Meinung nach besser ist)

`define Zisterne_Level DLJK /dev/serial/by-path/pci-0000:00:10.0-usb-0:1:1.0-port0`

Optional: `attr Zisterne_Level room Zisterne`

##### Attribute

Das Modul kann zusätzlich die in der Zisterne befindliche Menge an Wasser in Liter und Prozent automatisch berechnen. Dazu muss die Position des Sensors angegeben werden sowie die Gesamtmenge der Zistene.
Das wird mit den folgenden Attributen gemacht:

- CisternMinDist: Abstand zwischen Sensor und Wasseroberfläche, wenn die Zisterne voll ist
- CisternMaxDist: Abstand zwischen Sensor und Zisternenboden
- CisternVolume: Gesamtvolumen in Liter der Zisterne

<img src=pic/Attribute.png height="400"/>

Damit der Wert etwas "beruhigter" angezeit wird, gibt es das Attribut "NumStableVals". Damit kann angegeben werden, wieviel gleiche Werte gemessen werden sollen, bevor das Reading "Distance" aktualisiert wird. Wird dieses Attribut nicht angegeben, ist die Anzahl 10.

##### Readings
- Distance: über das Attribut "NumStableVals" generierter Abstand zwischen Sensor und Wasseroberfläche
- DistanceRAW: Aktueller Abstand zwischen Sensor und Wasseroberfläche
- Level: Wasserstand in Prozent
- Volume: Wasserstand in Liter

#### Aufzeichnung

<p align="center">
  <img src=pic/Verlauf.PNG width="900"/>
</p>
<p align="center">
  <img src=pic/Verlauf_Zunahme.PNG width="400"/>
  <img src=pic/Verlauf_Abnahme.PNG width="400"/>
</p>

##### Vorbereitung
Damit nicht unnötig viel aufgezeichnit wird, haben sich folgende Modulattribute bewährt:

- `attr Zisterne_Level event-min-interval .*:3600`
- `attr Zisterne_Level event-on-change-reading .*`

##### Energiemessung in ein Logfile:
- `define defmod Log_Zisterne FileLog ./log/Zisterne-%Y-%m.log Zisterne_Level:(Distance|Level|Volume):.*`
- `attr SVG_Log_Zisterne_1 room Zisterne`
- 
##### Ein Plot erzeugen:
- `define SVG_Log_Zisterne_1 SVG Log_Zisterne:SVG_Log_Zisterne_1:CURRENT`
- `attr SVG_Log_Zisterne_1 room Zisterne`
- *oder mit Create SVG plot im Logfile Modul*
- Die SVG_Log_Zisterne_1.gplot (kann in dem SVG Modul über das INTERNAL GPLOTFILE als Textblock editiert werden):

```
set terminal png transparent size <SIZE> crop
set output '<OUT>.png'
set xdata time
set timefmt "%Y-%m-%d_%H:%M:%S"
set xlabel " "
set title '<TL>'
set ytics 
set y2tics 
set grid
set ylabel "Level"
set y2label "mm"
set yrange [0:14000]
set y2range [0:2950]

#Log_Zisterne 4:Zisterne_Level.Volume\x3a::
#Log_Zisterne 4:Zisterne_Level.Distance\x3a::

plot "<IN>" using 1:2 axes x1y1 title 'Level (l)' ls l2fill lw 1 with lines,\
     "<IN>" using 1:2 axes x1y2 title 'Distance (mm)' ls l7 lw 1 with lines
```
