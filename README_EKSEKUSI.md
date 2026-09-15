# README EKSEKUSI — Latency Arbitrage HFM × Exness (XAUUSD)

> Dokumen ini = rangkuman lengkap + detail dari seluruh setup, tuning, dan
> troubleshooting yang kita lakukan. Kalau suatu saat lupa, baca file ini dulu.

---

## 0. Ringkasan 1 menit

| # | Isi |
|---|-----|
| Apa | Latency arbitrage: baca harga cepat Exness, trading di HFM yang lambat |
| Hasil ukur | **Exness = CEPAT** (lead), **HFM = LAMBAT** (menyusul ~104ms). Terbukti 137 vs 62 event |
| Status sekarang | Semua robot jalan, mode **DRY-RUN** (latihan, tanpa order). Sinyal sudah terdeteksi ✅ |
| Tugas aktif | Biarkan jalan 2–3 hari → hitung sinyal/hari di tab Experts → lapor → putuskan eksekusi demo |

---

## 1. Arsitektur sistem

```
TERMINAL EXNESS (kanan)              TERMINAL HFM (kiri)
Akun 246208209 (REAL!)               Akun 235249688 (DEMO, Hedge)
Simbol: XAUUSDm                      Simbol: XAUUSD
===========                          ==========
Chart XAUUSDm M1:                    Chart XAUUSD M1 (#1):
  FastFeedWriter                       FeedLagMeter (alat ukur)
  (Prefix=FAST)                      Chart XAUUSD M1 (#2):
                                       FastFeedWriter (Prefix=FAST)
           \                         Chart XAUUSD M1 (#3):
            \                          LatencyArb (robot trading, DRY-RUN)
             \                       /
              v                     v
        Common\Files\LatencyArb\  (folder bersama, 1 PC)
          ├── FAST_XAUUSDm.csv   (ditulis Exness, dibaca HFM)
          └── FAST_XAUUSD.csv    (ditulis HFM, dibaca meter)
```

**Peran tiap EA:**

| EA | Tugas | Nempel di |
|----|-------|-----------|
| `FastFeedWriter` | Menulis quote (bid/ask) ke file tiap ~50ms. TIDAK trading | Tiap terminal (masing-masing 1 chart) |
| `FeedLagMeter` | Membaca 2 file, mengukur siapa duluan + berapa ms lag-nya. TIDAK trading | HFM, chart sendiri |
| `LatencyArb` | Membaca file FAST, membandingkan dgn harga lokal, BUY/SELL saat deviasi > trigger | HFM (broker SLOW), chart sendiri |

**Aturan besi #1: 1 chart = 1 EA.** Memasang EA baru di chart yang sudah ada EA
akan **menendang EA lama keluar**. Ini penyebab error paling sering kemarin.

---

## 2. Spesifikasi setup kamu (konkret)

| Item | Terminal HFM (kiri) | Terminal Exness (kanan) |
|------|---------------------|-------------------------|
| Broker/server | HFMarketsGlobal-Demo4 | Exness-MT5Real24 |
| Akun | 235249688 — **DEMO** ✅ | 246208209 — **REAL** ⚠️ |
| Boleh trading? | Ya (demo, aman) | **TIDAK — hanya feed!** Jangan pernah pasang LatencyArb di sini |
| Simbol gold | `XAUUSD` (2 digit, spread ~34) | `XAUUSDm` (2 digit) |
| Prefix writer | `FAST` | `FAST` |
| Symbols writer | `XAUUSD` | `XAUUSDm` |
| File yang ditulis | `FAST_XAUUSD.csv` | `FAST_XAUUSDm.csv` |
| EA terpasang | Writer + Meter + LatencyArb (3 chart) | Writer saja (1 chart) |

> Catatan: kedua writer boleh sama-sama prefix `FAST` HANYA karena nama
> simbolnya beda (`XAUUSD` vs `XAUUSDm`) sehingga nama filenya beda dan tidak
> saling menimpa. Kalau simbolnya sama persis, prefix wajib dibedakan (A/B).

---

## 3. Instalasi dari nol (yang sudah kita lewati)

### Tahap 1 — 3 file EA masuk ke kedua terminal
1. F4 di terminal HFM → copy `FastFeedWriter.mq5`, `FeedLagMeter.mq5`,
   `LatencyArb.mq5` ke folder `MQL5/Experts` → buka satu per satu → F7
   (0 errors) → tutup MetaEditor → Navigator → Refresh.
2. Ulangi langkah 1 di terminal Exness (**tiap terminal punya folder sendiri!**
   F4 di HFM ≠ F4 di Exness).
3. Hasil: 3 nama EA muncul di Navigator kedua terminal.

### Tahap 2 — Writer jalan di keduanya
- HFM: drag Writer ke chart XAUUSD → `FAST` + `XAUUSD` → Allow Algo Trading.
- Exness: drag Writer ke chart XAUUSDm → `FAST` + `XAUUSDm`.
- Sukses: dashboard "Tulis ke-N" bertambah terus + path Common kedua terminal SAMA.

### Tahap 3 — Meter jalan (HFM, chart BARU)
- Buka chart XAUUSD kedua → drag Meter → PrefixA=`FAST`, PrefixB=`FAST`,
  SymbolA=(kosong), SymbolB=`XAUUSDm`.
- Sukses: `[OK]` untuk A dan B → verdict keluar: **B/Exness CEPAT**.

### Tahap 4 — LatencyArb dry-run (HFM, chart KETIGA)
- Buka chart XAUUSD ketiga → drag LatencyArb → `InpFastSymbol`=`XAUUSDm`,
  `InpFeedPrefix`=`FAST`, `InpDryRun`=`true` (jangan diubah!).
- Sukses: dashboard `MODE: DRY-RUN` + angka Dev bergerak + sinyal `[DRY-RUN]` muncul.

### Tahap 5 — Tuning trigger (emas HFM)
- `Deviasi minimum` (trigger): 15 → 45 → **25** (final, lihat bagian 9 no. 10).
- `Spread maks`: 30 → **50** (spread normal HFM ~34, filter 30 memblokir semua).

### Tahap 6 — Update anti-tabrakan (kode v2)
- Writer + LatencyArb ditambah **coba-ulang otomatis 4x** (retry) saat file
  terkunci, sehingga angka `gagal`/`err` berhenti naik.
- Cara update file: buka tab file → Ctrl+A → Delete → paste isi baru full →
  Ctrl+S → F7 (0 errors) → **hapus EA dari chart + drag ulang** (EA yang sedang
  jalan tidak otomatis pakai versi baru!). Meter tidak perlu update.

---

## 4. Konfigurasi final (catat — jangan diubah tanpa alasan)

**FastFeedWriter (kedua terminal):**

| Input | HFM | Exness |
|-------|-----|--------|
| InpSymbols | `XAUUSD` | `XAUUSDm` |
| InpPrefix | `FAST` | `FAST` |
| InpPublishMs | 50 | 50 |

**FeedLagMeter (HFM):**

| Input | Nilai |
|-------|-------|
| Prefix A / B | `FAST` / `FAST` |
| Symbol A / B | (kosong = chart) / `XAUUSDm` |
| EventPoints / CalmPoints | 10 / 3 |

**LatencyArb (HFM — SLOW):**

| Input | Nilai | Artinya |
|-------|-------|---------|
| InpFastSymbol | `XAUUSDm` | Baca harga Exness |
| InpFeedPrefix | `FAST` | Prefix file feed |
| InpDryRun | `true` | **Latihan, TANPA order. Matikan hanya saat siap eksekusi demo!** |
| Deviasi minimum (trigger) | `25` | Sinyal jika deviasi ≥ 25 pts ($0.25) |
| Deviasi maks | `80` | Lewati jika sudah > 80 (ketinggalan) |
| Spread maks | `50` | Blokir jika spread > 50 |
| Volume | `0.01` | Lot per posisi |
| TP virtual / SL virtual | `25` / `50` | Exit otomatis (points) |
| Max hold | `45` detik | Tutup paksa |
| Convergence exit | `true` + buffer `3` | Exit utama: saat HFM sudah menyusul Exness |
| Hard SL riil | `true`, `120` | Pengaman koneksi putus |
| Cooldown / Maks/hari / Stop harian | `10` dtk / `30` / `50` | Proteksi |

---

## 5. Cara kerja sinyal & exit (supaya paham)

**Sinyal (dihitung tiap ~25ms, dalam points HFM):**

- `Dev BUY = fastBid − slowAsk` → jika ≥ 25 → sinyal **BUY**
  (Exness sudah naik, HFM telat naik → beli di HFM, harap menyusul naik)
- `Dev SELL = slowBid − fastAsk` → jika ≥ 25 → sinyal **SELL**
  (Exness sudah turun, HFM telat turun → jual di HFM, harap menyusul turun)

**Dev negatif (mis. −36) itu NORMAL** — artinya tidak ada sinyal ke arah itu,
bukan error dan bukan berarti kebalik.

**Exit posisi (saat nanti eksekusi nyala), yang kena duluan yang menang:**

1. **Catch-up** (utama): HFM sudah menyusul harga Exness → tutup, kunci profit.
2. **TP virtual** +25 pts.
3. **SL virtual** −50 pts.
4. **Timeout** 45 detik.
5. **Hard SL riil** −120 pts (pengaman kalau EA/terminal mati).

**Kenapa trigger 25 masuk akal:** profit kotor ≈ deviasi − buffer ≈ 25 − 3 = 22 pts
($0.22 per 0.01 lot) JIKA HFM menyusul penuh. Biaya: slippage + komisi
(di demo ≈ 0, di real = besar — itulah yang nanti diuji).

---

## 6. Operasional harian (checklist)

**Setiap buka PC / pagi hari:**

- [ ] Kedua terminal MT5 kebuka dan login (HFM demo + Exness real)
- [ ] Tombol Algo Trading **hijau** di keduanya
- [ ] HFM: 3 dashboard hidup (Meter `[OK]` `[OK]`, Writer angka bertambah,
      LatencyArb `[FRESH]`)
- [ ] Exness: 1 dashboard Writer angka bertambah
- [ ] Koneksi pojok kanan bawah ada angka ms (bukan "No connection")

**Selama jalan (boleh minimize, JANGAN tutup):**

- Angka `gagal`/`err` boleh naik SESekali; yang penting status tetap
  `[OK]`/`[FRESH]` dan "terakhir"/"umur" update tiap detik.
- Kedipan `[TIDAK ADA]`/`[STALE]` sedetik lalu balik OK = tabrakan sesaat, normal.
- `STALE` terus > 1 menit = writer pihak itu mati → cek 4 hal bagian 10.

**Tugas ukur (fase sekarang):** tiap 1–2 hari, buka tab **Experts** → hitung baris
`SINYAL ... [DRY-RUN]` → catat sinyal/hari + jam paling ramai sinyal.

---

## 7. Cara baca dashboard

**FeedLagMeter:**

- `A=... [OK] vs B=... [OK]` → kedua feed hidup.
- `A duluan / B duluan` → **angka ini patokan utama** (siapa lebih sering gerak duluan).
- `susul Xms` → rata-rata lag pihak yang menyusul.
- `VERDICT` → vonis otomatis, TAPI butuh rasio 2:1 baru berani vonis, jadi kadang
  tulis SEIMBANG padahal sudah jelas (mis. 104 vs 55). **Percayai angka counts-nya.**
- `Divergensi / maks` → selisih harga live & terbesar tercatat (acuan set trigger).

**LatencyArb:**

- `MODE: DRY-RUN` (aman) vs `LIVE` (order beneran!) — selalu cek ini dulu.
- `Akun: DEMO/REAL` — LatencyArb HANYA boleh LIVE di DEMO.
- `FAST ... [FRESH] umur Xms` → feed Exness hidup. `STALE` = mati > 1.5 dtk.
- `Dev BUY / Dev SELL` → deviasi live. Sinyal jika salah satu ≥ trigger (25).
- `Status` → `Menunggu sinyal...` (normal) / `DRY-RUN: sinyal BUY/SELL` (dapat sinyal,
  tanpa order) / `Blokir: ...` + alasannya (spread/cooldown/jam/harian).

---

## 8. Kriteria naik ke eksekusi DEMO (InpDryRun → false)

JANGAN nyalakan eksekusi sebelum SEMUA ini terpenuhi:

- [ ] Dry-run ≥ 2 minggu, sinyal masuk rutin (ada data sinyal/hari).
- [ ] Verdict meter stabil: B/Exness tetap lead (bukan SEIMBANG terus).
- [ ] Paham bahwa demo fill ≈ sempurna (tanpa slippage) — hasil demo BUKAN janji real.
- [ ] LatencyArb di chart HFM **DEMO** (cek dashboard: `Akun: DEMO`).
- [ ] Volume tetap `0.01`, stop harian aktif (`50`).
- [ ] Siap memantau: bandingkan **harga sinyal vs harga fill** (kalau fill selalu
      jauh / requote → broker slow tidak bisa dieksploitasi → STOP).

**Cara menyalakan:** chart LatencyArb → Properties → `InpDryRun` = `false` → OK.
Untuk mematikan lagi: kembalikan ke `true` (posisi terbuka tetap dikelola EA).

---

## 9. Semua jebakan yang sudah kita temui (lessons learned)

1. **Meter TIDAK ADA** = writer belum jalan di terminal mana pun. Meter hanya
   membaca; file dibuat writer. Solusi: pasang + jalankan writer dulu.
2. **1 chart = 1 EA.** Pasang EA baru di chart ber-EA = menendang yang lama.
   Kejadian 2x (meter menendang writer). Solusi: selalu buka chart baru.
3. **Prefix + nama simbol harus cocok persis.** Meter mencari `A_XAUUSD247.csv`
   tapi folder berisi `FAST_EURUSD.csv` → tidak ketemu. Samakan prefix dan tulis
   nama simbol lengkap termasuk suffix (`XAUUSDm` bukan `XAUUSD`).
4. **Install C vs D TIDAK masalah.** Yang penting folder Common SAMA.
   Verifikasi: bandingkan tulisan "Folder:" di dashboard kedua terminal.
5. **Mode portable = masalah.** Shortcut berekor `/portable` bikin Common beda →
   hapus flag-nya.
6. **Tiap terminal punya folder data sendiri.** F4 + compile + copy file harus
   dilakukan di masing-masing terminal. Copy di HFM tidak muncul di Exness.
7. **Jebakan `.mq5.txt`.** Copy-paste via Notepad sering menyimpan sebagai
   `LatencyArb.mq5.txt` → MT5 tidak kenal. Nyalakan "File name extensions".
8. **Compile error kemarin:** typo `dayOfYear` (harusnya `day_of_year`) +
   baris `InpFeedPrefix` hilang (salah pembuat EA, sudah diperbaiki) +
   lupa Refresh Navigator. Selalu F7 → 0 errors → Refresh.
9. **STALE = writer pihak itu berhenti.** Penyebab: terminal ketutup / EA ketendang /
   Algo merah / putus koneksi. Cek 4 hal itu urut. `err` besar yang historis abaikan.
10. **Perjalanan trigger emas:** 15 → sinyal tenggelam noise + filter spread 30
    memblokir spread normal 34 → 45 → kekecilan... kebesaran, sinyal tidak pernah
    masuk → **25** = final buat fase belajar (di atas noise/offset, di bawah spike).
11. **Dev negatif bukan error.** Artinya tidak ada sinyal ke arah itu. Bukan kebalik.
12. **FAST/SLOW tidak kebalik:** FAST = Exness (sumber harga, dibaca),
    SLOW = HFM (tempat order). Buktinya counts meter (137 vs 62).
13. **Pagi Asia (WIB) memang sepi.** Sinyal ramai saat London–New York
    (14:00–23:00 WIB). Jangan nilai sistem dari 1 jam pagi.
14. **Angka `gagal`/`err` = tabrakan file, bukan order gagal.** Selama status
    FRESH/OK = sehat. Update retry v2 membuat ini nyaris nol.
15. **Update file EA = paste + F7 + hapus dari chart + drag ulang.**
    EA yang sedang jalan tidak otomatis memakai kode baru hasil compile.
16. **Akun Exness = REAL.** Tidak apa-apa untuk writer (read-only), tapi JANGAN
    pernah pasang LatencyArb LIVE di sana. Trading hanya di HFM demo.

---

## 10. Troubleshooting lengkap

| Gejala | Penyebab paling mungkin | Solusi |
|--------|-------------------------|--------|
| EA tidak muncul di Navigator | File belum di-copy / salah folder terminal / `.txt` / belum compile / belum Refresh | Cek 5 itu urut; F7 → 0 errors → Refresh |
| Compile error merah | Kode belum update / salah paste | Copy ulang FULL file terbaru → F7 |
| Meter `[TIDAK ADA]` | Writer belum jalan / prefix salah / nama simbol salah | Samakan prefix + simbol; cek file ada di folder Common |
| Meter/reader `[STALE]` | Writer pihak itu mati | Cek terminal ybs: kebuka? EA nempel? Algo hijau? koneksi? |
| Kedip TIDAK ADA/STALE sedetik | Tabrakan baca-tulis | Normal jika balik OK sendiri (retry v2 meminimalkan) |
| `gagal`/`err` naik cepat + STALE | Writer mati / file dikunci program lain (mis. Excel kebuka) | Hidupkan writer; tutup file csv di program lain |
| Tidak pernah sinyal (berhari-hari) | Trigger kebesaran / pasar sepi / feed salah | Cek Dev bergerak? Cek divergensi maks meter; turunkan trigger bertahap; ukur saat jam ramai |
| Sinyal tiap menit (banjir) | Trigger kekecilan (noise) | Naikkan trigger bertahap |
| `Blokir: spread terlalu besar` terus | Filter < spread normal broker | Naikkan `Spread maks` di atas spread normal (kita: 50) |
| Order gagal (saat LIVE demo) | Dana / mode simbol / koneksi | Baca tab Journal persisnya; pastikan akun allow trade + hedging |
| Verdict SEIMBANG terus | Pasangan feed seimbang / threshold meter kebesaran | Kecilkan EventPoints meter / coba simbol lain / terima: pasangan tidak cocok |
| EA tidak jalan padahal nempel | Algo merah / Allow Algo tidak centang | Hijaukan tombol + centang di Properties → Common |
| Chart kosong setelah drag EA | EA menendang EA lama (aturan 1 chart 1 EA) | Buka chart baru untuk tiap EA; pasang ulang yang ketendang |

---

## 11. FAQ singkat

**Q: Bedanya writer, meter, LatencyArb?**
A: Writer = penulis harga. Meter = alat ukur cepat-lambat. LatencyArb = robot
trading. Hanya LatencyArb yang bisa order, dan itu pun hanya jika DryRun dimatikan.

**Q: Kenapa trigger 25, bukan 15 atau 45?**
A: 15 tenggelam noise/offset harga antar broker; 45 hampir tidak pernah kejadian;
25 di tengah — cukup sering terlihat, masih masuk akal ekonominya untuk fase belajar.

**Q: Kenapa eksekusi hanya di HFM demo?**
A: Karena HFM yang lambat (peluangnya di sana) + akunnya demo (aman).
Exness real hanya jadi "mata" (feed), tidak pernah diorder.

**Q: Kapan boleh akun real?**
A: Setelah (1) demo eksekusi profit konsisten berminggu-minggu, (2) paham slippage
real, (3) baca TOS broker soal arbitrase (banyak yang melarang + bisa batalkan
profit), (4) pakai VPS dekat server broker. Realistisch: dari PC rumah Indonesia
sangat sulit profit — jujur saja.

**Q: File-file panduannya apa saja?**
A: `README_EKSEKUSI.md` (file ini — operasional), `PANDUAN_LATENCY.md` (konsep +
instalasi), `PANDUAN_UKUR_FEED.md` (cara ukur cepat-lambat).

---

## 12. Peringatan (baca tiap mau naik level)

1. Latency arbitrage **dilarang banyak broker** — profit bisa dibatalkan, akun dibekukan.
2. Demo fill ≈ sempurna; **real ada slippage/requote** — hasil demo bukan janji real.
3. Jangan trading real dengan uang yang tidak siap hilang. Jangan matikan DryRun
   di akun real. Jangan pasang LatencyArb LIVE di terminal Exness (real).
4. EA ini alat edukasi/eksperimen, bukan mesin uang dan bukan jaminan profit.

---

## 13. Riwayat tuning (changelog)

| Tanggal | Perubahan | Alasan |
|---------|-----------|--------|
| 15 Sep 2026 | Setup awal: writer FAST + meter + LatencyArb dry-run trigger 15 | Instalasi |
| 15 Sep 2026 | Trigger 15 → 45, spread filter 30 → 50 | Hindari noise (ternyata over) |
| 15 Sep 2026 | Fix kode: `dayOfYear`, `InpFeedPrefix` hilang | Compile error |
| 15 Sep 2026 | Verdict: Exness FAST (~104–183ms lead, 137 vs 62) | Hasil ukur |
| 15 Sep 2026 | Trigger 45 → **25** | 45 tidak pernah sinyal; 25 seimbang |
| 15 Sep 2026 | Retry 4x baca/tulis (writer + LatencyArb) | Hentikan `gagal`/`err` tabrakan file |

---

*Dokumen ini hidup — update lagi saat ada tuning baru atau naik ke eksekusi demo.* 🚀
