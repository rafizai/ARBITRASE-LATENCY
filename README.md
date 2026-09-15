[PANDUAN_LATENCY.md](https://github.com/user-attachments/files/32222756/PANDUAN_LATENCY.md)
# Panduan Latency Arbitrage 2 Broker (MT5)

> ⚠️ **Baca Bagian 1 (Peringatan) dulu sampai habis. Serius. Baru lanjut.**

**File EA:**

- `FastFeedWriter.mq5` → dipasang di terminal broker **CEPAT** (penulis quote)
- `LatencyArb.mq5` → dipasang di terminal broker **LAMBAT** (pembaca + trader)

---

## 1. Peringatan penting (TL;DR bahaya)

1. **Banyak broker eksplisit MELARANG latency arbitrage.** Sanksinya nyata: profit
   dibatalkan, akun dibekukan/ditutup. Cari kata "arbitrage / latency / scalping"
   di client agreement broker sebelum akun real.
2. **Strategi ini berpacu dalam milidetik.** Dari PC rumah di Indonesia, ping ke
   server broker EU/US biasanya 150–300ms — peluang arbitrase (yang umurnya sering
   <100ms) hampir pasti sudah hilang duluan. Untuk live, praktis **wajib VPS yang
   dekat dengan server broker**.
3. Metode file-sharing di sini menambah ±10–50ms. Ini versi **edukasi**, bukan
   HFT co-location beneran (yang butuh FIX API / server sekamar dengan broker).
4. **Backtest tidak valid** untuk latency arb — Strategy Tester tidak punya 2 feed
   live yang sinkron. Satu-satunya uji yang berarti: **forward test demo**.
5. Alur aman: **DRY-RUN → demo eksekusi → (baru pertimbangkan real kecil)**.
   Jangan pernah lompat langsung ke real.

---

## 2. Cara kerja

```
Terminal FAST (broker cepat)              Terminal SLOW (broker lambat)
┌─────────────────────────┐               ┌──────────────────────────┐
│ FastFeedWriter.mq5      │   file .csv   │ LatencyArb.mq5           │
│ tulis quote tiap ~50ms ─┼──Common Files─┼─→ baca tiap ~25ms        │
└─────────────────────────┘               │ bandingkan → BUY / SELL  │
                                          └──────────────────────────┘
File: <Common>\Files\LatencyArb\FAST_EURUSD.csv  (isi: bid,ask,tick_ms,waktu)
```

Logika sinyal (dalam points broker SLOW):

- `fastBid > slowAsk + trigger` → **BUY** (slow telat naik, akan menyusul)
- `fastAsk < slowBid - trigger` → **SELL** (slow telat turun, akan menyusul)

Exit: TP virtual kecil, atau **catch-up** (slow sudah menyusul fast), atau timeout,
atau SL. Ada juga SL riil sebagai pengaman koneksi putus.

---

## 3. Syarat

- **2 akun MT5 di broker BERBEDA** (demo dulu keduanya).
- Satu broker harus terbukti **lebih cepat**: buka chart simbol yang sama di kedua
  terminal berdampingan saat news (mis. NFP, CPI, FOMC) — lihat siapa yang bergerak
  duluan. Atau jalankan paket ini mode dry-run dan amati deviasinya.
  Cara paling akurat: ukur dengan `FeedLagMeter.mq5` (lihat `PANDUAN_UKUR_FEED.md`).
- **2 terminal MT5 di 1 PC** (atau 1 VPS yang sama untuk live).

---

## 4. Install 2 MT5 di 1 PC

1. Install MT5 broker #1 seperti biasa.
2. Jalankan installer MT5 broker #2 (atau installer yang sama sekali lagi) →
   klik **Settings** di installer → **ganti folder instalasi**
   (mis. `C:\Program Files\MT5-Slow`).
3. Jalankan kedua terminal → login akun masing-masing.
4. **Jangan pakai mode portable** untuk setup ini (path Common bisa berbeda-beda).
5. Verifikasi wajib: dashboard kedua EA menampilkan **path Common yang SAMA persis**.

---

## 5. Instalasi EA

**Terminal FAST (broker cepat):**

1. F4 → copy `FastFeedWriter.mq5` ke `MQL5/Experts` → F7 (0 errors).
2. Drag ke chart mana saja → centang **Allow Algo Trading**.
3. Isi `InpSymbols` dengan nama simbol **di broker FAST** (pisahkan koma),
   mis. `EURUSD,GBPUSD,XAUUSD`.

**Terminal SLOW (broker lambat):**

1. F4 → copy `LatencyArb.mq5` ke `MQL5/Experts` → F7 (0 errors).
2. Drag ke chart simbol yang mau ditradingkan (mis. EURUSD M1).
3. Isi `InpFastSymbol` = nama simbol itu **di broker FAST**. Kosongkan jika
   namanya sama persis di kedua broker (mis. slow `EURUSD.pro` vs fast `EURUSD`
   → isi `EURUSD`).
4. **Biarkan `InpDryRun = true`** dulu. Tombol Algo Trading hijau di kedua terminal.

> Pasang multi-simbol? Boleh (1 chart = 1 simbol), tapi **magic number harus beda**
> tiap chart, mis. 88001, 88002, dst.

---

## 6. Verifikasi (urutan wajib)

1. Di FAST: dashboard writer menampilkan angka "Tulis ke-N" yang **terus bertambah**.
2. Cek file fisik: buka path Common dari dashboard →
   `Files\LatencyArb\FAST_EURUSD.csv` → buka dengan Notepad, isinya
   `bid,ask,tick,waktu` dan berubah tiap dibuka ulang.
3. Di SLOW: dashboard reader menampilkan `FAST ... umur <100 ms [FRESH]`.
   Kalau `TIDAK ADA FILE` → nama simbol salah / writer belum jalan.
   Kalau `STALE` → terminal FAST putus koneksi.
4. Tunggu news / gerakan cepat → angka **Dev BUY/SELL melonjak** → muncul
   `SINYAL ... [DRY-RUN]` di tab Experts + status dashboard berubah.

---

## 7. Parameter

**FastFeedWriter:**

| Parameter | Default | Artinya |
|-----------|---------|---------|
| InpSymbols | `EURUSD,GBPUSD,USDJPY,XAUUSD` | Simbol yang dipublish (nama di FAST) |
| InpPublishMs | `50` | Interval tulis file (ms) |

**LatencyArb (SLOW):**

| Parameter | Default | Artinya |
|-----------|---------|---------|
| InpFastSymbol | _(kosong)_ | Nama simbol di FAST (kosong = samakan chart) |
| InpPollMs | `25` | Interval baca file (ms) |
| InpMaxFeedAgeMs | `1500` | Feed lebih tua dari ini = STALE, tidak trading |
| InpTriggerPoints | `15.0` | Deviasi minimum (points SLOW). 15 pts @5-digit = 1.5 pip |
| InpMaxDevPoints | `80.0` | Lewati jika deviasi sudah kelewat jauh (ketinggalan) |
| InpMaxSpreadPoints | `30` | Tolak sinyal saat spread melebar |
| InpDryRun | `true` | `true` = sinyal saja tanpa order. **Matikan hanya jika siap live** |
| InpVolume | `0.01` | Lot per posisi |
| InpTakeProfitPoints | `25.0` | TP virtual |
| InpStopLossPoints | `50.0` | SL virtual (EA yang menutup) |
| InpMaxHoldSec | `45` | Tutup paksa setelah N detik |
| InpUseConvergenceExit | `true` | Exit saat slow sudah menyusul fast (exit utama) |
| InpUseHardSL | `true` | Pasang SL riil sebagai pengaman |
| InpCooldownSec | `10` | Jeda antar transaksi |
| InpMaxTradesPerDay | `30` | Batas transaksi harian |
| InpMaxDailyLoss | `50.0` | Stop harian (mata uang akun) |

---

## 8. Tuning awal yang disarankan

- Mulai dari **1 simbol major** (EURUSD) + dry-run 1–2 minggu termasuk minimal
  satu news besar. Catat frekuensi sinyal dan besar deviasi maksimumnya.
- Tidak pernah sinyal? Antara trigger kebesaran ATAU broker "slow"-mu ternyata
  tidak lambat. Turunkan trigger bertahap (15 → 10 → 7) sambil mengamati —
  tapi trigger terlalu kecil = sinyal palsu dari noise.
- Sinyal puluhan kali sehari tapi deviasi langsung lenyap? Broker slow-mu
  sebenarnya cepat juga → ganti pasangan broker.
- TP kecil (20–30 pts), hold pendek (30–60 dtk). Latency arb = makan gerakan
  susulan yang singkat, bukan trend.
- XAUUSD sering memberi deviasi besar tapi spread/slippage-nya juga besar —
  uji terpisah, jangan samakan setting forex.

---

## 9. Checklist menuju live (baca dengan jujur)

- [ ] Forward test **demo ≥ 4 minggu** termasuk beberapa news besar, hasil konsisten.
- [ ] Ukur ping (pojok kanan bawah MT5) ke server broker SLOW. Ratusan ms dari
      rumah = praktis mustahil profit → sewa **VPS dekat server broker**
      (tanya support broker lokasi servernya: London/NY/dll).
- [ ] Pindahkan **KEDUA terminal ke VPS yang sama** (metode file butuh 1 mesin).
- [ ] Baca TOS/client agreement broker SLOW soal arbitrase. Siapkan skenario
      terburuk: profit dibatalkan / akun dibatasi.
- [ ] Mulai modal kecil yang siap hilang. Akun **hedging** (bukan netting).
- [ ] Pahami catch-22-nya: broker "slow" yang paling menguntungkan biasanya
      market maker — yang juga paling agresif memburu trader arbitrase.

---

## 10. Troubleshooting

| Gejala | Penyebab umum & solusi |
|--------|------------------------|
| File tidak muncul di folder | Writer belum jalan / Algo Trading merah / path Common beda → samakan, bandingkan path di kedua dashboard |
| Reader: TIDAK ADA FILE | `InpFastSymbol` salah ketik (cek suffix Epidemic di FAST) |
| Feed STALE terus | Terminal FAST disconnect / internet putus / PC sleep. Pastikan kedua terminal online |
| Read error naik sesekali | Normal (tabrakan baca-tulis). Kalau masif: naikkan `InpPollMs` ke 50, kecualikan folder Common dari antivirus |
| Tidak pernah sinyal | Trigger kebesaran / jam sepi / broker tidak cukup lambat → amati Dev saat news |
| Sinyal ada tapi order gagal | Cek tab Journal; pastikan akun allow trading + dana cukup + hedging |
| Posisi tidak ke-manage | EA harus **tetap jalan** (terminal on + Algo hijau). SL riil hanya pengaman terakhir |

---

## 11. Disclaimer

Paket ini untuk **edukasi dan eksperimen**. Latency arbitrage adalah strategi
berisiko tinggi — secara teknis maupun dari sisi kepatuhan broker. Tidak ada
jaminan profit. Keputusan dan risikonya sepenuhnya milik kamu.

---

## 12. Mau dikembangkan?

Bisa aku lanjutkan, misalnya: **notifikasi Telegram** tiap sinyal/fill,
**panel multi-simbol** (1 EA pantau banyak pair), **statistik deviasi per jam**
(untuk tahu kapan broker slow paling lambat), atau **versi bridge Python**
(pengganti file agar lebih cepat). Tinggal bilang! 🚀
