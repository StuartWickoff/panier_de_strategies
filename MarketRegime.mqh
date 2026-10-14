//+------------------------------------------------------------------+
//|                                                                  |
//| MarketRegime.mqh — FILTRE DE RÉGIME DE MARCHÉ H4 (transversal)   |
//|                                                                  |
//| RÔLE : module transversal (PAS un scanner) qui décide QUELLE     |
//| stratégie du panier a le droit de trader selon la tendance de    |
//| fond H4 — les scanners restent des îlots Pine-fidèles            |
//| intouchables (principe : ne pas polluer les scanners).           |
//|                                                                  |
//| RÈGLE (spéc utilisateur, gold, stratégies H1 pilotées en H4) :   |
//|   Bougie H4 CLÔTURÉE (shift 1, anti-repaint — le régime est      |
//|   figé jusqu'à la prochaine clôture H4) :                        |
//|     close > EMA50 > EMA100  ->  eMR_Bull                          |
//|     close < EMA50 < EMA100  ->  eMR_Bear                          |
//|     sinon (EMAs entrelacées) ->  eMR_Range                        |
//|                                                                  |
//| TABLE DE DÉCISION (branchée dans Strategy.mqh) :                 |
//|   Bull  -> EMA50 LONG uniquement   (veto TryEma50 si eT_Bear)    |
//|   Bear  -> EMA50 SHORT uniquement  (veto TryEma50 si eT_Bull)    |
//|   Range -> la stratégie choisie par K_Regime_RangeStrategy       |
//|            (eRRS_Rsi7 ou eRRS_Bb10 ; eRRS_None = aucune)         |
//|   Inconnu -> TOUT est vetoé (fail-closed : données H4            |
//|            indisponibles = pas de trade, convention codebase)    |
//|                                                                  |
//| FAIL-CLOSED : Update() retourne false et laisse m_Regime à       |
//| eMR_Unknown tant que CopyClose/CopyBuffer échouent ;             |
//| AllowsEmaSignal/AllowsRangeStrategy retournent false →           |
//| aucune nouvelle entrée. Retry au tick suivant (jamais perdu).    |
//|                                                                  |
//| BRANCHEMENT (Strategy.mqh, 7 points) :                           |
//|   #include + membre m_MarketRegime + Config() + End() +          |
//|   Update() dans Detection() AVANT l'exécution + veto             |
//|   AllowsRangeStrategy() sur les lignes TryRsi7/TryBb10 +         |
//|   veto AllowsEmaSignal() dans TryEma50 (après GetSignal).        |
//|                                                                  |
//| NOTE TF : H4 et EMA 50/100 sont codés en dur (spéc). Pour un     |
//| sweep backtest de ces valeurs, les transformer en inputs sera    |
//| une itération dédiée (protocole : 1 changement à la fois).       |
//|                                                                  |
//+------------------------------------------------------------------+

#include <Koenigin/Type.mqh>      // ENUM_TREND (eT_Bull / eT_Bear)
#include <Koenigin/Log.mqh>       // LOG.INFO / LOG.WARNING

enum ENUM_MARKET_REGIME
{
    eMR_Unknown = 0,
    eMR_Bull,
    eMR_Bear,
    eMR_Range
};

enum ENUM_REGIME_RANGE_STRATEGY
{
    eRRS_None = 0,
    eRRS_Rsi7,
    eRRS_Bb10
};

input group "Market regime filter (H4)"
input ENUM_REGIME_RANGE_STRATEGY K_Regime_RangeStrategy = eRRS_None;

//+------------------------------------------------------------------+
//| MarketRegimeToString                                              |
//| Helper de log (pattern maison EnumOprSlToString).                 |
//+------------------------------------------------------------------+
string MarketRegimeToString(const ENUM_MARKET_REGIME i_regime)
{
    switch (i_regime)
    {
        case eMR_Bull:   return("Bull (close > EMA50 > EMA100)");
        case eMR_Bear:   return("Bear (close < EMA50 < EMA100)");
        case eMR_Range:  return("Range (EMA50/EMA100 entrelacees)");
        default:         return("Inconnu (donnees H4 indisponibles)");
    }
}

//+------------------------------------------------------------------+
//| RangeStrategyToString                                             |
//| Helper de log pour l'annonce du Config.                           |
//+------------------------------------------------------------------+
string RangeStrategyToString(const ENUM_REGIME_RANGE_STRATEGY i_strategy)
{
    switch (i_strategy)
    {
        case eRRS_Rsi7:  return("RSI7 SOLO");
        case eRRS_Bb10:  return("BB10 SOLO");
        default:         return("AUCUNE (eRRS_None)");
    }
}

class CMarketRegime
{
private:
    int                  m_Ema50Handle;
    int                  m_Ema100Handle;
    datetime             m_LastH4BarTime;
    ENUM_MARKET_REGIME   m_Regime;
    bool                 m_LastUpdateFailed;   // anti-spam : le WARNING de panne ne sort qu'une fois

public:
    bool Config(void)
    {
        m_Ema50Handle   = INVALID_HANDLE;
        m_Ema100Handle  = INVALID_HANDLE;
        m_LastH4BarTime = 0;
        m_Regime        = eMR_Unknown;
        m_LastUpdateFailed = false;

        m_Ema50Handle = iMA(Symbol(), PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
        m_Ema100Handle = iMA(Symbol(), PERIOD_H4, 100, 0, MODE_EMA, PRICE_CLOSE);
        if (m_Ema50Handle == INVALID_HANDLE || m_Ema100Handle == INVALID_HANDLE)
        {
            End();
            return(false);
        }

        LOG.INFO("MarketRegime : filtre de regime H4 actif (EMA 50/100 H4, bougie clôturée shift 1) | "
                 "Stratégie en range = " + RangeStrategyToString(K_Regime_RangeStrategy), __FUNCTION__);
        return(true);
    }

    void End(void)
    {
        if (m_Ema50Handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_Ema50Handle);
            m_Ema50Handle = INVALID_HANDLE;
        }
        if (m_Ema100Handle != INVALID_HANDLE)
        {
            IndicatorRelease(m_Ema100Handle);
            m_Ema100Handle = INVALID_HANDLE;
        }
    }

    bool Update(void)
    {
        datetime l_H4BarTime = iTime(Symbol(), PERIOD_H4, 0);
        if (l_H4BarTime == 0)
        {
            if (!m_LastUpdateFailed)
            {
                LOG.WARNING("MarketRegime : iTime H4 indisponible — regime Inconnu, entrées bloquées (fail-closed)", __FUNCTION__);
                m_LastUpdateFailed = true;
            }
            m_Regime = eMR_Unknown;
            return(false);
        }
        if (l_H4BarTime == m_LastH4BarTime && m_Regime != eMR_Unknown)
        {
            return(true);
        }

        m_Regime = eMR_Unknown;

        double l_Close[];
        double l_Ema50[];
        double l_Ema100[];
        ArraySetAsSeries(l_Close, true);
        ArraySetAsSeries(l_Ema50, true);
        ArraySetAsSeries(l_Ema100, true);

        if (CopyClose(Symbol(), PERIOD_H4, 1, 1, l_Close) != 1 ||
            CopyBuffer(m_Ema50Handle, 0, 1, 1, l_Ema50) != 1 ||
            CopyBuffer(m_Ema100Handle, 0, 1, 1, l_Ema100) != 1)
        {
            // Fail-closed + retry au tick suivant. Le WARNING ne sort
            // qu'une fois par panne (anti-spam) — LOG.INFO à la récup.
            //----------------------------------------------------------------
            if (!m_LastUpdateFailed)
            {
                LOG.WARNING("MarketRegime : lecture close/EMA H4 impossible — regime Inconnu, entrées bloquées (fail-closed, retry au tick suivant)", __FUNCTION__);
                m_LastUpdateFailed = true;
            }
            return(false);
        }

        if (l_Close[0] > l_Ema50[0] && l_Ema50[0] > l_Ema100[0])
        {
            m_Regime = eMR_Bull;
        }
        else if (l_Close[0] < l_Ema50[0] && l_Ema50[0] < l_Ema100[0])
        {
            m_Regime = eMR_Bear;
        }
        else
        {
            m_Regime = eMR_Range;
        }

        m_LastH4BarTime = l_H4BarTime;

        // Journal : chaque CHANGEMENT de régime (diagnostic backtest —
        // permet de reconstituer a posteriori pourquoi un signal a été
        // vetoé). Silence si le régime H4 n'a pas changé.
        //----------------------------------------------------------------
        static ENUM_MARKET_REGIME s_LastLogged = eMR_Unknown;
        if (m_Regime != s_LastLogged)
        {
            LOG.INFO("MarketRegime : regime H4 = " + MarketRegimeToString(m_Regime) +
                     " (close H4 " + DoubleToString(l_Close[0], _Digits) +
                     " | EMA50 " + DoubleToString(l_Ema50[0], _Digits) +
                     " | EMA100 " + DoubleToString(l_Ema100[0], _Digits) + ")", __FUNCTION__);
            s_LastLogged = m_Regime;
        }

        if (m_LastUpdateFailed)
        {
            LOG.INFO("MarketRegime : lecture H4 rétablie — " + MarketRegimeToString(m_Regime), __FUNCTION__);
            m_LastUpdateFailed = false;
        }
        return(true);
    }

    ENUM_MARKET_REGIME GetRegime(void) const
    {
        return(m_Regime);
    }

    bool AllowsEmaSignal(const ENUM_TREND i_trend) const
    {
        return((m_Regime == eMR_Bull && i_trend == eT_Bull) ||
               (m_Regime == eMR_Bear && i_trend == eT_Bear));
    }

    bool AllowsRangeStrategy(const ENUM_REGIME_RANGE_STRATEGY i_strategy) const
    {
        return(m_Regime == eMR_Range &&
               K_Regime_RangeStrategy != eRRS_None &&
               K_Regime_RangeStrategy == i_strategy);
    }
};
