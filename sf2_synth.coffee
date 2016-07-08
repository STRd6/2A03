SF2Parser = require "./lib/sf2_parser"

SEMITONE = Math.pow(2, 1/12)

module.exports = (buffer) ->
  parser = new SF2Parser.Parser(new Uint8Array(buffer))
  parser.parse()

  instruments = parser.getInstruments()

  banks = createAllInstruments(parser, instruments)
  drumBank = banks[128]

  bank = banks[0]
  channels = [0..15].map ->
    notes: {}

  allNotesOff: (time) ->
    channels.forEach (channel) ->
      notes = channel.notes

      Object.keys(notes).forEach (key) ->
        while currentNoteData = notes[key].shift()
          noteOff time, currentNoteData...

  pitchBend: (time, channelId, fx) ->
    channel = channels[channelId]

    notes = channel.notes

    # Update note pitch for existing notes
    Object.keys(notes).forEach (key) ->
      notes[key].forEach (note) ->
        schedulePlaybackRate(time, note[1].playbackRate, fx, note[0])

  noteOn: (time, channelId, note, velocity, state, destination) ->
    channel = channels[channelId]

    {fx, program} = state.channels[channelId]

    channel.notes[note] ||= []

    if channelId is 9 # Drum Kit (Ch. 10)
      instrument = drumBank[program][note]
    else
      instrument = bank[program][note]

    if instrument
      channel.notes[note].push noteOn time, instrument, velocity, channelId, fx, destination
    else
      console.log "No instrument for note: #{note}"

  noteOff: (time, channelId, note) ->
    channel = channels[channelId]
    channel.notes[note] ||= []

    if currentNoteData = channel.notes[note].shift()
      noteOff time, currentNoteData...

toAudioBuffer = (context, buffer, sampleRate) ->
  audioBuffer = context.createBuffer 1, buffer.length, sampleRate

  audioData = audioBuffer.getChannelData(0)
  buffer.forEach (n, i) ->
    audioData[i] = n / 32768

  return audioBuffer

createAllInstruments = (parser, instruments) ->
  banks = []
  presets = parser.getPresets()

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
  if freqVibLFO
    freqVibLFO = Math.pow(2, freqVibLFO / 1200) * 8.176

  lo = generator['keyRange'].lo
  hi = generator['keyRange'].hi

  [lo..hi].forEach (i) ->
    if (preset[i])
      return

    sampleId = getModGenAmount(generator, 'sampleID');
    sampleHeader = parser.sampleHeader[sampleId];
    preset[i] =
      'sample': parser.sample[sampleId],
      'sampleRate': sampleHeader.sampleRate,
      'basePlaybackRate': Math.pow(
        SEMITONE,
        (
          i -
          getModGenAmount(generator, 'overridingRootKey', sampleHeader.originalPitch) +
          tune + (sampleHeader.pitchCorrection / 100)
        ) * scale
      ),
      'modEnvToPitch': getModGenAmount(generator, 'modEnvToPitch') / 100,
      'scaleTuning': scale,
      'start': getModGenAmount(generator, 'startAddrsCoarseOffset') * 32768 + getModGenAmount(generator, 'startAddrsOffset'),
      'end': getModGenAmount(generator, 'endAddrsCoarseOffset') * 32768 + getModGenAmount(generator, 'endAddrsOffset'),
      'loopStart': (
        # (sampleHeader.startLoop - sampleHeader.start) +
        (sampleHeader.startLoop) +
          getModGenAmount(generator, 'startloopAddrsCoarseOffset') * 32768 +
          getModGenAmount(generator, 'startloopAddrsOffset')
        ),
      'loopEnd': (
        # (sampleHeader.endLoop - sampleHeader.start) +
        (sampleHeader.endLoop) +
          getModGenAmount(generator, 'endloopAddrsCoarseOffset') * 32768 +
          getModGenAmount(generator, 'endloopAddrsOffset')
        ),
      'volAttack':  Math.pow(2, volAttack / 1200),
      'volDecay':   Math.pow(2, volDecay / 1200),
      'volSustain': volSustain / 1000,
      'volRelease': Math.pow(2, volRelease / 1200),
      'modAttack':  Math.pow(2, modAttack / 1200),
      'modDecay':   Math.pow(2, modDecay / 1200),
      'modSustain': modSustain / 1000,
      'modRelease': Math.pow(2, modRelease / 1200),
      'initialFilterFc': getModGenAmount(generator, 'initialFilterFc', 13500),
      'modEnvToFilterFc': getModGenAmount(generator, 'modEnvToFilterFc'),
      'initialFilterQ': getModGenAmount(generator, 'initialFilterQ'),
      'freqVibLFO': freqVibLFO

getModGenAmount = (generator, enumeratorType, opt_default=0) ->
  generator[enumeratorType]?.amount ? opt_default

amountToFreq = (val) ->
  Math.pow(2, (val - 6900) / 1200) * 440

noteOn = (time, instrument, velocity, channel, fx, destination) ->
  volume = fx.volume

  context = destination.context
  sample = instrument.sample

  now = time
  sampleRate = instrument.sampleRate

  volAttack = now + instrument['volAttack']
  modAttack = now + instrument['modAttack']
  volDecay = volAttack + instrument['volDecay']
  modDecay = modAttack + instrument['modDecay']

  loopStart = instrument['loopStart'] / sampleRate
  loopEnd = instrument['loopEnd'] / sampleRate
  startTime = instrument['start'] / sampleRate

  # TODO: sample.subarray(0, instrument.end) ?
  buffer = toAudioBuffer(context, sample, sampleRate)

  # buffer source
  bufferSource = context.createBufferSource()
  bufferSource.buffer = buffer
  bufferSource.loop = (channel != 9)
  bufferSource.loopStart = loopStart
  bufferSource.loopEnd = loopEnd

  schedulePlaybackRate(now, bufferSource.playbackRate, fx, instrument)

  # audio node
  panner = context.createPanner()
  output = context.createGain()
  outputGain = output.gain

  # filter
  filter = context.createBiquadFilter()
  filter.type = "lowpass"

  # panpot
  panner.setPosition(
    Math.sin(fx.panpot * Math.PI / 2),
    0,
    Math.cos(fx.panpot * Math.PI / 2)
  )

  #---------------------------------------------------------------------------
  # Attack, Decay, Sustain
  #---------------------------------------------------------------------------
  outputGain.setValueAtTime(0, now);
  outputGain.linearRampToValueAtTime(volume * (velocity / 127), volAttack)
  outputGain.linearRampToValueAtTime(volume * (1 - instrument['volSustain']), volDecay)

  filter.Q.setValueAtTime(instrument['initialFilterQ'], now)
  baseFreq = amountToFreq(instrument['initialFilterFc'])
  peekFreq = amountToFreq(instrument['initialFilterFc'] + instrument['modEnvToFilterFc'])
  sustainFreq = baseFreq + (peekFreq - baseFreq) * (1 - instrument['modSustain'])
  filter.frequency.setValueAtTime(baseFreq, now)
  filter.frequency.linearRampToValueAtTime(peekFreq, modAttack)
  filter.frequency.linearRampToValueAtTime(sustainFreq, modDecay)

  bufferSource.connect(filter)
  filter.connect(panner)
  panner.connect(output)
  output.connect(destination)

  bufferSource.start(now, startTime)

  return [instrument, bufferSource, fx, output]

noteOff = (time, instrument, bufferSource, fx, output) ->
  volEndTime = time + instrument.volRelease
  modEndTime = time + instrument.modRelease

  #---------------------------------------------------------------------------
  # Release
  #---------------------------------------------------------------------------
  output.gain.cancelScheduledValues(time)
  output.gain.linearRampToValueAtTime(0, volEndTime)

  computedPlaybackRate = computePlaybackRate(instrument, fx)
  bufferSource.playbackRate.cancelScheduledValues(time)
  bufferSource.playbackRate.linearRampToValueAtTime(computedPlaybackRate, modEndTime)

  bufferSource.loop = false
  bufferSource.stop(volEndTime)

# pitchBend is 14-bit midi pitch bend value [0 - 16383]
computePlaybackRate = (instrument, fx) ->
  pitchBend = fx.pitchBend - 8192

  denominator = if pitchBend < 0
    8192
  else
    8191

  ratio = pitchBend / denominator
  scaleTuning = instrument.scaleTuning

  rate = Math.pow SEMITONE, fx.pitchBendSensitivity * ratio * scaleTuning

  instrument.basePlaybackRate * rate

schedulePlaybackRate = (time, playbackRate, fx, instrument) ->
  computed = computePlaybackRate(instrument, fx)

  modAttack = time + instrument.modAttack
  modDecay = modAttack + instrument.modDecay
  peekPitch = computed * Math.pow(
    SEMITONE,
    instrument.modEnvToPitch * instrument.scaleTuning
  )

  playbackRate.cancelScheduledValues(time)
  playbackRate.setValueAtTime(computed, time)
  playbackRate.linearRampToValueAtTime(peekPitch, modAttack)
  playbackRate.linearRampToValueAtTime(computed + (peekPitch - computed) * (1 - instrument.modSustain), modDecay)
