import '../models/models.dart';

/// Generische Profile für den Start. Eigene Profile lassen sich als JSON
/// ergänzen (siehe Storage.saveProfiles).
const builtinProfiles = <FixtureProfile>[
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
];
