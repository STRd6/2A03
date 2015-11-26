noteFrequencies = [16.35,17.32,18.35,19.45,20.6,21.83,23.12,24.5,25.96,27.5,29.14,30.87,32.7,34.65,36.71,38.89,41.2,43.65,46.25,49,51.91,55,58.27,61.74,65.41,69.3,73.42,77.78,82.41,87.31,92.5,98,103.83,110,116.54,123.47,130.81,138.59,146.83,155.56,164.81,174.61,185,196,207.65,220,233.08,246.94,261.63,277.18,293.66,311.13,329.63,349.23,369.99,392,415.3,440,466.16,493.88,523.25,554.37,587.33,622.25,659.25,698.46,739.99,783.99,830.61,880,932.33,987.77,1046.5,1108.73,1174.66,1244.51,1318.51,1396.91,1479.98,1567.98,1661.22,1760,1864.66,1975.53,2093,2217.46,2349.32,2489.02,2637.02,2793.83,2959.96,3135.96,3322.44,3520,3729.31,3951.07,4186.01,4434.92,4698.63,4978.03,5274.04,5587.65,5919.91,6271.93,6644.88,7040,7458.62,7902.13]
noteNames = ["C","C#0","D","D#0","E","F","F#0","G","G#0","A","A#0","B","C","C#1","D","D#1","E","F","F#1","G","G#1","A","A#1","B","C","C#2","D","D#2","E","F","F#2","G","G#2","A","A#2","B","C","C#3","D","D#3","E","F","F#3","G","G#3","A","A#3","B","C","C#4","D","D#4","E","F","F#4","G","G#4","A","A#4","B","C","C#5","D","D#5","E","F","F#5","G","G#5","A","A#5","B","C","C#6","D","D#6","E","F","F#6","G","G#6","A","A#6","B","C","C#7","D","D#7","E","F","F#7","G","G#7","A","A#7","B","C","C#8","D","D#8","E","F","F#8","G","G#8","A","A#8","B"]

module.exports = ->
  lineHeight = 20
  width = 60

  data = [32...48]
  size = data.length

  # t <= 0 < 1
  draw: (canvas, t) ->
    canvas.font "bold 20px monospace"

    data.forEach (datum, line) ->
      s = line
      f = line + 1
      if s <= t * size < f
        canvas.drawRect
          x: 20
          y: line * lineHeight + 2
          width: width
          height: lineHeight
          color: "#00FF00"

      canvas.drawText
        x: 20
        y: 20 + line * lineHeight
        text: noteNames[datum]
        color: "#008800"

  update: (osc, t, dt) ->
    i = Math.floor(t * size)
    noteNumber = data[i]
    
    if noteNumber is 0
      osc.stop()
    else if noteNumber?
      frequency = noteFrequencies[noteNumber]
  
      osc.frequency.value = frequency#.setValueAtTime(frequency, )
      osc.start()
    else
      