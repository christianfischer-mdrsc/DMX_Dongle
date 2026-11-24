import '../models/models.dart';

/// Generische Profile für den Start. Eigene Profile lassen sich als JSON
/// ergänzen (siehe Storage.saveProfiles).
final builtinProfiles = <FixtureProfile>[
  FixtureProfile(
    id: 'gen-dimmer-1',
    manufacturer: 'Generisch',
    name: 'Dimmer (1 Kanal)',
    builtIn: true,
    channels: [ChannelDef('Dimmer', ChannelType.dimmer)],
  ),
  FixtureProfile(
    id: 'gen-rgb-3',
    manufacturer: 'Generisch',
    name: 'RGB (3 Kanäle)',
    builtIn: true,
    channels: [
      ChannelDef('Rot', ChannelType.red),
      ChannelDef('Grün', ChannelType.green),
      ChannelDef('Blau', ChannelType.blue),
    ],
  ),
  FixtureProfile(
    id: 'gen-drgb-4',
    manufacturer: 'Generisch',
    name: 'Dimmer + RGB (4 Kanäle)',
    builtIn: true,
    channels: [
      ChannelDef('Dimmer', ChannelType.dimmer),
      ChannelDef('Rot', ChannelType.red),
      ChannelDef('Grün', ChannelType.green),
      ChannelDef('Blau', ChannelType.blue),
    ],
  ),
  FixtureProfile(
    id: 'gen-rgbw-4',
    manufacturer: 'Generisch',
    name: 'RGBW (4 Kanäle)',
    builtIn: true,
    channels: [
      ChannelDef('Rot', ChannelType.red),
      ChannelDef('Grün', ChannelType.green),
      ChannelDef('Blau', ChannelType.blue),
      ChannelDef('Weiß', ChannelType.white),
    ],
  ),
  FixtureProfile(
    id: 'gen-par-7',
    manufacturer: 'Generisch',
    name: 'LED-PAR (7 Kanäle)',
    builtIn: true,
    channels: [
      ChannelDef('Dimmer', ChannelType.dimmer),
      ChannelDef('Rot', ChannelType.red),
      ChannelDef('Grün', ChannelType.green),
      ChannelDef('Blau', ChannelType.blue),
      ChannelDef('Weiß', ChannelType.white),
      ChannelDef('Strobe', ChannelType.strobe),
      ChannelDef('Modus', ChannelType.generic),
    ],
  ),
  FixtureProfile(
    id: 'gen-mh-11',
    manufacturer: 'Generisch',
    name: 'Moving Head (11 Kanäle)',
    builtIn: true,
    channels: [
      ChannelDef('Pan', ChannelType.pan, 128),
      ChannelDef('Pan fein', ChannelType.panFine),
      ChannelDef('Tilt', ChannelType.tilt, 128),
      ChannelDef('Tilt fein', ChannelType.tiltFine),
      ChannelDef('Speed', ChannelType.speed),
      ChannelDef('Dimmer', ChannelType.dimmer),
      ChannelDef('Strobe', ChannelType.strobe),
      ChannelDef('Rot', ChannelType.red),
      ChannelDef('Grün', ChannelType.green),
      ChannelDef('Blau', ChannelType.blue),
      ChannelDef('Weiß', ChannelType.white),
    ],
  ),

  // Zwei Lichtquellen in einer Lampe: weißes Strobe-LED-Feld + RGB-Ambient
  FixtureProfile(
    id: 'varytec-sonicstrobe-7',
    manufacturer: 'Varytec',
    name: 'Colors SonicStrobe (7 Kanäle)',
    builtIn: true,
    channels: [
      ChannelDef('Dimmer', ChannelType.dimmer, 0, 'Strobe'),
      ChannelDef('Strobe', ChannelType.strobe, 0, 'Strobe', [
        ChannelRange(0, 8, 'Aus'),
        ChannelRange(9, 255, 'Strobe langsam → schnell'),
      ]),
      ChannelDef('Dimmer', ChannelType.dimmer, 0, 'Ambient'),
      ChannelDef('Strobe', ChannelType.strobe, 0, 'Ambient', [
        ChannelRange(0, 8, 'Aus'),
        ChannelRange(9, 255, 'Strobe langsam → schnell'),
      ]),
      ChannelDef('Rot', ChannelType.red, 0, 'Ambient'),
      ChannelDef('Grün', ChannelType.green, 0, 'Ambient'),
      ChannelDef('Blau', ChannelType.blue, 0, 'Ambient'),
    ],
  ),

  // ---------- Pro-Paket (Freischaltung nötig) ----------
  FixtureProfile(
    id: 'pro-bar-8rgb',
    manufacturer: 'Pro',
    name: 'LED-Bar 8×RGB (24 Kanäle)',
    builtIn: true,
    requires: 'pack.pro',
    channels: [
      for (var i = 1; i <= 8; i++) ...[
        ChannelDef('Segment $i Rot', ChannelType.red),
        ChannelDef('Segment $i Grün', ChannelType.green),
        ChannelDef('Segment $i Blau', ChannelType.blue),
      ],
    ],
  ),
  FixtureProfile(
    id: 'pro-mh-16bit',
    manufacturer: 'Pro',
    name: 'Moving Head 16 Bit (14 Kanäle)',
    builtIn: true,
    requires: 'pack.pro',
    channels: [
      ChannelDef('Pan', ChannelType.pan, 128),
      ChannelDef('Pan fein', ChannelType.panFine),
      ChannelDef('Tilt', ChannelType.tilt, 128),
      ChannelDef('Tilt fein', ChannelType.tiltFine),
      ChannelDef('Speed', ChannelType.speed),
      ChannelDef('Dimmer', ChannelType.dimmer),
      ChannelDef('Strobe', ChannelType.strobe),
      ChannelDef('Rot', ChannelType.red),
      ChannelDef('Grün', ChannelType.green),
      ChannelDef('Blau', ChannelType.blue),
      ChannelDef('Weiß', ChannelType.white),
      ChannelDef('Farbrad', ChannelType.colorWheel),
      ChannelDef('Gobo', ChannelType.gobo),
      ChannelDef('Modus', ChannelType.generic),
    ],
  ),
];
