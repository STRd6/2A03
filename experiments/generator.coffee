# TODO: Multi-track recording

do ->
  styleNode = document.createElement("style")
  styleNode.innerHTML = require "/style"

  document.head.appendChild(styleNode)
  document.body.classList.add "no-select"

TouchCanvas = require "touch-canvas"
Ajax = require "ajax"
ajax = Ajax().ajax
Synth = require "/sf2_synth"
Pattern = require "../pattern"

{assert} = require("../util")

ControlsTemplate = require "../templates/controls"
Controls = require "../presenters/controls"

context = new AudioContext

{width, height} = require "/pixie"
canvas = TouchCanvas
  width: width
  height: height

document.body.appendChild canvas.element()
canvas.fill('blue')

controls = Controls
  patternLength:
    min: 1
    max: 32
    value: 8
    step: 1
    type: "number"

  bpm:
    min: 1
    max: 999
    step: 1
    value: 120
    type: "number"

  volume:
    min: 0
    max: 2
    value: 1
    step: 0.1
    type: "number"

controls.volume.observe (value) -> masterGain.gain.value = value

document.body.appendChild ControlsTemplate controls

Viz = require "../lib/viz"

analyser = context.createAnalyser()
analyser.smoothingTimeConstant = 0

masterGain = context.createGain()
masterGain.connect(context.destination)
masterGain.connect(analyser)

patterns = [0...4].map ->
  Pattern()

quantize = (t, snap=0.25) ->
  n = Math.round t / snap

  return n * snap

addNote = (pattern, note, velocity) ->
  t = quantize(trackBeat)
  # t = trackBeat

  assert 0 <= t < pattern.length()

  pattern.addEvent {t, note, velocity}

{bpm, patternLength} = controls
secondsPerBeat = ->
  60 / bpm()
secondsPerPattern = ->
  secondsPerBeat() * patternLength()

cursor = 0 # beats
trackBeat = 0 # beats
lastTime = context.currentTime
noteOn = ->
noteOff = ->
# TODO: Need to separate out cursor/time update from note scheduling
scheduleUpcomingEvents = (pattern, channel) ->
  lookahead = 0.05 # seconds
  lookaheadBeats = lookahead / secondsPerBeat()
  currentTime = context.currentTime
  deltaTime = currentTime - lastTime
  lastTime = currentTime

  # Accumulate track time, wrapping around pattern
  trackBeat = (trackBeat + deltaTime / secondsPerBeat()) % patternLength() # beats
  patternBeat = trackBeat

  start = cursor # beats
  end = (trackBeat + lookaheadBeats) % patternLength() # beats

  handle = (time, channel, note, velocity) ->
    if velocity > 0
      noteOn(time, channel, note, velocity)
    else
      noteOff(time, channel, note)

  if start <= end
    events = pattern.eventsWithin(start, end).map ({t, note, velocity}) ->
      delta = (t - patternBeat) * secondsPerBeat()

      handle(currentTime + delta, channel, note, velocity)
  else
    events = pattern.eventsWithin(start).map ({t, note, velocity}) ->
      delta = (t - patternBeat) * secondsPerBeat()

      handle(currentTime + delta, channel, note, velocity)

    events = pattern.eventsWithin(0, end).map ({t, note, velocity}) ->
      delta = (t - patternBeat + patternLength()) * secondsPerBeat()

      handle(currentTime + delta, channel, note, velocity)

  cursor = end

viz = Viz(analyser)
gamut =
  min: 32
  max: 96

drawEvents = (canvas, pattern) ->
  gamutWidth = gamut.max - gamut.min
  noteHeight = canvas.height() / gamutWidth
  width = canvas.width()
  length = patternLength()

  noteTimings = pattern.events().reduce (hash, {t, note, velocity}) ->
    hash[note] ?= []
    hash[note].push [t, velocity]

    return hash
  , {}

  Object.keys(noteTimings).forEach (note) ->
    start = null
    noteTimings[note].forEach ([t, velocity]) ->
      # TODO: Handle wrap around
      if velocity
        start = t
      else
        canvas.drawRect
          x: width * start / length
          y: noteHeight * (gamut.max - note)
          width: width * (t - start) / length
          height: noteHeight
          color: "blue"

updateViz = ->
  pattern = patterns[1]
  viz.draw(canvas)
  [0, 9].forEach (channel, index) ->
    scheduleUpcomingEvents(patterns[index], channel)

  length = patternLength()

  # Draw measure lines
  [0...length].forEach (p, i) ->
    p = p / length

    alpha = (i % 4 is 0) * 0.125 + 0.25
    canvas.drawRect
      x: p * canvas.width()
      y: 0
      width: 2
      height: canvas.height()
      color: "rgba(222, 238, 214, #{alpha})"

  patternPosition = canvas.width() * trackBeat / patternLength()
  canvas.drawRect
    x: patternPosition
    y: 0
    width: 2
    height: canvas.height()
    color: "rgba(222, 238, 214, 0.75)"

  drawEvents(canvas, pattern)

  requestAnimationFrame updateViz
requestAnimationFrame updateViz

ajax "https://whimsy.space/danielx/data/bEKepHacjexwXm92b2GU_BTj2EYjaClrAaB2jWaescU",
  responseType: "arraybuffer"
.progress ({loaded, total}) ->
  console.log loaded / total
.then (buffer) ->
  synth = Synth buffer

  console.log synth
  destination = masterGain

  channelId = 0
  state =
    channels: [0..15].map ->
      fx:
        panpot: 0 # [-1, 1]
        pitchBend: 8192 # [0, 16383]
        pitchBendSensitivity: 1
        volume: 1 # [0, 1]
      program: 0

  nextProgram = (channel) ->
    state.channels[channel].program += 1

  previousProgram = (channel) ->
    state.channels[channel].program -= 1

  noteOn = (time, channel, note, velocity) ->
    synth.noteOn time, channel, note, velocity, state, destination

  noteOff = (time, channel, note) ->
    synth.noteOff time, channel, note

  prevNotes = []
  canvas.on 'touch', (p) ->
    {x, y, identifier} = p
    time = context.currentTime
    range = 108 - 21
    note = Math.floor(x * range) + 21

    prevNotes[identifier] = note
    velocity = 64

    noteOn(time, channelId, note, velocity)
  canvas.on 'release', (p) ->
    {identifier} = p
    time = context.currentTime
    note = prevNotes[identifier]

    noteOff(time, channelId, note)

  Stream = require "../lib/stream"
  {readEvent} = require "../lib/midifile"
  streamState = {}

  require("../midi_access") ({data}) ->
    event = readEvent Stream(data), true, streamState

    {subtype, noteNumber:note, channel, velocity} = event
    channel = 9

    time = context.currentTime
    switch subtype
      when "noteOn"
        addNote(patterns[1], note, velocity)
        noteOn(time, channel, note, velocity)
      when "noteOff"
        addNote(patterns[1], note, 0)
        noteOff(time, channel, note)

  mapping = """
    AWSEDFTGYHUJKOLP
  """

  recording = false
  toggleRecording = ->
    recording = !recording

  do ->
    getNote = (code) ->
      n = mapping.indexOf code.substr(-1)
      if n >= 0
        n + 60

    isDown = {}

    channel = 0
    document.addEventListener "keydown", (e) ->
      code = e.code
      note = getNote code
      time = context.currentTime

      if note
        unless isDown[code]
          isDown[code] = note

          velocity = 100
          addNote(patterns[0], note, velocity)
          noteOn(time, channel, note, velocity)
      else
        switch code
          when "BracketLeft"
            previousProgram(channel)
          when "BracketRight"
            nextProgram(channel)
          when "Space"
            toggleRecording()
          when "Enter"
            consoleWindow "https://danielx.net/coffee-console/",
              patternLength: controls.patternLength
              bpm: controls.bpm


    document.addEventListener "keyup", (e) ->
      code = e.code
      time = context.currentTime
      note = isDown[code]

      if note
        delete isDown[code]
        addNote(patterns[0], note, 0)
        noteOff(time, channel, note)

Postmaster = require "postmaster"

consoleWindow = (url, handlers, options={}) ->
  {name, width, height} = options
  width ?= 800
  height ?= 600

  childWindow = window.open url, name, "width=#{width},height=#{height}"

  postmaster = Postmaster(handlers)
  postmaster.remoteTarget = -> childWindow

  # Return a proxy for easy Postmastering
  proxy = new Proxy postmaster,
    get: (target, property, receiver) ->
      target[property] or
      (args...) ->
        target.invokeRemote property, args...

  return proxy
