//+------------------------------------------------------------------+
//|                                                 FeedLagMeter.mq5 |
//|   Alat ukur: broker mana yang CEPAT (lead) vs LAMBAT (lag)?      |
//|                                                                  |
//|   CARA PAKAI:                                                    |
//|   1. Jalankan FastFeedWriter di terminal broker A dengan prefix  |
//|      "A", dan di terminal broker B dengan prefix "B".            |
//|   2. Pasang EA ini di SALAH SATU terminal (bebas yang mana).     |
//|   3. Biarkan jalan melewati jam sibuk / news, lalu baca verdict  |
//|      di dashboard: siapa yang bergerak duluan & berapa ms lag    |
//|      pihak yang menyusul.                                        |
//|                                                                  |
//|  Threshold dihitung dalam points simbol chart tempat EA dipasang.|
//+------------------------------------------------------------------+
#property copyright "Dibuat dengan bantuan Arena.ai Agent - untuk edukasi"
#property version   "1.00"
#property description "Ukur lead/lag 2 feed broker untuk latency arbitrage."

input group "Feed A vs B"
input string InpPrefixA = "A";   // Prefix writer broker A
input string InpPrefixB = "B";   // Prefix writer broker B
input string InpSymbolA = "";    // Simbol di A (kosong = chart ini)
input string InpSymbolB = "";    // Simbol di B (kosong = chart ini)

input group "Deteksi Event"
input double InpEventPoints   = 10.0; // Gerakan = event (points chart ini)
input double InpCalmPoints    = 3.0;  // Di bawah ini = tenang (reset acuan)
input int    InpEventTimeoutMs = 3000;// Timeout tunggu susulan (ms)
input int    InpRefAnchorSec  = 10;   // Reset acuan tiap N detik (anti-drift)

input group "Umum"
input int    InpPollMs        = 25;   // Interval baca (milidetik)
input int    InpMaxAgeMs      = 5000; // File lebih tua = tidak valid
input bool   InpShowDashboard = true; // Tampilkan dashboard

//+------------------------------------------------------------------+
//| Struktur & variabel global                                       |
//+------------------------------------------------------------------+
struct FeedState
  {
   double            bid;
   double            ask;
   double            mid;
   uint              tick;
   uint              age;
  };

#define RATE_BUF 1200

string g_symA = "";
string g_symB = "";
//--- status feed terakhir (2=ok, 1=stale, 0=tidak ada)
int    g_stA = 0, g_stB = 0;
double g_midA = 0.0, g_midB = 0.0;
uint   g_ageA = 0, g_ageB = 0;
double g_div = 0.0;               // divergensi live (points)
//--- tick rate (buffer waktu quote berubah)
uint   g_arrA[RATE_BUF];
uint   g_arrB[RATE_BUF];
int    g_iA = 0, g_iB = 0;
long   g_cA = 0, g_cB = 0;
double g_lastBidA = -1.0, g_lastAskA = -1.0;
double g_lastBidB = -1.0, g_lastAskB = -1.0;
//--- mesin event lead/lag
int    g_pend = 0;                // 0=tidak ada, 1=A duluan, 2=B duluan
uint   g_t0 = 0;
int    g_dir = 0;
double g_mag = 0.0;
double g_refA = 0.0, g_refB = 0.0;
uint   g_refTime = 0;
bool   g_haveRef = false;
//--- statistik
long   g_nAB = 0, g_nBA = 0;      // A duluan->B susul | B duluan->A susul
long   g_sumAB = 0, g_sumBA = 0;  // jumlah lag (ms)
long   g_ties = 0, g_timeouts = 0;
double g_maxDiv = 0.0;
datetime g_maxDivTime = 0;
string g_status = "";

//+------------------------------------------------------------------+
//| Baca 1 file feed. Kembalian: 2=ok, 1=stale, 0=tidak ada/rusak.   |
//+------------------------------------------------------------------+
int ReadFeed(const string prefix, const string sym, FeedState &f)
  {
   ZeroMemory(f);
   string path = "LatencyArb\\" + prefix + "_" + sym + ".csv";
   if(!FileIsExist(path, FILE_COMMON))
      return 0;
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return 0;
   string line = FileReadString(h);
   FileClose(h);
   string p[];
   if(StringSplit(line, ',', p) < 3)
      return 0;
   f.bid = StringToDouble(p[0]);
   f.ask = StringToDouble(p[1]);
   f.tick = (uint)StringToInteger(p[2]);
   if(f.bid <= 0 || f.ask <= 0)
      return 0;
   f.mid = (f.bid + f.ask) / 2.0;
   f.age = GetTickCount() - f.tick;   // aritmetika uint: aman dari wrap
   if(f.age > (uint)InpMaxAgeMs)
      return 1;
   return 2;
  }

//+------------------------------------------------------------------+
//| Tick rate: catat & hitung quote berubah per menit.               |
//+------------------------------------------------------------------+
void PushTick(uint &arr[], int &idx, long &cnt, const uint nowMs)
  {
   arr[idx] = nowMs;
   idx++;
   if(idx >= RATE_BUF)
      idx = 0;
   cnt++;
  }

int RatePerMin(const uint &arr[], const long cnt, const uint nowMs)
  {
   long n = (cnt < RATE_BUF ? cnt : RATE_BUF);
   int c = 0;
   for(long i = 0; i < n; i++)
      if(nowMs - arr[i] < 60000)
         c++;
   return c;
  }

//+------------------------------------------------------------------+
//| Verdict: siapa lead?                                              |
//+------------------------------------------------------------------+
string Verdict()
  {
   long total = g_nAB + g_nBA;
   if(total < 5)
      return "Belum cukup data (butuh >=5 event susulan; biarkan jalan saat news/jam sibuk).";
   if(g_nAB >= g_nBA * 2 && g_nAB >= 3)
     {
      double avg = (double)g_sumAB / (double)g_nAB;
      return "A = CEPAT (lead). B menyusul rata-rata " + DoubleToString(avg, 0) + " ms (" +
             IntegerToString(g_nAB) + " event). Rekomendasi arb: FAST=A, SLOW=B.";
     }
   if(g_nBA >= g_nAB * 2 && g_nBA >= 3)
     {
      double avg = (double)g_sumBA / (double)g_nBA;
      return "B = CEPAT (lead). A menyusul rata-rata " + DoubleToString(avg, 0) + " ms (" +
             IntegerToString(g_nBA) + " event). Rekomendasi arb: FAST=B, SLOW=A.";
     }
   return "SEIMBANG / belum jelas (" + IntegerToString(g_nAB) + " vs " + IntegerToString(g_nBA) +
          "). Tambah waktu ukur / kecilkan EventPoints / coba simbol lain.";
  }

string FeedStatusWord(const int st)
  {
   if(st == 2)
      return "OK";
   if(st == 1)
      return "STALE";
   return "TIDAK ADA";
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_symA = (InpSymbolA == "" ? _Symbol : InpSymbolA);
   g_symB = (InpSymbolB == "" ? _Symbol : InpSymbolB);
   FolderCreate("LatencyArb", FILE_COMMON);
   int ms = (InpPollMs < 5 ? 5 : InpPollMs);
   if(!EventSetMillisecondTimer(ms))
     {
      Print("ERROR: gagal menyalakan timer.");
      return(INIT_FAILED);
     }
   Print("FeedLagMeter jalan. A=", InpPrefixA, "_", g_symA, " B=", InpPrefixB, "_", g_symB);
   Print("Pastikan writer Kedua broker jalan dengan prefix tsb. Biarkan ukur saat jam sibuk/news.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
  }

void OnTick()  { Process(); }
void OnTimer() { Process(); }

//+------------------------------------------------------------------+
//| Loop utama pengukuran                                            |
//+------------------------------------------------------------------+
void Process()
  {
   FeedState A, B;
   g_stA = ReadFeed(InpPrefixA, g_symA, A);
   g_stB = ReadFeed(InpPrefixB, g_symB, B);

   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(pt <= 0)
      pt = _Point;
   uint nowMs = GetTickCount();

   if(g_stA == 2 && g_stB == 2)
     {
      g_midA = A.mid;
      g_midB = B.mid;
      g_ageA = A.age;
      g_ageB = B.age;
      g_div = (A.mid - B.mid) / pt;

      //--- tick rate: hitung saat quote BERUBAH
      if(A.bid != g_lastBidA || A.ask != g_lastAskA)
        {
         PushTick(g_arrA, g_iA, g_cA, nowMs);
         g_lastBidA = A.bid;
         g_lastAskA = A.ask;
        }
      if(B.bid != g_lastBidB || B.ask != g_lastAskB)
        {
         PushTick(g_arrB, g_iB, g_cB, nowMs);
         g_lastBidB = B.bid;
         g_lastAskB = B.ask;
        }

      if(MathAbs(g_div) > MathAbs(g_maxDiv))
        {
         g_maxDiv = g_div;
         g_maxDivTime = TimeCurrent();
        }

      //--- jangkar acuan anti-drift
      if(!g_haveRef || nowMs - g_refTime > (uint)(InpRefAnchorSec * 1000))
        {
         g_refA = A.mid;
         g_refB = B.mid;
         g_refTime = nowMs;
         g_haveRef = true;
        }

      if(MathAbs(g_div) < InpCalmPoints)
        {
         //--- tenang: reset acuan & event
         g_refA = A.mid;
         g_refB = B.mid;
         g_refTime = nowMs;
         g_pend = 0;
         g_status = "Tenang (spread/kuotasi sejajar). Menunggu gerakan...";
        }
      else if(g_pend == 0)
        {
         //--- divergen: siapa yang bergerak duluan?
         double dA = (A.mid - g_refA) / pt;
         double dB = (B.mid - g_refB) / pt;
         double adA = MathAbs(dA), adB = MathAbs(dB);
         if(adA >= InpEventPoints || adB >= InpEventPoints)
           {
            if(adA >= InpEventPoints && adA >= adB * 1.5)
              {
               g_pend = 1;
               g_t0 = nowMs;
               g_dir = (dA > 0 ? 1 : -1);
               g_mag = adA;
              }
            else if(adB >= InpEventPoints && adB >= adA * 1.5)
              {
               g_pend = 2;
               g_t0 = nowMs;
               g_dir = (dB > 0 ? 1 : -1);
               g_mag = adB;
              }
            else
              {
               g_ties++;   // bergerak hampir bareng
               g_refA = A.mid;
               g_refB = B.mid;
               g_refTime = nowMs;
              }
           }
         g_status = "Divergen " + DoubleToString(g_div, 1) + " pts. Menganalisis...";
        }
      else
        {
         //--- event berjalan: tunggu pihak kedua menyusul
         double dA = (A.mid - g_refA) / pt;
         double dB = (B.mid - g_refB) / pt;
         bool followed = false;
         if(g_pend == 1)
           {
            if((g_dir > 0 && dB >= g_mag * 0.5) || (g_dir < 0 && dB <= -g_mag * 0.5))
              {
               uint lag = nowMs - g_t0;
               g_nAB++;
               g_sumAB += (long)lag;
               followed = true;
               Print("Event: A duluan, B susul ", IntegerToString((long)lag), "ms");
              }
            g_status = "Event: A duluan, tunggu B (" + IntegerToString((long)(nowMs - g_t0)) + "ms)...";
           }
         else
           {
            if((g_dir > 0 && dA >= g_mag * 0.5) || (g_dir < 0 && dA <= -g_mag * 0.5))
              {
               uint lag = nowMs - g_t0;
               g_nBA++;
               g_sumBA += (long)lag;
               followed = true;
               Print("Event: B duluan, A susul ", IntegerToString((long)lag), "ms");
              }
            g_status = "Event: B duluan, tunggu A (" + IntegerToString((long)(nowMs - g_t0)) + "ms)...";
           }
         if(followed)
           {
            g_pend = 0;
            g_refA = A.mid;
            g_refB = B.mid;
            g_refTime = nowMs;
           }
         else if(nowMs - g_t0 > (uint)InpEventTimeoutMs)
           {
            g_timeouts++;
            g_pend = 0;
            g_refA = A.mid;
            g_refB = B.mid;
            g_refTime = nowMs;
            g_status = "Timeout (tidak ada susulan). Reset acuan...";
           }
        }
     }
   else
     {
      g_pend = 0;
      if(g_stA != 2 && g_stB != 2)
         g_status = "Menunggu file A & B (writer belum jalan / prefix salah?)";
      else if(g_stA != 2)
         g_status = "Menunggu file A (" + FeedStatusWord(g_stA) + ")";
      else
         g_status = "Menunggu file B (" + FeedStatusWord(g_stB) + ")";
     }

   if(InpShowDashboard)
      DrawDash(pt);
   else
      Comment("");
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawDash(const double pt)
  {
   uint nowMs = GetTickCount();
   int rateA = RatePerMin(g_arrA, g_cA, nowMs);
   int rateB = RatePerMin(g_arrB, g_cB, nowMs);
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   string s = "";
   s += "===== FEED LAG METER =====\n";
   s += "A=" + InpPrefixA + "_" + g_symA + " [" + FeedStatusWord(g_stA) + "]" +
        "  vs  B=" + InpPrefixB + "_" + g_symB + " [" + FeedStatusWord(g_stB) + "]\n";
   if(g_stA == 2 && g_stB == 2)
     {
      s += "Mid A: " + DoubleToString(g_midA, dg) + " (umur " + IntegerToString((long)g_ageA) +
           "ms, " + IntegerToString(rateA) + " tick/mnt)\n";
      s += "Mid B: " + DoubleToString(g_midB, dg) + " (umur " + IntegerToString((long)g_ageB) +
           "ms, " + IntegerToString(rateB) + " tick/mnt)\n";
      s += "Divergensi: " + DoubleToString(g_div, 1) + " pts | maks: " +
           DoubleToString(g_maxDiv, 1) + " pts @ " +
           (g_maxDivTime > 0 ? TimeToString(g_maxDivTime, TIME_SECONDS) : "-") + "\n";
     }
   else
      s += "(menunggu kedua feed valid...)\n";
   string avgAB = (g_nAB > 0 ? DoubleToString((double)g_sumAB / (double)g_nAB, 0) + "ms" : "-");
   string avgBA = (g_nBA > 0 ? DoubleToString((double)g_sumBA / (double)g_nBA, 0) + "ms" : "-");
   s += "A duluan: " + IntegerToString(g_nAB) + " (susul " + avgAB + ")" +
        " | B duluan: " + IntegerToString(g_nBA) + " (susul " + avgBA + ")\n";
   s += "Bareng: " + IntegerToString(g_ties) + " | Timeout: " + IntegerToString(g_timeouts) + "\n";
   s += "VERDICT: " + Verdict() + "\n";
   s += "Status: " + g_status;
   Comment(s);
  }
//+------------------------------------------------------------------+
