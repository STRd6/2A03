do ->
  styleNode = document.createElement("style")
  styleNode.innerHTML = require "./style"

  document.head.appendChild(styleNode)

TouchCanvas = require "touch-canvas"

{width, height} = require "./pixie"

canvas = TouchCanvas
  width: width
  height: height

document.body.appendChild canvas.element()

context = new AudioContext

Viz = require "./lib/viz"

masterGain = context.createGain()
masterGain.gain.value = 0.5
masterGain.connect(context.destination)

analyser = context.createAnalyser()
analyser.smoothingTimeConstant = 0

masterGain.connect(analyser)

viz = Viz(analyser)

osc = context.createOscillator()
osc.type = "triangle"
osc.frequency.value = 440

osc.connect(masterGain)
osc.start(context.currentTime)
osc.stop(context.currentTime + 2)

updateViz = ->
  console.log 'a'
  viz.draw(canvas)

  requestAnimationFrame updateViz

requestAnimationFrame updateViz