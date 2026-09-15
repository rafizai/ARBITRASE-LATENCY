//+------------------------------------------------------------------+
//|                                              FastFeedWriter.mq5  |
//|   Latency Arbitrage - sisi FAST (terminal broker cepat)          |
//|                                                                  |
//|   CARA KERJA:                                                    |
//|   EA ini dipasang di terminal MT5 yang login ke broker CEPAT.    |
//|   Setiap beberapa milidetik ia menulis quote (bid/ask) ke file   |
//|   di folder Common Files, yang kemudian dibaca oleh EA           |
//|   LatencyArb.mq5 di terminal broker LAMBAT (mesin/PC yang sama). |
//|                                                                  |
//|   File: <Common>\Files\LatencyArb\<PREFIX>_<SIMBOL>.csv          |
//|   Isi:  bid,ask,tick_ms,waktu_server                             |
//|                                                                  |
//|   PREFIX: samakan dengan InpFeedPrefix di pembaca. Default       |
//|   "FAST". Untuk mengukur 2 broker (FeedLagMeter), pakai "A" di   |
//|   satu terminal dan "B" di terminal lain.                        |
//+------------------------------------------------------------------+
#property copyright "Dibuat dengan bantuan Arena.ai Agent - untuk edukasi"
#property version   "1.10"
#property description "Latency Arb sisi FAST: publish quote ke Common Files untuk dibaca terminal SLOW."

input group "Feed"
input string InpSymbols       = "EURUSD,GBPUSD,USDJPY,XAUUSD"; // Simbol yg dipublish (nama di broker ini, pisahkan koma)
input string InpPrefix        = "FAST";                        // Prefix file (samakan dgn pembaca; ukur 2 broker: "A"/"B")
input int    InpPublishMs     = 50;                            // Interval tulis (milidetik)
input bool   InpShowDashboard = true;                          // Tampilkan dashboard

string   g_syms[];
datetime g_lastWrite = 0;
long     g_writes = 0;
long     g_writeErr = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   FolderCreate("LatencyArb", FILE_COMMON);

   if(InpPrefix == "")
     {
      Print("ERROR: InpPrefix tidak boleh kosong.");
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- pecah daftar simbol
   string parts[];
   int n = StringSplit(InpSymbols, ',', parts);
   ArrayResize(g_syms, 0);
   for(int i = 0; i < n; i++)
     {
      StringTrimLeft(parts[i]);
      StringTrimRight(parts[i]);
      if(parts[i] != "")
        {
         int sz = ArraySize(g_syms);
         ArrayResize(g_syms, sz + 1);
         g_syms[sz] = parts[i];
        }
     }
   if(ArraySize(g_syms) == 0)
     {
      Print("ERROR: InpSymbols kosong.");
      return(INIT_PARAMETERS_INCORRECT);
     }
   for(int i = 0; i < ArraySize(g_syms); i++)
      SymbolSelect(g_syms[i], true);

   int ms = (InpPublishMs < 5 ? 5 : InpPublishMs);
   if(!EventSetMillisecondTimer(ms))
     {
      Print("ERROR: gagal menyalakan timer.");
      return(INIT_FAILED);
     }
   Print("FastFeedWriter jalan. Prefix=", InpPrefix, " Simbol: ", InpSymbols, " tiap ", IntegerToString(ms), " ms.");
   Print("Folder file: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\LatencyArb\\");
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

void OnTick()  { Publish(); }
void OnTimer() { Publish(); }

//+------------------------------------------------------------------+
//| Tulis quote semua simbol ke file (1 file per simbol).            |
//+------------------------------------------------------------------+
void Publish()
  {
   uint now = GetTickCount();   // jam lokal PC (ms) - sebanding antar terminal di PC yang sama
   string srv = TimeToString(TimeTradeServer(), TIME_DATE | TIME_SECONDS);
   for(int i = 0; i < ArraySize(g_syms); i++)
     {
      string sym = g_syms[i];
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(bid <= 0 || ask <= 0)
         continue;
      string path = "LatencyArb\\" + InpPrefix + "_" + sym + ".csv";
      int h = INVALID_HANDLE;
      for(int attempt = 0; attempt < 4 && h == INVALID_HANDLE; attempt++)
        {
         if(attempt > 0)
            Sleep(2);   // file sedang dibaca pihak lain, tunggu sebentar & coba lagi
         h = FileOpen(path, FILE_WRITE | FILE_TXT | FILE_COMMON | FILE_ANSI);
        }
      if(h == INVALID_HANDLE)
        {
         g_writeErr++;
         continue;
        }
      string line = StringFormat("%s,%s,%s,%s",
                                 DoubleToString(bid, 8), DoubleToString(ask, 8),
                                 IntegerToString((long)now), srv);
      FileWrite(h, line);
      FileClose(h);
      g_writes++;
     }
   g_lastWrite = TimeCurrent();
   if(InpShowDashboard)
      DrawDash();
   else
      Comment("");
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void DrawDash()
  {
   string s = "";
   s += "===== FAST FEED WRITER =====\n";
   s += "Prefix: " + InpPrefix + " | Publish: " + InpSymbols + "\n";
   s += "Tulis ke-" + IntegerToString(g_writes) +
        " | terakhir " + TimeToString(g_lastWrite, TIME_SECONDS) +
        " | gagal " + IntegerToString(g_writeErr) + "\n";
   s += "Folder: " + TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\LatencyArb\\\n";
   s += "Pastikan terminal pembaca menampilkan path Common yang SAMA.";
   Comment(s);
  }
//+------------------------------------------------------------------+
