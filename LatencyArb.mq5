//+------------------------------------------------------------------+
//|                                                    LatencyArb.mq5 |
//|   Latency Arbitrage EA - sisi SLOW (terminal broker lambat)      |
//|                                                                  |
//|   CARA KERJA:                                                    |
//|   EA ini dipasang di terminal MT5 yang login ke broker LAMBAT.   |
//|   Ia membaca quote broker CEPAT dari file Common Files yang      |
//|   ditulis FastFeedWriter.mq5, lalu membandingkan dengan quote    |
//|   broker lambat. Jika deviasi > ambang: BUY/SELL di broker       |
//|   lambat, berharap harganya menyusul.                            |
//|                                                                  |
//|   SINYAL (dalam points broker SLOW):                             |
//|     fastBid > slowAsk + trigger  ->  BUY                         |
//|     fastAsk < slowBid - trigger  ->  SELL                        |
//|                                                                  |
//|   PERINGATAN KERAS:                                              |
//|   Latency arbitrage DILARANG banyak broker (profit bisa          |
//|   dibatalkan / akun dibekukan). Mode bawaan = DRY-RUN (tanpa     |
//|   order). Baca TOS broker sebelum akun real.                     |
//+------------------------------------------------------------------+
#property copyright "Dibuat dengan bantuan Arena.ai Agent - untuk edukasi"
#property version   "1.00"
#property description "Latency Arbitrage (2 broker): baca fast feed dari file, eksekusi di broker slow."

#include <Trade\Trade.mqh>

//--- input: feed cepat
input group "Feed Cepat (dari terminal FAST)"
input string InpFastSymbol  = "";     // Simbol di broker FAST (kosong = samakan chart ini)
input string InpFeedPrefix  = "FAST"; // Prefix file feed (samakan dgn InpPrefix writer)
input int    InpPollMs      = 25;    // Interval baca file (milidetik)
input int    InpMaxFeedAgeMs = 1500; // Umur maks feed agar dianggap fresh (ms)

//--- input: sinyal
input group "Sinyal (dalam points broker SLOW)"
input double InpTriggerPoints  = 15.0; // Deviasi minimum untuk sinyal
input double InpMaxDevPoints   = 80.0; // Deviasi maks (0 = tanpa batas atas)
input int    InpMaxSpreadPoints = 30;  // Spread maks (points, 0 = mati)

//--- input: eksekusi & exit
input group "Eksekusi & Exit"
input bool   InpDryRun           = true;   // Dry-run (true = sinyal saja, TANPA order)
input double InpVolume           = 0.01;   // Volume per posisi
input int    InpSlippagePoints   = 30;     // Slippage maks (points)
input long   InpMagic            = 88001;  // Magic number (unik per chart!)
input double InpTakeProfitPoints = 25.0;   // TP virtual (points)
input double InpStopLossPoints   = 50.0;   // SL virtual (points)
input int    InpMaxHoldSec       = 45;     // Tahan maks posisi (detik, 0 = mati)
input bool   InpUseConvergenceExit = true; // Exit saat slow sudah menyusul fast
input double InpExitBufferPoints  = 3.0;   // Buffer exit catch-up (points)
input bool   InpUseHardSL        = true;   // Pasang SL riil sebagai pengaman
input double InpHardSLPoints     = 120.0;  // Jarak SL riil (points)

//--- input: proteksi
input group "Proteksi"
input int    InpCooldownSec     = 10;   // Jeda antar transaksi (detik)
input int    InpMaxTradesPerDay = 30;   // Maks transaksi per hari (0 = tanpa batas)
input double InpMaxDailyLoss    = 50.0; // Stop harian: rugi maks (mata uang akun, 0 = mati)
input bool   InpUseTimeFilter   = false;// Aktifkan filter jam
input int    InpStartHour       = 7;    // Jam mulai (waktu server broker SLOW)
input int    InpEndHour         = 22;   // Jam selesai (waktu server broker SLOW)

//--- input: tampilan
input group "Tampilan"
input bool InpShowDashboard = true;     // Tampilkan dashboard

//+------------------------------------------------------------------+
//| Struktur & variabel global                                       |
//+------------------------------------------------------------------+
struct FastQuote
  {
   double            bid;
   double            ask;
   uint              tick;   // GetTickCount() penulis (ms, sebanding 1 PC)
   string            srv;    // waktu server FAST (diagnostik)
  };

CTrade   trade;
string   g_fastSym = "";
FastQuote g_fast;
bool     g_haveFast = false;  // file ada & format benar
bool     g_fresh = false;     // umur feed <= batas
uint     g_fastAgeMs = 0;
long     g_readErr = 0;
datetime g_lastErrPrint = 0;
int      g_sig = 0;           // -1 = SELL, 0 = tidak ada, +1 = BUY
double   g_devBuy = 0.0;
double   g_devSell = 0.0;
datetime g_lastAction = 0;
datetime g_lastSignalTime = 0;
//--- statistik harian
int      g_dayOfYear = -1;
double   g_dayStartBalance = 0.0;
bool     g_dailyBlocked = false;
int      g_trades = 0, g_wins = 0, g_losses = 0;
double   g_dayProfit = 0.0;

//+------------------------------------------------------------------+
//| Helper: Print yang dibatasi (maks 1x per 60 detik)               |
//+------------------------------------------------------------------+
void ThrottledPrint(const string msg)
  {
   if(TimeCurrent() - g_lastErrPrint >= 60)
     {
      Print(msg);
      g_lastErrPrint = TimeCurrent();
     }
  }

string SignedPts(const double v)
  {
   return ((v >= 0 ? "+" : "") + DoubleToString(v, 1));
  }

//+------------------------------------------------------------------+
//| Baca file quote FAST. Kembalian true jika file terbaca & valid.  |
//+------------------------------------------------------------------+
bool ReadFast()
  {
   string path = "LatencyArb\\" + InpFeedPrefix + "_" + g_fastSym + ".csv";
   if(!FileIsExist(path, FILE_COMMON))
     {
      g_haveFast = false;
      g_fresh = false;
      return false;
     }
   for(int attempt = 0; attempt < 4; attempt++)
     {
      int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_COMMON | FILE_ANSI);
      if(h == INVALID_HANDLE)
        {
         Sleep(2);
         continue;
        }
      string line = FileReadString(h);
      FileClose(h);
      string p[];
      if(StringSplit(line, ',', p) < 3)
        {
         Sleep(2);
         continue;   // file tertangkap setengah ditulis, coba lagi
        }
      g_fast.bid = StringToDouble(p[0]);
      g_fast.ask = StringToDouble(p[1]);
      g_fast.tick = (uint)StringToInteger(p[2]);
      g_fast.srv = (ArraySize(p) > 3 ? p[3] : "");
      if(g_fast.bid <= 0 || g_fast.ask <= 0)
        {
         Sleep(2);
         continue;
        }
      g_haveFast = true;
      g_fastAgeMs = GetTickCount() - g_fast.tick;   // aritmetika uint: aman dari wrap
      g_fresh = (g_fastAgeMs <= (uint)InpMaxFeedAgeMs);
      return true;
     }
   g_readErr++;
   ThrottledPrint("Gagal baca " + path + " setelah 4x coba.");
   g_fresh = false;
   return g_haveFast;
  }

//+------------------------------------------------------------------+
//| Cari posisi milik EA ini di chart ini (simbol + magic).          |
//+------------------------------------------------------------------+
bool FindOurPosition(ulong &ticket, int &ptype, double &open, datetime &otime)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0)
         continue;
      if(!PositionSelectByTicket(t))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      ticket = t;
      ptype = (int)PositionGetInteger(POSITION_TYPE);
      open = PositionGetDouble(POSITION_PRICE_OPEN);
      otime = (datetime)PositionGetInteger(POSITION_TIME);
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Ambil profit deal penutup terakhir milik EA ini (riwayat).       |
//+------------------------------------------------------------------+
bool GetLastCloseProfit(double &profit)
  {
   profit = 0.0;
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 2 * 86400, now + 60))
      return false;
   int total = HistoryDealsTotal();
   datetime bestTime = 0;
   bool found = false;
   for(int i = 0; i < total; i++)
     {
      ulong dt = HistoryDealGetTicket(i);
      if(dt == 0)
         continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol)
         continue;
      if(HistoryDealGetInteger(dt, DEAL_MAGIC) != InpMagic)
         continue;
      long entry = HistoryDealGetInteger(dt, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;
      datetime dtm = (datetime)HistoryDealGetInteger(dt, DEAL_TIME);
      if(dtm >= bestTime)
        {
         bestTime = dtm;
         profit = HistoryDealGetDouble(dt, DEAL_PROFIT) +
                  HistoryDealGetDouble(dt, DEAL_SWAP) +
                  HistoryDealGetDouble(dt, DEAL_COMMISSION);
         found = true;
        }
     }
   return found;
  }

//+------------------------------------------------------------------+
//| Tutup posisi + catat statistik.                                  |
//+------------------------------------------------------------------+
void CloseOur(const ulong ticket, const string reason)
  {
   trade.PositionClose(ticket);
   if(trade.ResultRetcode() != TRADE_RETCODE_DONE)
     {
      Print("Gagal close: ", trade.ResultRetcodeDescription());
      return;
     }
   double p = 0.0;
   if(GetLastCloseProfit(p))
     {
      g_dayProfit += p;
      if(p >= 0)
         g_wins++;
      else
         g_losses++;
     }
   g_lastAction = TimeCurrent();
   Print("CLOSE (", reason, "): profit=", DoubleToString(p, 2), " ", AccountInfoString(ACCOUNT_CURRENCY));
  }

//+------------------------------------------------------------------+
//| Hitung harga SL riil (disesuaikan stops-level broker).           |
//+------------------------------------------------------------------+
double AdjustSL(const bool isBuy, const double refPrice, double dist)
  {
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist = (lvl + 2) * pt;
   if(dist < minDist)
      dist = minDist;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return NormalizeDouble(isBuy ? refPrice - dist : refPrice + dist, dg);
  }

//+------------------------------------------------------------------+
//| Buka posisi market.                                              |
//+------------------------------------------------------------------+
void OpenTrade(const int side)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl = 0.0;
   if(InpUseHardSL)
     {
      double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      sl = AdjustSL(side > 0, (side > 0 ? ask : bid), InpHardSLPoints * pt);
     }
   trade.SetTypeFillingBySymbol(_Symbol);
   bool ok = (side > 0 ? trade.Buy(InpVolume, _Symbol, 0.0, sl, 0.0, "LatArb")
                        : trade.Sell(InpVolume, _Symbol, 0.0, sl, 0.0, "LatArb"));
   if(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      g_trades++;
      g_lastAction = TimeCurrent();
      Print("OPEN ", (side > 0 ? "BUY" : "SELL"), " ", _Symbol, " ", DoubleToString(InpVolume, 2), " lot");
     }
   else
     {
      Print("OPEN gagal: ", trade.ResultRetcodeDescription());
      g_lastAction = TimeCurrent();   // cegah spam order gagal
     }
  }

//+------------------------------------------------------------------+
//| Filter jam trading (waktu server broker SLOW).                   |
//+------------------------------------------------------------------+
bool TimeAllowed()
  {
   if(!InpUseTimeFilter)
      return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int h = dt.hour;
   if(InpStartHour <= InpEndHour)
      return (h >= InpStartHour && h < InpEndHour);
   return (h >= InpStartHour || h < InpEndHour);
  }

//+------------------------------------------------------------------+
//| Proteksi harian: reset tiap hari, stop jika batas tercapai.      |
//+------------------------------------------------------------------+
void UpdateDaily()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_year != g_dayOfYear)
     {
      g_dayOfYear = dt.day_of_year;
      g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyBlocked = false;
      g_trades = 0;
      g_wins = 0;
      g_losses = 0;
      g_dayProfit = 0.0;
     }
   if(InpMaxDailyLoss > 0 && !g_dailyBlocked)
     {
      double dd = AccountInfoDouble(ACCOUNT_EQUITY) - g_dayStartBalance;
      if(dd <= -InpMaxDailyLoss)
        {
         g_dailyBlocked = true;
         ulong ticket = 0;
         int ptype = -1;
         double open = 0.0;
         datetime otime = 0;
         if(FindOurPosition(ticket, ptype, open, otime))
            CloseOur(ticket, "stop-harian");
         Print("STOP HARIAN tercapai. Entry baru dihentikan sampai besok.");
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpSlippagePoints);

   g_fastSym = (InpFastSymbol == "" ? _Symbol : InpFastSymbol);
   FolderCreate("LatencyArb", FILE_COMMON);

//--- validasi volume
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(InpVolume < vmin || InpVolume > vmax)
     {
      Print("ERROR: InpVolume harus antara ", DoubleToString(vmin, 2), " - ", DoubleToString(vmax, 2), ".");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpTriggerPoints <= 0 || InpTakeProfitPoints <= 0 || InpStopLossPoints <= 0)
     {
      Print("ERROR: Trigger/TP/SL harus lebih besar dari 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- peringatan mode akun & simbol
   long mm = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      Print("PERINGATAN: akun NETTING terdeteksi. Untuk latency arb disarankan akun HEDGING, ",
            "dan jangan ada EA/manual lain di simbol ini (posisi bisa tercampur).");
   long stm = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(stm != SYMBOL_TRADE_MODE_FULL)
      Print("PERINGATAN: simbol ", _Symbol, " tidak full-trading. EA mungkin gagal order.");
   if((bool)MQLInfoInteger(MQL_TESTER))
      Print("PERINGATAN: EA ini tidak bisa dibacktest normal (butuh live feed 2 broker via file).");

   int ms = (InpPollMs < 5 ? 5 : InpPollMs);
   if(!EventSetMillisecondTimer(ms))
     {
      Print("ERROR: gagal menyalakan timer.");
      return(INIT_FAILED);
     }

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   g_dayOfYear = dt.day_of_year;
   g_dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   Print("LatencyArb jalan. SLOW=", _Symbol, " FAST=", g_fastSym,
         " MODE=", (InpDryRun ? "DRY-RUN (tanpa order)" : "LIVE (order aktif!)"));
   Print("Membaca: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\LatencyArb\\", InpFeedPrefix, "_", g_fastSym, ".csv");
   if(!InpDryRun)
      Print("PERINGATAN KERAS: mode LIVE aktif. Pastikan ini akun DEMO dan kamu paham risiko banned broker.");
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
//| Loop utama: baca feed -> kelola posisi -> evaluasi sinyal.       |
//+------------------------------------------------------------------+
void Process()
  {
   UpdateDaily();
   ReadFast();

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   bool okSlow = (bid > 0 && ask > 0 && pt > 0);

   if(okSlow && g_haveFast)
     {
      g_devBuy = (g_fast.bid - ask) / pt;
      g_devSell = (bid - g_fast.ask) / pt;
     }
   else
     {
      g_devBuy = 0.0;
      g_devSell = 0.0;
     }

   datetime now = TimeCurrent();
   string status = "";

   ulong ticket = 0;
   int ptype = -1;
   double open = 0.0;
   datetime otime = 0;
   bool havePos = FindOurPosition(ticket, ptype, open, otime);
   bool justClosed = false;

   //--- 1. kelola posisi terbuka (maks 1 posisi)
   if(havePos)
     {
      bool isBuy = (ptype == POSITION_TYPE_BUY);
      double cur = (isBuy ? bid : ask);
      double ppts = (isBuy ? (cur - open) : (open - cur)) / pt;
      long held = (long)(now - otime);
      string exitReason = "";
      if(ppts >= InpTakeProfitPoints)
         exitReason = "tp";
      else if(ppts <= -InpStopLossPoints)
         exitReason = "sl";
      else if(InpMaxHoldSec > 0 && held >= InpMaxHoldSec)
         exitReason = "timeout";
      else if(InpUseConvergenceExit && g_fresh)
        {
         if(isBuy && bid >= g_fast.bid - InpExitBufferPoints * pt)
            exitReason = "catchup";
         if(!isBuy && ask <= g_fast.ask + InpExitBufferPoints * pt)
            exitReason = "catchup";
        }
      if(exitReason != "")
        {
         CloseOur(ticket, exitReason);
         havePos = false;
         justClosed = true;
         status = "Exit: " + exitReason;
        }
      else
         status = StringFormat("Hold %s %s pts (%s dtk)", (isBuy ? "BUY" : "SELL"),
                               SignedPts(ppts), IntegerToString(held));
      g_sig = 0;
     }

   //--- 2. evaluasi sinyal jika sedang flat
   if(!havePos && !justClosed)
     {
      int sig = 0;
      if(g_fresh && okSlow)
        {
         bool bBuy = (g_devBuy >= InpTriggerPoints &&
                      (InpMaxDevPoints <= 0 || g_devBuy <= InpMaxDevPoints));
         bool bSell = (g_devSell >= InpTriggerPoints &&
                       (InpMaxDevPoints <= 0 || g_devSell <= InpMaxDevPoints));
         if(bBuy && bSell)
            sig = (g_devBuy >= g_devSell ? 1 : -1);
         else if(bBuy)
            sig = 1;
         else if(bSell)
            sig = -1;
        }
      if(sig != g_sig)
        {
         if(sig != 0)
           {
            g_lastSignalTime = now;
            Print("SINYAL ", (sig > 0 ? "BUY" : "SELL"),
                  " dev=", DoubleToString(sig > 0 ? g_devBuy : g_devSell, 1),
                  " pts, umur feed=", IntegerToString((long)g_fastAgeMs), "ms",
                  (InpDryRun ? " [DRY-RUN]" : " [LIVE]"));
           }
         g_sig = sig;
        }

      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      bool spreadOK = (InpMaxSpreadPoints <= 0 || spread <= InpMaxSpreadPoints);
      bool coolOK = (now - g_lastAction >= InpCooldownSec);
      bool tradesOK = (InpMaxTradesPerDay <= 0 || g_trades < InpMaxTradesPerDay);
      bool timeOK = TimeAllowed();
      bool terminalOK = (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
                        (bool)MQLInfoInteger(MQL_TRADE_ALLOWED);
      bool accountOK = (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);

      if(!g_haveFast)
         status = "Menunggu file FAST (writer belum jalan?)";
      else if(!g_fresh)
         status = "Feed STALE (terminal FAST putus?)";
      else if(sig == 0)
         status = "Menunggu sinyal...";
      else if(!spreadOK)
         status = "Blokir: spread terlalu besar";
      else if(!coolOK)
         status = "Cooldown...";
      else if(!tradesOK)
         status = "Blokir: maks transaksi harian";
      else if(g_dailyBlocked)
         status = "Blokir: stop harian tercapai";
      else if(!timeOK)
         status = "Blokir: di luar jam trading";
      else if(!terminalOK)
         status = "Blokir: Algo Trading mati";
      else if(!accountOK)
         status = "Blokir: akun tidak mengizinkan trading";
      else if(InpDryRun)
         status = "DRY-RUN: sinyal " + (sig > 0 ? "BUY" : "SELL") + " (tanpa order)";
      else
         status = "EKSEKUSI " + (sig > 0 ? "BUY" : "SELL");

      if(sig != 0 && spreadOK && coolOK && tradesOK && !g_dailyBlocked &&
         timeOK && terminalOK && accountOK && !InpDryRun)
         OpenTrade(sig);
     }

   if(InpShowDashboard)
      DrawDash(bid, ask, okSlow, status);
   else
      Comment("");
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawDash(const double bid, const double ask, const bool okSlow, const string status)
  {
   string accCur = AccountInfoString(ACCOUNT_CURRENCY);
   ENUM_ACCOUNT_TRADE_MODE tm = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   string accType = (tm == ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : (tm == ACCOUNT_TRADE_MODE_REAL ? "REAL" : "CONTEST"));
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   string feedLine;
   if(!g_haveFast)
      feedLine = "FAST " + g_fastSym + ": TIDAK ADA FILE (writer belum jalan?)";
   else
      feedLine = StringFormat("FAST %s: %s/%s | umur %s ms [%s] | err %s",
                              g_fastSym,
                              DoubleToString(g_fast.bid, _Digits), DoubleToString(g_fast.ask, _Digits),
                              IntegerToString((long)g_fastAgeMs), (g_fresh ? "FRESH" : "STALE"),
                              IntegerToString(g_readErr));

   string s = "";
   s += "===== LATENCY ARBITRAGE (SLOW) =====\n";
   s += StringFormat("MODE: %s | Akun: %s (%s)\n", (InpDryRun ? "DRY-RUN" : "LIVE"), accType, accCur);
   s += feedLine + "\n";
   if(okSlow)
      s += StringFormat("SLOW %s: %s/%s (sp %s)\n", _Symbol,
                        DoubleToString(bid, _Digits), DoubleToString(ask, _Digits),
                        IntegerToString(spread));
   else
      s += "SLOW: harga belum siap\n";
   s += StringFormat("Dev BUY: %s pts | Dev SELL: %s pts | trigger: %s pts\n",
                     DoubleToString(g_devBuy, 1), DoubleToString(g_devSell, 1),
                     DoubleToString(InpTriggerPoints, 1));

   ulong ticket = 0;
   int ptype = -1;
   double open = 0.0;
   datetime otime = 0;
   if(FindOurPosition(ticket, ptype, open, otime))
     {
      bool isBuy = (ptype == POSITION_TYPE_BUY);
      double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double cur = (isBuy ? bid : ask);
      double ppts = (isBuy ? (cur - open) : (open - cur)) / pt;
      s += StringFormat("Posisi: %s %s lot @ %s | %s pts\n", (isBuy ? "BUY" : "SELL"),
                        DoubleToString(PositionGetDouble(POSITION_VOLUME), 2),
                        DoubleToString(open, _Digits), SignedPts(ppts));
     }
   else
      s += "Posisi: tidak ada\n";

   s += StringFormat("Hari ini: %s transaksi | W%s/L%s | %s %s\n",
                     IntegerToString(g_trades), IntegerToString(g_wins), IntegerToString(g_losses),
                     ((g_dayProfit >= 0 ? "+" : "") + DoubleToString(g_dayProfit, 2)), accCur);
   s += "Sinyal terakhir: " + (g_lastSignalTime > 0 ? TimeToString(g_lastSignalTime, TIME_SECONDS) : "-") + "\n";
   s += "Status: " + status;
   Comment(s);
  }
//+------------------------------------------------------------------+
