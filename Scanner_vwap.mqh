//+------------------------------------------------------------------+
//|                                                                  |
//| Scanner_vwap.mqh — SCANNER VWAP MENSUEL +1σ SOLO (XAUUSD H1)    |
//|                                                                  |
//| Adaptation du script Pine "SCANNER VWAP MENSUEL | XAUUSD H1 |   |
//| SOLO | 2R" (04_VWAP_OR_SOLO.pine) dans l'architecture parallèle  |
//| multi-scanners de Koenigin.                                      |
//|                                                                  |
//| - Classe CONCRETE CScannerVwap (pas d'héritage, pas de virtual)  |
//| - LONG : crossover haussier de la bande VWAP +1σ mensuelle —    |
//|   toujours actif (le Pine d'origine est long uniquement)         |
//| - SHORT : crossunder baissier de la bande VWAP +1σ (miroir) —   |
//|   OPTIONNEL, input K_VWAP_Short = false par défaut. Touche       |
//|   personnelle Koenigin (même pattern que K_EMA50_Short,          |
//|   K_RSI7_Short, K_BB10_Short)                                    |
//| - VWAP = Volume Weighted Average Price MENSUEL : reset au début  |
//|   de chaque mois calendaire (UTC). Calcul MANUEL (pas de handle  |
//|   MT5 : l'indicateur iCustom("VWAP") n'est pas standard et les  |
//|   conventions de reset ne sont pas garanties identiques à Pine)  |
//| - upper = vwap + 1*sd (sd = écart-type POPULATION pondéré par    |
//|   le volume, identique au Pine : sqrt(sum(V*P²)/sum(V) - vwap²))|
//| - LONG  (Pine l.43) : sd>0 AND close[1]<=upper[1] AND           |
//|   close>upper AND age>=3 AND volume>0                            |
//|   = première clôture de croisement AU-DESSUS de la bande +1σ     |
//| - SHORT (miroir maison) : sd>0 AND close[1]>=lower[1] AND       |
//|   close<lower AND age>=3 AND volume>0                            |
//|   = première clôture de croisement EN-DESSOUS de la bande -1σ    |
//| - SL long = plus BAS des N bougies ; SL short = plus HAUT       |
//|   (bougie signal incluse, N = K_VWAP_SL_Bars, Pine : 10)        |
//| - TP long = entry + 2R (ask) ; TP short = entry - 2R (bid)      |
//| - 1 trade simultané max (HasPositionForSymbol) — verrou SOLO     |
//| - Entrée au marché (IsMarketOrder = true) au 1er tick qui suit   |
//|   la clôture de la bougie de signal                              |
//| - Pas de break-even, pas de trailing (fidélité Pine)             |
//|                                                                  |
//| === TRADUCTION PINE → MQL5 ===                                   |
//| - "TF Valide" (graphe H1 imposé)      → K_VWAP_TF (le scanner   |
//|   travaille sur SON TF, quel que soit le TF du chart)            |
//| - barstate.isconfirmed               → anti-rejeu de CStrategy : |
//|   EvaluateBar() est appelé au 1er tick de chaque nouvelle bougie |
//|   K_VWAP_TF (la bougie signal = shift 1, clôturée) et FIGE la   |
//|   décision ; GetSignal() la consomme après les filtres           |
//| - reset mensuel (key = year*100+month) → identique dans          |
//|   VwapBandsAt() : recherche du début de mois, cumul séquentiel   |
//|   des barres du mois en cours                                    |
//| - age >= 3 : au moins 3 barres dans le mois (le VWAP n'est pas  |
//|   significatif avec 1-2 barres)                                  |
//| - volume > 0 : filtre de validité (pas de VWAP sans volume)     |
//| - ÉTAT PERSISTANT → position RÉELLE : verrou SOLO =              |
//|   HasPositionForSymbol, bracket SL/TP posé par le broker         |
//| - Capital virtuel / commissions du Pine → NON REPRODUITS :       |
//|   sizing par le module MONEY standard                            |
//| - Portes de dates TV (startDate/limitEnd/endDate) et strictChart  |
//|   → non reproduites : artefacts de la simulation TradingView     |
//|                                                                  |
//| Le scanner ne fait AUCUN appel direct à BROKER, MONEY ou DATAS.  |
//| Il remplit STRUCT_STRATEGY et CStrategy fait le reste.           |
//|                                                                  |
//| ARCHITECTURE : SANS ÉTAT glissant (pas de machine à pivots type  |
//| RSI7 — le VWAP se recalcule à la demande sur les barres du mois  |
//| courant), avec une DÉCISION FIGÉE PAR BOUGIE : EvaluateBar()     |
//| (pattern BB10) lit les données et stocke la décision ;           |
//| GetSignal() consomme cette décision (garde ask/bid au tick       |
//| courant uniquement).                                             |
//+------------------------------------------------------------------+


//////////////////////////////////////////////////////////
//                                                      //
//              C O N S T A N T E S                     //
//                                                      //
//////////////////////////////////////////////////////////
// Garde d'historique minimal (Pine : bar_index >= 200 sur la bougie
// SIGNAL). Le contrôle applique Bars()-2 >= 200 (convention projet).
#define VWAP_WARMUP_BARS  200

//////////////////////////////////////////////////////////
//                                                      //
//              I N P U T S                             //
//                                                      //
//////////////////////////////////////////////////////////
// Auto-contenus : chaque scanner apporte SES réglages dans SON
// fichier (convention "panier de stratégies"). Ils apparaissent
// dans la fenêtre de réglages de l'EA dès que le scanner est
// inclus par Strategy.mqh.
//============================================
//---   Paramètres SCANNER VWAP MENSUEL SOLO
//============================================
// PANIER DE STRATÉGIES : greffé ≠ tradé.
// Ce toggle décide si CE scanner trade. Le scanner reste câblé dans
// Strategy (Config/Detection) mais DORMANT tant que la case
// n'est pas cochée : aucun signal, aucune entrée. Les positions
// déjà ouvertes avant dé-sélection courent jusqu'à leur SL/TP
// (portés par le broker — jamais touchées par le toggle).
// False par défaut : rien ne trade tant que l'utilisateur n'a
// rien choisi dans le panier.
input group "📁 STRATÉGIE VWAP OR"
input bool               K_VWAP_Trade   = false;       // Panier : trader VWAP SOLO ?
input ENUM_TIMEFRAMES    K_VWAP_TF      = PERIOD_H1;   // TF de travail (Pine : TF Valide = H1)
input uint               K_VWAP_SL_Bars = 10;          // Plus bas de combien de bougies pour le SL (Pine : 10)
input double             K_VWAP_TP_R    = 2.0;         // Objectif TP en R (Pine : 2R)
// SHORT OPTIONNEL : le Pine d'origine est long uniquement.
// K_VWAP_Short=true ajoute le miroir : première clôture sous la bande
// -1σ ; SL = plus HAUT des N bougies ; TP = bid - 2R.
// False par défaut = fidélité Pine.
input bool               K_VWAP_Short   = false;       // Activer short (Pine : long uniquement)

//////////////////////////////////////////////////////////
//                                                      //
//                 I N C L U D E S                      //
//                                                      //
//////////////////////////////////////////////////////////
#include <Koenigin/Type.mqh>
#include <Koenigin/Log.mqh>
#include <Koenigin/Tools.mqh>


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CScannerVwap
{
//==================================
//--- PRIVATE
//==================================
private:
    // Identité du scanner
    //---------------------
    string          m_Name;             // Nom logique ("VwapScanner") — préfixe du comment d'ordre
    ENUM_TIMEFRAMES m_TF;               // Timeframe de travail (K_VWAP_TF)

    // Décision FIGÉE de la dernière bougie clôturée évaluée
    // (pattern BB10 P1-2 : EvaluateBar → GetSignal). Propriétés
    // immuables de la bougie clôturée, posées à son évaluation
    // et consommées par GetSignal.
    //----------------------------------------------------------------
    int             m_BarDir;           // 0 = pas de signal, +1 = long, -1 = short
    double          m_BarSL;            // SL du signal : extrême des K_VWAP_SL_Bars bougies
    double          m_BarClose;         // clôture de la bougie signal (journal)
    double          m_BarBand;          // bande de croisement : +1σ (long) / -1σ (short) (journal)

    //+--------------------------------------------------------+
    //| VwapBandsAt                                             |
    //| Calcule le VWAP mensuel et son écart-type pondéré par   |
    //| le volume sur les barres du mois en cours, à partir     |
    //| d'un shift donné.                                       |
    //|                                                         |
    //| Le VWAP utilise HLC3 (= (High+Low+Close)/3) comme prix |
    //| typique, identique au Pine (hlc3).                      |
    //|                                                         |
    //| sd = écart-type POPULATION pondéré par le volume :      |
    //|   vwap = sum(V*P) / sum(V)                              |
    //|   sd = sqrt(sum(V*P²)/sum(V) - vwap²)                  |
    //| Identique au calcul Pine (l.24-38).                     |
    //|                                                         |
    //| INPUT:                                                  |
    //|   i_shift : shift de la bougie dont on veut le VWAP     |
    //|             (1 = bougie signal, 2 = bougie précédente)  |
    //| OUTPUT:                                                 |
    //|   o_upper : bande +1σ (vwap + sd)                       |
    //|   o_lower : bande -1σ (vwap - sd) [pour le short]       |
    //|   o_age   : nombre de barres dans le mois courant       |
    //|   Retour : TRUE si le calcul a réussi                   |
    //+--------------------------------------------------------+
    bool VwapBandsAt(const int i_shift, double &o_upper, double &o_lower, int &o_age)
    {
        o_upper = 0.0;
        o_lower = 0.0;
        o_age   = 0;

        // (1) Récupérer le mois/année de la bougie cible
        //--------------------------------------------------
        datetime bar_time[];
        if (CopyTime(Symbol(), m_TF, i_shift, 1, bar_time) < 1) return(false);

        MqlDateTime dt;
        TimeToStruct(bar_time[0], dt);
        int target_year  = dt.year;
        int target_month = dt.mon;

        // (2) Scanner en arrière pour trouver toutes les barres de ce mois
        //    On remonte depuis i_shift jusqu'à trouver un changement de mois.
        //    Nombre max de barres à vérifier : un mois H1 ≈ 31*24 = 744 barres.
        //------------------------------------------------------------------
        int max_scan = 800;     // marge de sécurité
        int total_bars = Bars(Symbol(), m_TF);

        // Trouver le premier shift du mois (le plus ancien dans le mois)
        int first_shift = i_shift;
        for (int s = i_shift + 1; s < i_shift + max_scan && s < total_bars; s++)
        {
            datetime t[];
            if (CopyTime(Symbol(), m_TF, s, 1, t) < 1) break;
            MqlDateTime dts;
            TimeToStruct(t[0], dts);
            if (dts.year != target_year || dts.mon != target_month)
                break;
            first_shift = s;
        }

        // (3) Charger les données du mois (de first_shift à i_shift inclus)
        //-------------------------------------------------------------------
        int count = first_shift - i_shift + 1;
        if (count < 1) return(false);

        double highs[], lows[], closes[];
        long   volumes[];
        if (CopyHigh  (Symbol(), m_TF, i_shift, count, highs)   < count) return(false);
        if (CopyLow   (Symbol(), m_TF, i_shift, count, lows)    < count) return(false);
        if (CopyClose  (Symbol(), m_TF, i_shift, count, closes)  < count) return(false);
        if (CopyTickVolume(Symbol(), m_TF, i_shift, count, volumes) < count) return(false);

        // Les tableaux Copy* sont chronologiques (index 0 = plus ancien = first_shift,
        // index count-1 = plus récent = i_shift)

        // (4) Calcul VWAP cumulatif (Pine l.24-38)
        //   sv  += volume
        //   sp  += volume * hlc3
        //   sp2 += volume * hlc3 * hlc3
        //   vwap = sp / sv
        //   sd   = sqrt(max(0, sp2/sv - vwap²))
        //-------------------------------------------
        double sv  = 0.0;
        double sp  = 0.0;
        double sp2 = 0.0;
        int    age = 0;

        for (int i = 0; i < count; i++)
        {
            double vol = (double)volumes[i];
            if (vol <= 0.0) continue;   // skip barres sans volume

            double hlc3 = (highs[i] + lows[i] + closes[i]) / 3.0;
            sv  += vol;
            sp  += vol * hlc3;
            sp2 += vol * hlc3 * hlc3;
            age++;
        }

        if (sv <= 0.0) return(false);   // pas de volume du tout

        double vwap = sp / sv;
        double var  = sp2 / sv - vwap * vwap;
        if (var < 0.0) var = 0.0;   // protection flottante
        double sd   = MathSqrt(var);

        o_upper = vwap + sd;
        o_lower = vwap - sd;
        o_age   = age;

        return(true);
    }

//==================================
//--- PUBLIC
//==================================
public:

    //+--------------------------------------------------------+
    //| Config                                                  |
    //+--------------------------------------------------------+
    bool Config(const string i_name, const ENUM_TIMEFRAMES i_tf)
    {
        m_Name = i_name;
        m_TF   = i_tf;

        // Réinitialise la décision figée (hygiène de démarrage)
        //--------------------------------------------------------
        m_BarDir   = 0;
        m_BarSL    = 0.0;
        m_BarClose = 0.0;
        m_BarBand  = 0.0;

        // Validation FAIL-FAST des paramètres (pattern BB10)
        //---------------------------------------------------------------
        if (K_VWAP_SL_Bars < 1)
        {
            LOG.ERROR(m_Name + " : K_VWAP_SL_Bars invalide (" +
                      IntegerToString((int)K_VWAP_SL_Bars) +
                      ") — minimum 1 requis (référence Pine : 10)", __FUNCTION__);
            return(false);
        }
        if (K_VWAP_TP_R <= 0.0)
        {
            LOG.ERROR(m_Name + " : K_VWAP_TP_R invalide (" +
                      DoubleToString(K_VWAP_TP_R, 2) +
                      ") — strictement positif requis (référence Pine : 2R)", __FUNCTION__);
            return(false);
        }

        LOG.INFO(m_Name + " : Scanner VWAP MENSUEL SOLO initialisé (TF=" +
                 PeriodToString(m_TF) +
                 ", SL_Bars=" + IntegerToString((int)K_VWAP_SL_Bars) +
                 ", TP_R=" + DoubleToString(K_VWAP_TP_R, 2) + ")", __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| End                                                     |
    //+--------------------------------------------------------+
    //| Pas de handle d'indicateur à libérer : le VWAP est      |
    //| calculé à la demande sur CopyHigh/Low/Close/Volume.     |
    //+--------------------------------------------------------+
    void End(void)
    {
    }

    //+--------------------------------------------------------+
    //| HasPositionForSymbol                                   |
    //| Une position OUVERTE existe-t-elle pour CE scanner ?    |
    //| C'est le verrou SOLO du Pine ("active") : tant qu'une  |
    //| position existe, aucune nouvelle entrée n'est possible. |
    //+--------------------------------------------------------+
    bool HasPositionForSymbol(void)
    {
        for (int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong l_Ticket = PositionGetTicket(i);
            if (PositionGetString (POSITION_SYMBOL) != Symbol())              continue;
            if (PositionGetInteger(POSITION_MAGIC)  != (K_Magic + I_Robot_ID)) continue;

            string l_comment = PositionGetString(POSITION_COMMENT);
            if (StringFind(l_comment, m_Name) < 0) continue;

            return(true);
        }
        return(false);
    }

    //+--------------------------------------------------------+
    //| EvaluateBar                                             |
    //|--------------------------------------------------------|
    //| Évalue la bougie qui vient de clôturer (shift 1) et     |
    //| FIGE sa décision (sens + SL + niveaux). Appelé par      |
    //| CStrategy::Detection() au 1er tick de chaque nouvelle   |
    //| bougie K_VWAP_TF, AVANT les filtres d'exécution.        |
    //|                                                         |
    //| CONTRAT :                                               |
    //|   FALSE = données INDISPONIBLES → le scheduler NE       |
    //|           VALIDE PAS la bougie → retry au tick suivant   |
    //|   TRUE  = lecture FAITE → décision figée dans m_BarDir  |
    //|                                                         |
    //| Le VWAP est recalculé intégralement sur les barres du   |
    //| mois courant à chaque appel (pas d'état glissant).      |
    //|                                                         |
    //| Idempotent : rappelé sur la même bougie → même décision.|
    //|                                                         |
    //| IMPORTANT : ne JAMAIS appeler BROKER/MONEY/DATAS ici.   |
    //+--------------------------------------------------------+
    bool EvaluateBar(void)
    {
        // Réinitialise la décision de la bougie
        //----------------------------------------
        m_BarDir   = 0;
        m_BarSL    = 0.0;
        m_BarClose = 0.0;
        m_BarBand  = 0.0;

        // (1) Historique minimal (Pine : bar_index >= 200 sur la bougie
        //     SIGNAL = Bars()-2 >= 200)
        //----------------------------------------------------------------
        if (Bars(Symbol(), m_TF) < VWAP_WARMUP_BARS + 2) return(true);

        // (2) Clôtures des shifts 1 et 2 pour le croisement
        //-----------------------------------------------------
        double c[];
        ArraySetAsSeries(c, true);
        if (CopyClose(Symbol(), m_TF, 1, 2, c) < 2)
        {
            LOG.WARNING(m_Name + " : CopyClose indisponible — retry au tick suivant", __FUNCTION__);
            return(false);
        }
        double close1 = c[0];   // bougie signal (shift 1)
        double close2 = c[1];   // bougie précédente (shift 2)
        if (close1 <= 0.0 || close2 <= 0.0)
        {
            LOG.WARNING(m_Name + " : clôtures invalides — retry au tick suivant", __FUNCTION__);
            return(false);
        }

        // (3) Volume de la bougie signal (Pine : not na(volume) and volume>0)
        //---------------------------------------------------------------------
        long vol1[];
        if (CopyTickVolume(Symbol(), m_TF, 1, 1, vol1) < 1)
        {
            LOG.WARNING(m_Name + " : volume indisponible — retry au tick suivant", __FUNCTION__);
            return(false);
        }
        if (vol1[0] <= 0)
        {
            // Pine l.43 : volume>0 — pas de signal sans volume
            return(true);   // lecture OK, pas de signal → bougie validée
        }

        // (4) Bandes VWAP des bougies signal (shift 1) et précédente (shift 2)
        //----------------------------------------------------------------------
        double upper1 = 0.0, lower1 = 0.0;
        double upper2 = 0.0, lower2 = 0.0;
        int    age1 = 0, age2 = 0;
        if (!VwapBandsAt(1, upper1, lower1, age1))
        {
            LOG.WARNING(m_Name + " : VWAP shift 1 indisponible — retry au tick suivant", __FUNCTION__);
            return(false);
        }
        if (!VwapBandsAt(2, upper2, lower2, age2))
        {
            LOG.WARNING(m_Name + " : VWAP shift 2 indisponible — retry au tick suivant", __FUNCTION__);
            return(false);
        }

        // (5) Écart-type > 0 (Pine : sd>0 dans la condition signal)
        //    Si upper == lower, sd == 0 → pas de signal
        //------------------------------------------------------------
        double sd1 = (upper1 - lower1) / 2.0;   // upper = vwap+sd, lower = vwap-sd → sd = (upper-lower)/2
        if (sd1 <= 0.0) return(true);

        // (6) Age >= 3 (Pine l.43 : and age>=3)
        //    Nombre de barres dans le mois courant pour la bougie signal
        //----------------------------------------------------------------
        if (age1 < 3) return(true);

        // === DÉTECTION DE SENS ===
        // LONG  (Pine l.43) :
        //   signal = sd>0 and close[1]<=upper[1] and close>upper and age>=3 and volume>0
        //   → la bougie PRÉCÉDENTE clôturait sous/sur la bande +1σ,
        //     la bougie SIGNAL clôture AU-DESSUS de la bande +1σ.
        // SHORT (miroir maison, gated par K_VWAP_Short) :
        //   close[1]>=lower[1] and close<lower
        //---------------------------------------------------------------
        bool go_long  = (close2 <= upper2) && (close1 > upper1);
        bool go_short = K_VWAP_Short && (close2 >= lower2) && (close1 < lower1);
        if (!go_long && !go_short) return(true);   // lecture OK, pas de signal

        // Tick size (filtre anti-risque-nul, commun aux deux sens)
        //-----------------------------------------------------------
        double min_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if (min_tick <= 0.0) min_tick = _Point;

        if (go_long)
        {
            // === LONG : SL = PLUS BAS DES N BOUGIES ===
            // (Pine : stopCandidate = ta.lowest(low,10) sur la bougie
            //  de signal — iLowest(shift 1, count N) couvre shifts 1..N)
            //------------------------------------------------------
            int lowest_idx = iLowest(Symbol(), m_TF, MODE_LOW, (int)K_VWAP_SL_Bars, 1);
            if (lowest_idx < 0)
            {
                LOG.WARNING(m_Name + " : iLowest indisponible — retry au tick suivant", __FUNCTION__);
                return(false);
            }
            double sl = iLow(Symbol(), m_TF, lowest_idx);

            // === FILTRE PINE SUR LA CLÔTURE (convention audit P1-2) ===
            // Pine l.75/l.80 : distance = close - stopCandidate > mintick
            //--------------------------------------------------------------
            if (close1 - sl <= min_tick)
            {
                LOG.INFO(m_Name + " : VWAP ACHAT rejeté par le filtre Pine (distance clôture-SL <= mintick)", __FUNCTION__);
                return(true);
            }

            // === DÉCISION LONG FIGÉE ===
            //------------------------------------------------------
            m_BarDir   = 1;
            m_BarSL    = sl;
            m_BarClose = close1;
            m_BarBand  = upper1;

            LOG.INFO(m_Name + " : VWAP détection ACHAT crossover bande +1σ | Close=" +
                     DoubleToString(close1, _Digits) +
                     " | Upper=" + DoubleToString(upper1, _Digits) +
                     " | SL "    + IntegerToString((int)K_VWAP_SL_Bars) + " bars=" +
                                  DoubleToString(sl, _Digits) +
                     " | age=" + IntegerToString(age1),
                     __FUNCTION__);
            return(true);
        }

        // === SHORT : MIROIR EXACT DU LONG (bande -1σ) ===
        //----------------------------------------------------
        int highest_idx = iHighest(Symbol(), m_TF, MODE_HIGH, (int)K_VWAP_SL_Bars, 1);
        if (highest_idx < 0)
        {
            LOG.WARNING(m_Name + " : iHighest indisponible — retry au tick suivant", __FUNCTION__);
            return(false);
        }
        double sl = iHigh(Symbol(), m_TF, highest_idx);

        // === FILTRE PINE MIROIR : SL - CLÔTURE > mintick ===
        //--------------------------------------------------------------------
        if (sl - close1 <= min_tick)
        {
            LOG.INFO(m_Name + " : VWAP VENTE rejetée par le filtre Pine miroir (SL-clôture <= mintick)", __FUNCTION__);
            return(true);
        }

        // === DÉCISION SHORT FIGÉE ===
        //--------------------------------------------------------
        m_BarDir   = -1;
        m_BarSL    = sl;
        m_BarClose = close1;
        m_BarBand  = lower1;

        LOG.INFO(m_Name + " : VWAP détection VENTE crossunder bande -1σ | Close=" +
                 DoubleToString(close1, _Digits) +
                 " | Lower=" + DoubleToString(lower1, _Digits) +
                 " | SL "    + IntegerToString((int)K_VWAP_SL_Bars) + " bars=" +
                              DoubleToString(sl, _Digits) +
                 " | age=" + IntegerToString(age1),
                 __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| GetSignal                                               |
    //|--------------------------------------------------------|
    //| Consomme la décision figée par EvaluateBar(). Ne        |
    //| recalcule RIEN : VWAP, croisement, SL et filtre Pine   |
    //| sur la clôture sont des propriétés immuables de la      |
    //| bougie clôturée. Seule la GARDE D'EXÉCUTION sur le      |
    //| prix réel du tick courant (adaptation MQL5).            |
    //|                                                         |
    //| INPUT:                                                  |
    //|   i_tick : tick courant (ask/bid réels d'exécution)     |
    //| OUTPUT:                                                 |
    //|   o_datas : STRUCT_STRATEGY rempli si retourne TRUE     |
    //|   Retour : TRUE si signal émis                          |
    //|                                                         |
    //| IMPORTANT : ne JAMAIS appeler BROKER/MONEY/DATAS ici.   |
    //+--------------------------------------------------------+
    bool GetSignal(const MqlTick &i_tick, STRUCT_STRATEGY &o_datas)
    {
        // Bougie sans signal → rien à exécuter
        //------------------------------------------------------------
        if (m_BarDir == 0) return(false);

        // Tick size (garde anti-risque-nul au prix d'exécution)
        //-----------------------------------------------------------
        double min_tick = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if (min_tick <= 0.0) min_tick = _Point;

        if (m_BarDir > 0)
        {
            // === LONG : GARDE D'EXÉCUTION + REMPLISSAGE ===
            //-------------------------------------------------------------------
            double entry = i_tick.ask;
            double risk  = entry - m_BarSL;
            if (risk <= min_tick) return(false);

            ZeroMemory(o_datas);
            o_datas.Trend         = eT_Bull;
            o_datas.Entry         = entry;
            o_datas.StopLoss      = m_BarSL;
            o_datas.TakeProfit    = entry + K_VWAP_TP_R * risk;
            o_datas.IsMarketOrder = true;

            LOG.INFO(m_Name + " : VWAP ACHAT exécution | Ask=" +
                     DoubleToString(entry, _Digits) +
                     " | SL="  + DoubleToString(m_BarSL, _Digits) +
                     " | TP="  + DoubleToString(o_datas.TakeProfit, _Digits) +
                     " | R="   + DoubleToString(K_VWAP_TP_R, 2),
                     __FUNCTION__);
            return(true);
        }

        // === SHORT : MIROIR EXACT DU LONG ===
        //------------------------------------------------------------
        double entry = i_tick.bid;
        double risk  = m_BarSL - entry;
        if (risk <= min_tick) return(false);

        ZeroMemory(o_datas);
        o_datas.Trend         = eT_Bear;
        o_datas.Entry         = entry;
        o_datas.StopLoss      = m_BarSL;
        o_datas.TakeProfit    = entry - K_VWAP_TP_R * risk;
        o_datas.IsMarketOrder = true;

        LOG.INFO(m_Name + " : VWAP VENTE exécution | Bid=" +
                 DoubleToString(entry, _Digits) +
                 " | SL="  + DoubleToString(m_BarSL, _Digits) +
                 " | TP="  + DoubleToString(o_datas.TakeProfit, _Digits) +
                 " | R="   + DoubleToString(K_VWAP_TP_R, 2),
                 __FUNCTION__);
        return(true);
    }

    //+--------------------------------------------------------+
    //| GetNamePublic                                          |
    //+--------------------------------------------------------+
    string GetNamePublic(void) { return(m_Name); }

};  // fin de la classe CScannerVwap
