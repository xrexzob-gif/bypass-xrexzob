/* =========================================================
   XREXZOB STUDIO
   AUDIO DEVELOPER
   Local Audio Speed Processor
   ========================================================= */

const audioInput = document.getElementById("audioInput");
const dropZone = document.getElementById("dropZone");

const fileBox = document.getElementById("fileBox");
const fileName = document.getElementById("fileName");
const fileInfo = document.getElementById("fileInfo");
const removeFile = document.getElementById("removeFile");

const previewBox = document.getElementById("previewBox");
const audioPreview = document.getElementById("audioPreview");
const durationLabel = document.getElementById("durationLabel");

const processBtn = document.getElementById("processBtn");

const progressBar = document.getElementById("progressBar");
const progressPercent = document.getElementById("progressPercent");
const statusText = document.getElementById("statusText");

const selectedSpeed = document.getElementById("selectedSpeed");
const customBtn = document.getElementById("customBtn");
const presets = document.querySelectorAll(".preset[data-speed]");

let selectedFile = null;
let selectedMultiplier = 1.00;


/* =========================================================
   LOADING SCREEN
   ========================================================= */

window.addEventListener("load", () => {

  setTimeout(() => {
    const loading = document.getElementById("loadingScreen");

    if (loading) {
      loading.classList.add("hide");
    }
  }, 1700);

});


/* =========================================================
   FILE INPUT
   ========================================================= */

dropZone.addEventListener("click", () => {
  audioInput.click();
});


audioInput.addEventListener("change", () => {

  if (audioInput.files.length > 0) {
    handleFile(audioInput.files[0]);
  }

});


/* =========================================================
   DRAG & DROP
   ========================================================= */

["dragenter", "dragover"].forEach(eventName => {

  dropZone.addEventListener(eventName, event => {

    event.preventDefault();
    event.stopPropagation();

    dropZone.classList.add("dragover");

  });

});


["dragleave", "drop"].forEach(eventName => {

  dropZone.addEventListener(eventName, event => {

    event.preventDefault();
    event.stopPropagation();

    dropZone.classList.remove("dragover");

  });

});


dropZone.addEventListener("drop", event => {

  const files = event.dataTransfer.files;

  if (files.length > 0) {
    handleFile(files[0]);
  }

});


/* =========================================================
   HANDLE FILE
   ========================================================= */

function handleFile(file) {

  const validTypes = [
    "audio/mpeg",
    "audio/mp3",
    "audio/wav",
    "audio/x-wav",
    "audio/wave"
  ];

  const extension = file.name
    .split(".")
    .pop()
    .toLowerCase();

  const validExtension =
    extension === "mp3" ||
    extension === "wav";

  if (!validTypes.includes(file.type) && !validExtension) {

    alert("File harus berupa MP3 atau WAV.");

    return;
  }

  selectedFile = file;

  fileName.textContent = file.name;
  fileInfo.textContent =
    `${formatBytes(file.size)} • ${extension.toUpperCase()}`;

  fileBox.classList.remove("hidden");
  previewBox.classList.remove("hidden");

  processBtn.disabled = false;

  const url = URL.createObjectURL(file);

  audioPreview.src = url;

  statusText.textContent = "FILE READY";
  setProgress(0);

  audioPreview.onloadedmetadata = () => {

    durationLabel.textContent =
      formatTime(audioPreview.duration);

  };

}


/* =========================================================
   REMOVE FILE
   ========================================================= */

removeFile.addEventListener("click", event => {

  event.stopPropagation();

  selectedFile = null;

  audioInput.value = "";

  fileBox.classList.add("hidden");
  previewBox.classList.add("hidden");

  audioPreview.pause();
  audioPreview.removeAttribute("src");
  audioPreview.load();

  processBtn.disabled = true;

  statusText.textContent = "READY";
  setProgress(0);

});


/* =========================================================
   SPEED PRESETS
   ========================================================= */

presets.forEach(button => {

  button.addEventListener("click", () => {

    presets.forEach(btn => {
      btn.classList.remove("active");
    });

    button.classList.add("active");

    selectedMultiplier =
      Number(button.dataset.speed);

    selectedSpeed.textContent =
      `${selectedMultiplier.toFixed(2)}x`;

    statusText.textContent = "PRESET SELECTED";

  });

});


/* =========================================================
   CUSTOM SPEED
   ========================================================= */

customBtn.addEventListener("click", () => {

  let value = prompt(
    "Masukkan multiplier custom.\nContoh: 1.25, 1.5, 2, 2.32",
    selectedMultiplier.toFixed(2)
  );

  if (value === null) {
    return;
  }

  value = Number(value);

  if (!Number.isFinite(value) || value <= 0) {

    alert("Multiplier tidak valid.");

    return;
  }

  if (value > 10) {

    alert("Multiplier maksimal 10x.");

    return;
  }

  presets.forEach(btn => {
    btn.classList.remove("active");
  });

  customBtn.classList.add("active");

  selectedMultiplier = value;

  selectedSpeed.textContent =
    `${value.toFixed(2)}x`;

  statusText.textContent =
    "CUSTOM SPEED SELECTED";

});


/* =========================================================
   PROCESS BUTTON
   ========================================================= */

processBtn.addEventListener("click", async () => {

  if (!selectedFile) {

    alert("Pilih audio terlebih dahulu.");

    return;
  }

  if (selectedMultiplier <= 0) {

    alert("Speed tidak valid.");

    return;
  }

  processBtn.disabled = true;

  try {

    await processAudio();

  } catch (error) {

    console.error(error);

    statusText.textContent = "ERROR";

    alert(
      "Gagal memproses audio.\n\n" +
      "Detail: " + error.message
    );

  } finally {

    processBtn.disabled = false;

  }

});


/* =========================================================
   PROCESS AUDIO
   ========================================================= */

async function processAudio() {

  setProgress(5);
  statusText.textContent = "READING AUDIO";

  const arrayBuffer =
    await selectedFile.arrayBuffer();

  setProgress(15);
  statusText.textContent = "DECODING AUDIO";

  const AudioContextClass =
    window.AudioContext ||
    window.webkitAudioContext;

  if (!AudioContextClass) {
    throw new Error(
      "Browser tidak mendukung Web Audio API."
    );
  }

  const audioContext =
    new AudioContextClass();

  let audioBuffer;

  try {

    audioBuffer =
      await audioContext.decodeAudioData(
        arrayBuffer.slice(0)
      );

  } finally {

    await audioContext.close();

  }

  setProgress(30);
  statusText.textContent = "PREPARING RENDER";

  const inputLength = audioBuffer.length;

  /*
    Speed lebih cepat = durasi output lebih pendek.

    Contoh:
    2x speed
    10 detik input
    = sekitar 5 detik output
  */

  const outputLength =
    Math.max(
      1,
      Math.ceil(inputLength / selectedMultiplier)
    );

  const sampleRate =
    audioBuffer.sampleRate;

  const channels =
    audioBuffer.numberOfChannels;

  const offlineContext =
    new OfflineAudioContext(
      channels,
      outputLength,
      sampleRate
    );

  const source =
    offlineContext.createBufferSource();

  source.buffer = audioBuffer;

  source.playbackRate.value =
    selectedMultiplier;

  source.connect(
    offlineContext.destination
  );

  source.start(0);

  setProgress(40);
  statusText.textContent = "RENDERING AUDIO";

  const renderedBuffer =
    await offlineContext.startRendering();

  setProgress(75);
  statusText.textContent = "ENCODING WAV";

  const wavBlob =
    audioBufferToWav(renderedBuffer);

  setProgress(90);
  statusText.textContent = "CREATING DOWNLOAD";

  const baseName =
    selectedFile.name
      .replace(/\.[^/.]+$/, "");

  const speedText =
    selectedMultiplier
      .toFixed(2)
      .replace(".", "_");

  const outputName =
    `${baseName}_xrexzob_${speedText}x.wav`;

  downloadBlob(
    wavBlob,
    outputName
  );

  setProgress(100);

  statusText.textContent =
    "COMPLETE • DOWNLOAD STARTED";

}


/* =========================================================
   PROGRESS
   ========================================================= */

function setProgress(value) {

  value = Math.max(
    0,
    Math.min(100, value)
  );

  progressBar.style.width =
    `${value}%`;

  progressPercent.textContent =
    `${Math.round(value)}%`;

}


/* =========================================================
   DOWNLOAD
   ========================================================= */

function downloadBlob(blob, filename) {

  const url =
    URL.createObjectURL(blob);

  const link =
    document.createElement("a");

  link.href = url;
  link.download = filename;

  document.body.appendChild(link);

  link.click();

  link.remove();

  setTimeout(() => {
    URL.revokeObjectURL(url);
  }, 2000);

}


/* =========================================================
   WAV ENCODER
   ========================================================= */

function audioBufferToWav(buffer) {

  const numberOfChannels =
    buffer.numberOfChannels;

  const sampleRate =
    buffer.sampleRate;

  const format = 1;
  const bitDepth = 16;

  const channelData = [];

  for (
    let channel = 0;
    channel < numberOfChannels;
    channel++
  ) {

    channelData.push(
      buffer.getChannelData(channel)
    );

  }

  const samples =
    buffer.length;

  const blockAlign =
    numberOfChannels *
    bitDepth / 8;

  const byteRate =
    sampleRate *
    blockAlign;

  const dataSize =
    samples *
    blockAlign;

  const bufferSize =
    44 + dataSize;

  const arrayBuffer =
    new ArrayBuffer(bufferSize);

  const view =
    new DataView(arrayBuffer);


  /* RIFF */

  writeString(
    view,
    0,
    "RIFF"
  );

  view.setUint32(
    4,
    36 + dataSize,
    true
  );

  writeString(
    view,
    8,
    "WAVE"
  );


  /* fmt */

  writeString(
    view,
    12,
    "fmt "
  );

  view.setUint32(
    16,
    16,
    true
  );

  view.setUint16(
    20,
    format,
    true
  );

  view.setUint16(
    22,
    numberOfChannels,
    true
  );

  view.setUint32(
    24,
    sampleRate,
    true
  );

  view.setUint32(
    28,
    byteRate,
    true
  );

  view.setUint16(
    32,
    blockAlign,
    true
  );

  view.setUint16(
    34,
    bitDepth,
    true
  );


  /* data */

  writeString(
    view,
    36,
    "data"
  );

  view.setUint32(
    40,
    dataSize,
    true
  );


  /* PCM */

  let offset = 44;

  for (let i = 0; i < samples; i++) {

    for (
      let channel = 0;
      channel < numberOfChannels;
      channel++
    ) {

      let sample =
        channelData[channel][i];

      sample =
        Math.max(
          -1,
          Math.min(1, sample)
        );

      const intSample =
        sample < 0
          ? sample * 0x8000
          : sample * 0x7FFF;

      view.setInt16(
        offset,
        intSample,
        true
      );

      offset += 2;

    }

  }

  return new Blob(
    [arrayBuffer],
    {
      type: "audio/wav"
    }
  );

}


/* =========================================================
   WRITE STRING
   ========================================================= */

function writeString(view, offset, string) {

  for (let i = 0; i < string.length; i++) {

    view.setUint8(
      offset + i,
      string.charCodeAt(i)
    );

  }

}


/* =========================================================
   FORMAT BYTES
   ========================================================= */

function formatBytes(bytes) {

  if (bytes === 0) {
    return "0 Bytes";
  }

  const units = [
    "Bytes",
    "KB",
    "MB",
    "GB"
  ];

  const index =
    Math.floor(
      Math.log(bytes) /
      Math.log(1024)
    );

  return (
    parseFloat(
      (bytes /
      Math.pow(1024, index))
      .toFixed(2)
    ) +
    " " +
    units[index]
  );

}


/* =========================================================
   FORMAT TIME
   ========================================================= */

function formatTime(seconds) {

  if (!Number.isFinite(seconds)) {
    return "00:00";
  }

  const minutes =
    Math.floor(seconds / 60);

  const secs =
    Math.floor(seconds % 60);

  return (
    String(minutes).padStart(2, "0") +
    ":" +
    String(secs).padStart(2, "0")
  );

}
