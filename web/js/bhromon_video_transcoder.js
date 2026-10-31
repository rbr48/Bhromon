// Shrinks a reel video for upload in the browser. The Android app compresses
// with its native transcoder, and the web build uses this module instead.
//
// mp4box.js reads an MP4 or MOV file. WebCodecs decodes the H.264 or HEVC
// video, and each frame is drawn at the target size, with the container's
// rotation applied, and encoded again as H.264. mp4-muxer writes the MP4. AAC
// audio is copied packet by packet. Other audio is decoded and encoded again.
// The libraries load on first use.
//
// Dart calls window.bhromonVideoTranscoder. Options and results are JSON, so
// the interop stays small.

const VENDOR = new URL('./vendor/', import.meta.url);
const KEYFRAME_INTERVAL_US = 2_000_000;
const AUDIO_BLOCK_FRAMES = 1024;
const QUEUE_LIMIT = 12;

let libraries = null;
let running = null;

function loadLibraries() {
  libraries ??= Promise.all([
    import(new URL('mp4box/mp4box.all.mjs', VENDOR).href),
    import(new URL('mp4-muxer/mp4-muxer.mjs', VENDOR).href),
  ]).then(([mp4box, muxer]) => ({ mp4box, muxer }));
  return libraries;
}

function isSupported() {
  return (
    typeof VideoDecoder === 'function' &&
    typeof VideoEncoder === 'function' &&
    typeof VideoFrame === 'function' &&
    typeof OffscreenCanvas === 'function'
  );
}

function pause(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function cancelledError() {
  return new DOMException('The transcode was cancelled.', 'AbortError');
}

function toMicros(ticks, timescale) {
  return Math.round((ticks * 1e6) / timescale);
}

// MP4, MOV and other ISO base media files start with a box whose type is one
// of these, at byte 4. WebM and MKV start with an EBML header instead.
const ISO_BOX_TYPES = new Set(['ftyp', 'moov', 'mdat', 'wide', 'free', 'skip']);

function isIsoBaseMedia(bytes) {
  if (bytes.byteLength < 12) return false;
  const type = String.fromCharCode(...bytes.subarray(4, 8));
  return ISO_BOX_TYPES.has(type);
}

// Parses the file's moov box. The whole file is already in memory.
function openFile(mp4box, bytes) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Reading the video timed out.')), 60_000);
    const settle = (fn) => (value) => {
      clearTimeout(timer);
      fn(value);
    };
    // Keep the mdat data, or extraction returns no samples.
    const file = mp4box.createFile(true);
    file.onError = (module, message) => settle(reject)(new Error(`${module}: ${message}`));
    file.onReady = (info) => settle(resolve)({ file, info });
    const buffer =
      bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength
        ? bytes.buffer
        : bytes.slice().buffer;
    buffer.fileStart = 0;
    file.appendBuffer(buffer);
    file.flush();
  });
}

// The rotation the container asks for, in degrees clockwise: 0, 90, 180 or 270.
function rotationDegrees(track) {
  const matrix = track.tkhd?.matrix;
  if (!matrix) return 0;
  const quarterTurns = Math.round(Math.atan2(matrix[1], matrix[0]) / (Math.PI / 2));
  return (((quarterTurns * 90) % 360) + 360) % 360;
}

// The decoder configuration record (avcC or hvcC) without its box header.
function decoderDescription(mp4box, entry) {
  const box = entry.avcC ?? entry.hvcC;
  if (!box) return null;
  const stream = new mp4box.DataStream(undefined, 0, mp4box.DataStream.BIG_ENDIAN);
  box.write(stream);
  return new Uint8Array(stream.buffer, 8, stream.position - 8);
}

// The AudioSpecificConfig inside an esds descriptor, which AAC decoders need.
function audioSpecificConfig(descriptor) {
  if (!descriptor) return null;
  if (descriptor.tag === 0x05) return descriptor.data ?? null;
  for (const child of descriptor.descs ?? []) {
    const found = audioSpecificConfig(child);
    if (found) return found;
  }
  return null;
}

// Display size after rotation, scaled so the short side and the long side each
// fit the limits, with the even dimensions the encoder needs.
function outputSize(sourceWidth, sourceHeight, rotation, maxShort, maxLong) {
  const quarterTurn = rotation === 90 || rotation === 270;
  const displayWidth = quarterTurn ? sourceHeight : sourceWidth;
  const displayHeight = quarterTurn ? sourceWidth : sourceHeight;
  const scale = Math.min(
    1,
    maxShort / Math.min(displayWidth, displayHeight),
    maxLong / Math.max(displayWidth, displayHeight),
  );
  const even = (value) => Math.max(2, Math.floor(value / 2) * 2);
  return {
    width: even(displayWidth * scale),
    height: even(displayHeight * scale),
  };
}

// Resolves once every track has delivered all of its samples, in decode order.
function extractSamples(file, tracks) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Reading the video samples timed out.')), 120_000);
    const collected = new Map(tracks.map((track) => [track.id, []]));
    file.onSamples = (id, _user, samples) => {
      const list = collected.get(id);
      for (const sample of samples) list.push(sample);
      const complete = tracks.every((track) => collected.get(track.id).length >= track.nb_samples);
      if (complete) {
        clearTimeout(timer);
        file.stop();
        resolve(collected);
      }
    };
    for (const track of tracks) file.setExtractionOptions(track.id, null, { nbSamples: 1000 });
    file.start();
  });
}

function earliestCts(samples) {
  let earliest = Infinity;
  for (const sample of samples) earliest = Math.min(earliest, sample.cts);
  return earliest;
}

// Draws one decoded frame onto the output canvas, scaled and rotated.
function drawFrame(context, frame, rotation, width, height) {
  const quarterTurn = rotation === 90 || rotation === 270;
  const drawWidth = quarterTurn ? height : width;
  const drawHeight = quarterTurn ? width : height;
  context.setTransform(1, 0, 0, 1, 0, 0);
  context.clearRect(0, 0, width, height);
  context.translate(width / 2, height / 2);
  context.rotate((rotation * Math.PI) / 180);
  context.drawImage(frame, -drawWidth / 2, -drawHeight / 2, drawWidth, drawHeight);
  context.setTransform(1, 0, 0, 1, 0, 0);
}

// The first AAC or Opus encoder the browser has for this layout, or null.
async function firstSupportedAudioCodec(numberOfChannels, sampleRate, bitrate) {
  for (const codec of ['mp4a.40.2', 'opus']) {
    try {
      const { supported } = await AudioEncoder.isConfigSupported({
        codec,
        sampleRate,
        numberOfChannels,
        bitrate,
      });
      if (supported) return codec;
    } catch (_error) {
      // Some browsers reject a codec outright. Try the next one.
    }
  }
  return null;
}

async function decodeAudio(bytes) {
  const context = new AudioContext({ sampleRate: 48000 });
  try {
    // decodeAudioData takes ownership of its input, so it gets a copy.
    return await context.decodeAudioData(bytes.slice().buffer);
  } finally {
    await context.close();
  }
}

async function encodeDecodedAudio(output, decoded, codec, bitrate, run) {
  const channels = Math.min(2, decoded.numberOfChannels);
  const sampleRate = decoded.sampleRate;
  let failure = null;
  const encoder = new AudioEncoder({
    output: (chunk, meta) => output.addAudioChunk(chunk, meta),
    error: (error) => {
      failure ??= error;
    },
  });
  encoder.configure({ codec, sampleRate, numberOfChannels: channels, bitrate });
  try {
    for (let start = 0; start < decoded.length; start += AUDIO_BLOCK_FRAMES) {
      if (run.cancelled) throw cancelledError();
      if (failure) throw failure;
      const frames = Math.min(AUDIO_BLOCK_FRAMES, decoded.length - start);
      const planar = new Float32Array(frames * channels);
      for (let channel = 0; channel < channels; channel++) {
        planar.set(decoded.getChannelData(channel).subarray(start, start + frames), channel * frames);
      }
      const audioData = new AudioData({
        format: 'f32-planar',
        sampleRate,
        numberOfFrames: frames,
        numberOfChannels: channels,
        timestamp: toMicros(start, sampleRate),
        data: planar,
      });
      try {
        encoder.encode(audioData);
      } finally {
        audioData.close();
      }
      while (encoder.encodeQueueSize > QUEUE_LIMIT) await pause(2);
    }
    await encoder.flush();
    if (failure) throw failure;
  } finally {
    if (encoder.state !== 'closed') encoder.close();
  }
}

// Decides how the audio is written. Returns null when the file has no audio.
async function planAudio(file, audioInfo, bytes, audioBitrate) {
  if (!audioInfo) return null;
  // QuickTime files keep the esds box inside the wave box.
  const sampleEntry = file.getTrackById(audioInfo.id).mdia.minf.stbl.stsd.entries[0];
  const asc = audioSpecificConfig((sampleEntry.esds ?? sampleEntry.wave?.esds)?.esd);
  if (audioInfo.codec.startsWith('mp4a.40') && asc) {
    return {
      mode: 'copy',
      track: audioInfo,
      codec: 'aac',
      numberOfChannels: audioInfo.audio.channel_count,
      sampleRate: audioInfo.audio.sample_rate,
      decoderConfig: {
        codec: audioInfo.codec,
        description: asc,
        numberOfChannels: audioInfo.audio.channel_count,
        sampleRate: audioInfo.audio.sample_rate,
      },
    };
  }
  const decoded = await decodeAudio(bytes);
  const numberOfChannels = Math.min(2, decoded.numberOfChannels);
  const encoderCodec = await firstSupportedAudioCodec(numberOfChannels, decoded.sampleRate, audioBitrate);
  if (!encoderCodec) throw new Error(`This browser cannot encode the audio (${audioInfo.codec}).`);
  return {
    mode: 'encode',
    decoded,
    encoderCodec,
    codec: encoderCodec === 'opus' ? 'opus' : 'aac',
    numberOfChannels,
    sampleRate: decoded.sampleRate,
  };
}

async function transcodeFile(mp4box, muxer, bytes, options, run) {
  const { file, info } = await openFile(mp4box, bytes);
  const videoInfo = info.videoTracks[0];
  if (!videoInfo) throw new Error('The file has no video track.');
  const videoTrack = file.getTrackById(videoInfo.id);
  const videoDescription = decoderDescription(mp4box, videoTrack.mdia.minf.stbl.stsd.entries[0]);
  if (!videoDescription) throw new Error(`Unsupported video codec ${videoInfo.codec}.`);

  const rotation = rotationDegrees(videoTrack);
  const { width, height } = outputSize(
    videoInfo.video.width,
    videoInfo.video.height,
    rotation,
    options.maxShortSide,
    options.maxLongSide,
  );
  const decoderConfig = {
    codec: videoInfo.codec,
    codedWidth: videoInfo.video.width,
    codedHeight: videoInfo.video.height,
    description: videoDescription,
  };
  if (!(await VideoDecoder.isConfigSupported(decoderConfig)).supported) {
    throw new Error(`This browser cannot decode ${videoInfo.codec}.`);
  }
  const encoderConfig = {
    codec: options.videoCodec,
    width,
    height,
    bitrate: options.videoBitrate,
    framerate: options.frameRate,
    avc: { format: 'avc' },
  };
  if (!(await VideoEncoder.isConfigSupported(encoderConfig)).supported) {
    throw new Error('This browser cannot encode H.264 at this size.');
  }

  const audio = await planAudio(file, info.audioTracks[0] ?? null, bytes, options.audioBitrate);
  const muxerOptions = {
    target: new muxer.ArrayBufferTarget(),
    video: { codec: 'avc', width, height },
    fastStart: 'in-memory',
  };
  if (audio) {
    muxerOptions.audio = {
      codec: audio.codec,
      numberOfChannels: audio.numberOfChannels,
      sampleRate: audio.sampleRate,
    };
  }
  const output = new muxer.Muxer(muxerOptions);

  const tracks = audio?.mode === 'copy' ? [videoInfo, audio.track] : [videoInfo];
  const collected = await extractSamples(file, tracks);
  const videoSamples = collected.get(videoInfo.id);
  if (videoSamples.length === 0) throw new Error('The video has no frames.');
  const videoStart = earliestCts(videoSamples);
  const totalUs = toMicros(info.duration, info.timescale);
  const frameGapUs = Math.round(1e6 / options.frameRate);

  if (audio?.mode === 'copy') {
    const audioSamples = collected.get(audio.track.id);
    const audioStart = earliestCts(audioSamples);
    audioSamples.forEach((sample, index) => {
      output.addAudioChunk(
        new EncodedAudioChunk({
          type: 'key',
          timestamp: toMicros(sample.cts - audioStart, audio.track.timescale),
          duration: toMicros(sample.duration, audio.track.timescale),
          data: sample.data,
        }),
        index === 0 ? { decoderConfig: audio.decoderConfig } : undefined,
      );
    });
  }

  let failure = null;
  let lastKeptUs = null;
  let lastKeyUs = null;
  const canvas = new OffscreenCanvas(width, height);
  const context = canvas.getContext('2d');
  context.imageSmoothingQuality = 'high';

  const encoder = new VideoEncoder({
    output: (chunk, meta) => output.addVideoChunk(chunk, meta),
    error: (error) => {
      failure ??= error;
    },
  });
  const decoder = new VideoDecoder({
    output: (frame) => {
      try {
        const timestamp = frame.timestamp;
        if (failure || run.cancelled) return;
        // Keep at most the target frame rate. Higher-rate sources drop frames.
        if (lastKeptUs !== null && timestamp - lastKeptUs < frameGapUs * 0.9) return;
        lastKeptUs = timestamp;
        drawFrame(context, frame, rotation, width, height);
        const keyFrame = lastKeyUs === null || timestamp - lastKeyUs >= KEYFRAME_INTERVAL_US;
        if (keyFrame) lastKeyUs = timestamp;
        const scaled = new VideoFrame(canvas, { timestamp, duration: frameGapUs });
        try {
          encoder.encode(scaled, { keyFrame });
        } finally {
          scaled.close();
        }
        if (run.onProgress && totalUs > 0) run.onProgress(Math.min(1, timestamp / totalUs));
      } catch (error) {
        failure ??= error;
      } finally {
        frame.close();
      }
    },
    error: (error) => {
      failure ??= error;
    },
  });

  try {
    encoder.configure(encoderConfig);
    decoder.configure(decoderConfig);
    for (const sample of videoSamples) {
      if (run.cancelled) throw cancelledError();
      if (failure) throw failure;
      while (decoder.decodeQueueSize > QUEUE_LIMIT) await pause(2);
      decoder.decode(
        new EncodedVideoChunk({
          type: sample.is_sync ? 'key' : 'delta',
          timestamp: toMicros(sample.cts - videoStart, videoInfo.timescale),
          duration: toMicros(sample.duration, videoInfo.timescale),
          data: sample.data,
        }),
      );
    }
    await decoder.flush();
    if (failure) throw failure;
    await encoder.flush();
    if (failure) throw failure;
  } finally {
    if (decoder.state !== 'closed') decoder.close();
    if (encoder.state !== 'closed') encoder.close();
  }

  if (audio?.mode === 'encode') {
    await encodeDecodedAudio(output, audio.decoded, audio.encoderCodec, options.audioBitrate, run);
  }
  if (run.cancelled) throw cancelledError();

  output.finalize();
  return new Uint8Array(output.target.buffer);
}

// The file's basic facts, for planning the encode, as JSON. Null when the file
// has no video track.
async function probe(bytes) {
  if (!isIsoBaseMedia(bytes)) return null;
  const { mp4box } = await loadLibraries();
  const { file, info } = await openFile(mp4box, bytes);
  const videoInfo = info.videoTracks[0];
  if (!videoInfo) return null;
  const rotation = rotationDegrees(file.getTrackById(videoInfo.id));
  const quarterTurn = rotation === 90 || rotation === 270;
  return JSON.stringify({
    durationSeconds: info.duration / info.timescale,
    width: quarterTurn ? videoInfo.video.height : videoInfo.video.width,
    height: quarterTurn ? videoInfo.video.width : videoInfo.video.height,
    rotation,
    videoCodec: videoInfo.codec,
    audioCodec: info.audioTracks[0]?.codec ?? null,
  });
}

// Encodes the file at the size and bitrate in optionsJson. Resolves with the
// MP4 bytes, or null when cancelled.
async function transcode(bytes, optionsJson, onProgress) {
  if (!isSupported()) throw new Error('WebCodecs is not available in this browser.');
  if (!isIsoBaseMedia(bytes)) throw new Error('Only MP4 and MOV files can be shrunk in the browser.');
  const options = {
    videoCodec: 'avc1.42001f',
    audioBitrate: 128000,
    frameRate: 30,
    ...JSON.parse(optionsJson),
  };
  const { mp4box, muxer } = await loadLibraries();
  const run = { cancelled: false, onProgress };
  running = run;
  try {
    return await transcodeFile(mp4box, muxer, bytes, options, run);
  } catch (error) {
    if (run.cancelled) return null;
    throw error;
  } finally {
    if (running === run) running = null;
  }
}

function cancel() {
  if (running) running.cancelled = true;
}

globalThis.bhromonVideoTranscoder = { isSupported, probe, transcode, cancel };
