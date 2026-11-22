// The AudioWorklet of paw-pod.js: plays the stereo frames that paw in the
// pod sends to the page. The page writes them into a ring in a
// SharedArrayBuffer; this processor reads them.
//
// The ring: Int32 [write, read] (in samples), then Float32 samples, left
// and right interleaved. The processor waits until `prefill` frames are
// there before it plays, and again after each underrun.

class PawPodPlayer extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const { sab, capacity, prefill } = options.processorOptions;
    this.index = new Int32Array(sab, 0, 2);
    this.ring = new Float32Array(sab, 8, capacity);
    this.capacity = capacity;
    this.prefill = prefill * 2;
    this.playing = false;
    this.stats = { played: 0, underruns: 0, peak: 0 };
    this.port.onmessage = () => this.port.postMessage({ ...this.stats, playing: this.playing });
  }

  process(_inputs, outputs) {
    const [left, right] = outputs[0];
    const write = Atomics.load(this.index, 0);
    let read = Atomics.load(this.index, 1);
    const ready = (write - read + this.capacity) % this.capacity;
    const wanted = left.length * 2;
    if (!this.playing && ready >= this.prefill) this.playing = true;
    if (this.playing && ready < wanted) {
      this.playing = false;
      this.stats.underruns += 1;
    }
    if (!this.playing) return true;
    let peak = this.stats.peak;
    for (let i = 0; i < left.length; i++) {
      const l = this.ring[read];
      const r = this.ring[read + 1];
      left[i] = l;
      if (right) right[i] = r;
      peak = Math.max(peak, Math.abs(l), Math.abs(r));
      read = (read + 2) % this.capacity;
    }
    Atomics.store(this.index, 1, read);
    this.stats.played += left.length;
    this.stats.peak = peak;
    return true;
  }
}

registerProcessor("paw-pod-player", PawPodPlayer);
