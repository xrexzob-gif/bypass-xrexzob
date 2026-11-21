
const express = require("express");
const cors = require("cors");

const app = express();

app.use(cors());
app.use(express.json());

app.get("/", (req, res) => {
  res.send("ZOB MP3 BACKEND ONLINE 🔥");
});

app.post("/api/convert", async (req, res) => {
  const { url } = req.body || {};

  if (!url) {
    return res.status(400).json({
      error: "Link belum dimasukkan"
    });
  }

  try {
    const parsed = new URL(url);

    if (!["http:", "https:"].includes(parsed.protocol)) {
      throw new Error("URL tidak valid");
    }

    res.status(501).json({
      error: "Mesin konversi belum dipasang. Endpoint siap menerima integrasi sumber audio yang mengizinkan download."
    });

  } catch (error) {
    res.status(400).json({
      error: "Format link tidak valid"
    });
  }
});

const PORT = process.env.PORT || 3000;

app.listen(PORT, "0.0.0.0", () => {
  console.log("ZOB MP3 BACKEND berjalan di port " + PORT);
});
