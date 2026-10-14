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

class CMarketRegime
{
private:
    int                  m_Ema50Handle;
    int                  m_Ema100Handle;
    datetime             m_LastH4BarTime;
    ENUM_MARKET_REGIME   m_Regime;

public:
    bool Config(void)
    {
        m_Ema50Handle   = INVALID_HANDLE;
        m_Ema100Handle  = INVALID_HANDLE;
        m_LastH4BarTime = 0;
        m_Regime        = eMR_Unknown;

        m_Ema50Handle = iMA(Symbol(), PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
        m_Ema100Handle = iMA(Symbol(), PERIOD_H4, 100, 0, MODE_EMA, PRICE_CLOSE);
        if (m_Ema50Handle == INVALID_HANDLE || m_Ema100Handle == INVALID_HANDLE)
        {
            End();
            return(false);
        }

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