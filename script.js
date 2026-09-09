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
  statusText.textContent = "ENCODING OGG";

  // Konversi buffer ke WebM/OGG Blob menggunakan MediaRecorder API bawaan browser
  const oggBlob = await audioBufferToOgg(renderedBuffer);

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
    `${baseName}_xrexzob_${speedText}x.ogg`;

  downloadBlob(
    oggBlob,
    outputName
  );

  setProgress(100);

  statusText.textContent =
    "COMPLETE • DOWNLOAD STARTED";

}


/* =========================================================
   OGG ENCODER (Menggunakan MediaStreamDestination & MediaRecorder)
   ========================================================= */

async function audioBufferToOgg(buffer) {
  const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  const dest = audioCtx.createMediaStreamDestination();
  const source = audioCtx.createBufferSource();
  
  source.buffer = buffer;
  source.connect(dest);
  
  // Pilih mimeType OGG jika didukung browser, fallback ke webm jika tidak
  const options = { mimeType: 'audio/ogg;codecs=opus' };
  const mediaRecorder = new MediaRecorder(dest.stream, MediaRecorder.isTypeSupported('audio/ogg;codecs=opus') ? options : { mimeType: 'audio/webm;codecs=opus' });
  
  const chunks = [];
  mediaRecorder.ondataavailable = e => chunks.push(e.data);
  
  return new Promise((resolve) => {
    mediaRecorder.onstop = () => {
      const blob = new Blob(chunks, { type: 'audio/ogg' });
      audioCtx.close();
      resolve(blob);
    };

    mediaRecorder.start();
    source.start(0);
    
    // Hentikan perekaman otomatis setelah durasi buffer selesai
    setTimeout(() => {
      mediaRecorder.stop();
      source.stop();
    }, (buffer.duration * 1000) + 100);
  });
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
