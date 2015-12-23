Ajax = require "./lib/ajax"

"bEKepHacjexwXm92b2GU_BTj2EYjaClrAaB2jWaescU" # CT4MGM
"VQHGLBy82AW4ZppTgItJm1IpquIF-042W3Ix3u7PQeQ" # Yamaha XG
loadSoundFont = ->
  SF2Parser = require "./lib/sf2_parser"
  console.log SF2Parser
  soundFontURL = "http://whimsy.space/danielx/data/bEKepHacjexwXm92b2GU_BTj2EYjaClrAaB2jWaescU"

  Ajax.getBuffer(soundFontURL)
  .then (buffer) ->
    parser = new SF2Parser.Parser(new Uint8Array(buffer))
    parser.parse()

    console.log parser

    global.parser = parser

createAllInstruments = (presets, instruments) ->
  banks = []

  presets.forEach (preset, i) ->
    presetNumber = preset.header.preset

    if (typeof preset.instrument != 'number')
      return

    instrument = instruments[preset.instrument]
    if (instrument.name.replace(/\0*$/, '') is 'EOI')
      return

    # select bank
    if (banks[preset.header.bank] is undefined)
      banks[preset.header.bank] = []

    bank = banks[preset.header.bank]
    bank[presetNumber] = []
    bank[presetNumber].name = preset.name

    instrument.info.forEach (info) ->
      createNoteInfo(parser, info, bank[presetNumber])

  return banks

createNoteInfo = (parser, info, preset) ->
  generator = info.generator

  return unless generator['keyRange'] and generator['sampleID']

  volAttack  = getModGenAmount(generator, 'attackVolEnv',  -12000)
  volDecay   = getModGenAmount(generator, 'decayVolEnv',   -12000)
  volSustain = getModGenAmount(generator, 'sustainVolEnv')
  volRelease = getModGenAmount(generator, 'releaseVolEnv', -12000)
  modAttack  = getModGenAmount(generator, 'attackModEnv',  -12000)
  modDecay   = getModGenAmount(generator, 'decayModEnv',   -12000)
  modSustain = getModGenAmount(generator, 'sustainModEnv')
  modRelease = getModGenAmount(generator, 'releaseModEnv', -12000)

  tune =
    getModGenAmount(generator, 'coarseTune') +
    getModGenAmount(generator, 'fineTune') / 100

  scale = getModGenAmount(generator, 'scaleTuning', 100) / 100
  freqVibLFO = getModGenAmount(generator, 'freqVibLFO')

  i = generator['keyRange'].lo
  il = generator['keyRange'].hi
  
  while(i <= il)
    if (preset[i]) {
      continue;
    }

    sampleId = this.getModGenAmount(generator, 'sampleID');
    sampleHeader = parser.sampleHeader[sampleId];
    preset[i] =
      'sample': parser.sample[sampleId],
      'sampleRate': sampleHeader.sampleRate,
      'basePlaybackRate': Math.pow(
        Math.pow(2, 1/12),
        (
          i -
          this.getModGenAmount(generator, 'overridingRootKey', sampleHeader.originalPitch) +
          tune + (sampleHeader.pitchCorrection / 100)
        ) * scale
      ),
      'modEnvToPitch': this.getModGenAmount(generator, 'modEnvToPitch') / 100,
      'scaleTuning': scale,
      'start':
        this.getModGenAmount(generator, 'startAddrsCoarseOffset') * 32768 +
          this.getModGenAmount(generator, 'startAddrsOffset'),
      'end':
        this.getModGenAmount(generator, 'endAddrsCoarseOffset') * 32768 +
          this.getModGenAmount(generator, 'endAddrsOffset'),
      'loopStart': (
        //(sampleHeader.startLoop - sampleHeader.start) +
        (sampleHeader.startLoop) +
          this.getModGenAmount(generator, 'startloopAddrsCoarseOffset') * 32768 +
          this.getModGenAmount(generator, 'startloopAddrsOffset')
        ),
      'loopEnd': (
        //(sampleHeader.endLoop - sampleHeader.start) +
        (sampleHeader.endLoop) +
          this.getModGenAmount(generator, 'endloopAddrsCoarseOffset') * 32768 +
          this.getModGenAmount(generator, 'endloopAddrsOffset')
        ),
      'volAttack':  Math.pow(2, volAttack / 1200),
      'volDecay':   Math.pow(2, volDecay / 1200),
      'volSustain': volSustain / 1000,
      'volRelease': Math.pow(2, volRelease / 1200),
      'modAttack':  Math.pow(2, modAttack / 1200),
      'modDecay':   Math.pow(2, modDecay / 1200),
      'modSustain': modSustain / 1000,
      'modRelease': Math.pow(2, modRelease / 1200),
      'initialFilterFc': this.getModGenAmount(generator, 'initialFilterFc', 13500),
      'modEnvToFilterFc': this.getModGenAmount(generator, 'modEnvToFilterFc'),
      'initialFilterQ': this.getModGenAmount(generator, 'initialFilterQ'),
      'freqVibLFO': freqVibLFO ? Math.pow(2, freqVibLFO / 1200) * 8.176 : void 0

    i += 1


getModGenAmount = (generator, enumeratorType, opt_default=0) ->
  generator[enumeratorType]?.amount ? opt_default

loadSoundFont()
