# Cara Mengukur: Broker Mana yang Cepat vs Lambat

"Broker cepat" = feed-nya mencapai harga baru **duluan** (leader).
"Broker lambat" = feed-nya **menyusul** belakangan (lagger).
Latency arbitrage = trading di yang lambat, berpatokan pada yang cepat.

Ada 3 metode, dari kasar sampai akurat. Pakai semuanya berurutan.

---

## Metode 1 — Visual saat news (5 menit, kasar)

1. Buka chart simbol yang **sama** (mis. EURUSD M1) di kedua terminal, berdampingan.
2. Amati saat news besar (NFP, CPI, FOMC — cek kalender forex).
3. Lihat candle/tick-nya: **terminal yang bergerak duluan = lebih cepat**.

Kelebihan: cepat. Kelemahan: subjektif, tidak ada angka pastinya.
Kalau hasilnya tidak jelas, lanjut ke Metode 2.

---

## Metode 2 — FeedLagMeter (akurat, ada angka ms-nya) ✅ disarankan

**Setup (sekali saja):**

1. Terminal broker **A**: pasang `FastFeedWriter.mq5` (versi terbaru!) →
   `InpPrefix = "A"` → `InpSymbols` = simbol yang mau diuji (mis. `EURUSD`).
2. Terminal broker **B**: pasang `FastFeedWriter.mq5` →
   `InpPrefix = "B"` → simbol yang sama (sesuaikan suffix, mis. `EURUSD.pro`).
3. Di **salah satu** terminal, pasang `FeedLagMeter.mq5` di chart simbol itu.
   Kalau nama simbol beda antar broker, isi `InpSymbolA` / `InpSymbolB`
   (kosongkan yang sama dengan chart).
4. Pastikan kedua writer jalan (dashboard "Tulis ke-N" bertambah) dan meter
   menampilkan `[OK]` untuk A dan B.

**Pengukuran:**

- Biarkan jalan melewati **jam sibuk** (sesi London/New York) atau **satu news besar**.
- Meter mencatat setiap gerakan ≥ `InpEventPoints` (default 10 pts): siapa duluan,
  siapa menyusul, berapa ms lag-nya.
- Baca **VERDICT** di dashboard, contoh:
  `A = CEPAT (lead). B menyusul rata-rata 340 ms (12 event).`

**Kriteria pasangan yang layak untuk latency arb:**

| Metrik | Bagus | Jelek |
|--------|-------|-------|
| Verdict | Satu pihak lead konsisten (rasio ≥ 2:1) | Seimbang / ties banyak |
| Rata-rata lag | Makin besar makin baik (mis. >200ms) | <50ms (peluang hilang sebelum tereksekusi) |
| Divergensi maks | > trigger + spread + buffer | Tidak pernah melewati trigger |
| Tick/mnt | Pihak FAST update lebih sering | Keduanya jarang update (feed jelek) |

> Catatan: setelah verdict keluar, kamu bisa langsung trading tanpa ubah writer —
> di `LatencyArb.mq5` (sisi SLOW) cukup isi `InpFeedPrefix` = `"A"` atau `"B"`
> sesuai pihak yang FAST, dan `InpFastSymbol` = nama simbol di pihak FAST.

---

## Metode 3 — Pendukung: ping & tick rate

- **Tick rate** sudah ditampilkan meter (tick/mnt tiap broker). Bukan penentu utama,
  tapi feed yang update 5x lebih sering biasanya memang lebih "hidup".
- **Ping** (pojok kanan bawah MT5): mengukur koneksi ke server trading, **BUKAN**
  kecepatan feed. Broker bisa ping kecil tapi quote-nya difilter/delay
  (virtual dealer). Jadi ping hanya info tambahan.

---

## Jebakan umum (wajib paham)

1. **Jangan bandingkan timestamp tick antar broker.** Jam server tiap broker beda
   (zona waktu/clock drift). Alat ini benar karena memakai **jam PC yang sama**
   (`GetTickCount`) untuk kedua feed.
2. **Quote lambat ≠ pasti bisa profit.** Kalau broker slow mengisi order-mu dengan
   slippage besar / requote ke harga baru, edge-nya hilang. Setelah verdict bagus,
   **wajib uji fill di demo**: bandingkan harga sinyal vs harga fill aktual.
3. **Perilaku broker bisa berubah**: lambat saat sepi tapi cepat saat news (atau
   sebaliknya). Ukur di **kondisi yang mau kamu tradingkan** (biasanya jam news).
4. Ukur **per simbol**. EURUSD bisa layak sementara XAUUSD tidak (atau sebaliknya).
5. Kedua terminal harus di **PC/VPS yang sama** dan online bersamaan.

---

## Setelah tahu siapa FAST & SLOW

Lanjut ke `PANDUAN_LATENCY.md` bagian 5 (instalasi) dengan konfigurasi:

- Writer prefix `"FAST"` (atau pertahankan `"A"`/`"B"` + sesuaikan `InpFeedPrefix`)
  di terminal broker **cepat**.
- `LatencyArb.mq5` mode **DRY-RUN** dulu di terminal broker **lambat**.

---

## Troubleshooting meter

| Gejala | Solusi |
|--------|--------|
| Feed A/B "TIDAK ADA" | Prefix salah / writer belum jalan / path Common beda → cek dashboard writer |
| Feed "STALE" | Terminal writer putus koneksi |
| 0 event berjam-jam | Pasar sepi atau `InpEventPoints` kebesaran → turunkan ke 5–7, atau tunggu news |
| "Bareng" (ties) sangat banyak | Kedua feed seimbang → pasangan ini tidak cocok untuk latency arb |
| Timeout banyak | Divergensi tidak kembali (spread/feed beda struktur) → coba simbol/broker lain |
