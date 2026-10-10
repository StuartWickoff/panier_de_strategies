//+-----------------------------------------------
//+---------------------------------------
//| Ensemble des fonctions publiques de l'objet 'CParameters'
//|                                                      
//|   (Le code est compatible MT4/MT5)
//|
//|
//|
//+------------------------------------------------
//+-------------------------------------------------


//+----------------------------------------------------------------+
//| Config                                                         |
//| Initialise les données internes de l'objet                     |
//| INPUT:                                                         |
//|  Répertoire du fichier de paramètres                           |
//| Période du contrôle du fichier de paramètres (en minutes)      |
//| OUTPUT:                                                        |
//|  TRUE si la config est correcte                                |
//+----------------------------------------------------------------+
bool CParameters::Config(const string i_folder, const uint i_interCheck = K_CParameters_MinPeriod)
{
   // Variables locales
   //------------------
   string   l_folder;
   
   // Initialisation
   //---
   m_Filename          = "";
   m_InterCheck        = 0 ;
   m_LastCheck         = 0 ;
   m_ModificationDate  = 0 ;
   this.RazParam();
   
   // Nettoie le nom du répertoire
   //-----------------------------
   l_folder = i_folder;
   CleanString(l_folder);
   
   // Vérification du nom
   //--------------------
   if (!FolderNameControl(l_folder, true))
   {
      m_Filename = "";
      LOG.ERROR("Nom de répertoire '" + l_folder + "' incorrect !!!", __FUNCTION__);
      return(false);
   }
   
   // Sauvegarde le nom du répertoire
   //--------------------------------
   else
   {
      m_Filename = l_folder + IntegerToString(I_Robot_ID) + "\\" + K_CParameters_FileName;
   }
   
   // Contrôle de la période minimum
   //-------------------------------
   if (i_interCheck < K_CParameters_MinPeriod)
   {
      m_InterCheck = K_CParameters_MinPeriod;
      LOG.WARNING("Période de vérification des paramètres fixée à " + IntegerToString(K_CParameters_MinPeriod) + " minute(s)", __FUNCTION__);
   }
   
   // Renseigne la période
   //---------------------
   else
   {
      m_InterCheck = i_interCheck;
   }
   
   // Fin de la configuration
   //------------------------
   return(true);
   
}

/*
ConfigOk
Retourne l'état de la config de l'objet
INPUT:
None
OUTPUT:
TRUE si configuration sans erreur
*/
bool CParameters::ConfigOk(void)
{
   return(m_Filename != "");
}

//+----------------------------------------------------------------+
//| GetFileName                                                    |
//| Extrait le nom complet du fichier de paramètre ou un message   |
//| d'erreur s'il est incorrect ou non renseigné                   |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  Le texte avec le nom du fichier ou un message                 |
//+----------------------------------------------------------------+
string CParameters::GetFileName(void)
{
   if (m_Filename == "")
   {
      return("Fichier de paramètre non initialisé !!!");
   }
   else
   {
      return("Fichier de paramètres : " + TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\"+ m_Filename);
   }
}

//+----------------------------------------------------------------+
//| CyclicFileAnalysis                                             |
//| Vérification de la date de dernière modification du fichier et |
//| lecture du fichier avec prise en compte de tous les paramètres |
//| INPUT:                                                         |
//|  None                                                          |
//| OUTPUT:                                                        |
//|  TRUE si les données ont été modifiées                         |
//+----------------------------------------------------------------+
bool CParameters::CyclicFileAnalysis(void)
{
   // Variable locale
   //----------------
   datetime l_DateModif;
      
   // Contrôle du fichier à interval régulier
   //----------------------------------------
   if ((TimeLocal() - m_LastCheck) >= m_InterCheck * PeriodSeconds(PERIOD_M1))
   {
      // Mémorise le moment du contrôle
      //-------------------------------
      m_LastCheck = TimeLocal();
      
      // Test le fichier de paramètres s'il existe
      //------------------------------------------
      if (FileIsExist(m_Filename, FILE_COMMON))
      {
         // Contrôle la date de la dernière modif du fichier de paramètres
         //---------------------------------------------------------------
         l_DateModif = (datetime)FileGetInteger(m_Filename, FILE_MODIFY_DATE, true);
         if (l_DateModif != m_ModificationDate)
         {
            m_ModificationDate = l_DateModif;
            this.ExtractData();
            return(true);
         }
      }
   }
   
   // Pas de nouvelles données
   //-------------------------
   return(false);
};

/*
GetNextNews
Retourne la date et l'heure UTC (GMT) de la prochaine NEWS
INPUT:
None
OUTPUT:
TRUE si une NEWS est définie
La date et l'heure UTC de la prochaine NEWS
*/
bool CParameters::GetNextNews(STRUCT_NEWS &i_news)
{
   // Variable locale
   //----------------
   int      l_Index;
   datetime l_ReadDate;
   datetime l_Date;
   
   // Initialise la recherche
   //------------------------
   l_Date = 0;
   
   // Cherche dans les dates existantes
   //----------------------------------
   for (l_Index =0; l_Index < ArraySize(m_News); l_Index++)
   {
      // Calcule la date la plus éloignée
      //---------------------------------
      l_ReadDate = m_News[l_Index].date + m_News[l_Index].security;

      // Cherche la prochaine date la plus proche de l'heure UTC actuelle
      //-----------------------------------------------------------------
      if ((l_ReadDate > TimeGMT()) && ((l_Date == 0) || (l_ReadDate < l_Date)))
      {
         l_Date = l_ReadDate;
         i_news = m_News[l_Index];
      }
   }
   
   // Retourne TRUE si une news a été trouvée
   //---
   return(l_Date != 0);
}

/*
GetHourStartTrading
Retourne l'heure de début de trading pour la journée d'après l'heure du marché
(Ceci concerne les détections)
INPUT:
None
OUTPUT:
TRUE si l'heure est définie
L'heure de début de trading
*/
bool CParameters::GetHourStartTrading(datetime &i_date)
{
   // Renseigne la date si elle est valide
   //---
   if (m_TradingStartDay.valid)
   {
      i_date = m_TradingStartDay.value;
   }
   
   // Retourne la validité
   //---
   return(m_TradingStartDay.valid);
}

/*
GetHourEndTrading
Retourne l'heure de fin de trading pour la journée d'après l'heure du marché
(Ceci concerne les détections)
INPUT:
None
OUTPUT:
TRUE si l'heure est définie
L'heure de fin de trading
*/
bool CParameters::GetHourEndTrading(datetime &i_date)
{
   // Renseigne la date si elle est valide
   //---
   if (m_TradingEndDay.valid)
   {
      i_date = m_TradingEndDay.value;
   }
   
   // Retourne la validité
   //---
   return(m_TradingEndDay.valid);
}

/*
GetHourCutPosition
Retourne l'heure de coupure des positions de la journée d'après l'heure du marché
INPUT:
None
OUTPUT:
TRUE si l'heure est définie
L'heure de coupure des positions ouvertes de la journée
*/
bool CParameters::GetHourCutPosition(datetime &i_date)
{
   // Renseigne la date si elle est valide
   //---
   if (m_EndPositionDay.valid)
   {
      i_date = m_EndPositionDay.value;
   }
   
   // Retourne la validité
   //---
   return(m_EndPositionDay.valid);
}

/*
GetDateHardCut
Retourne la date pour couper toutes les positions ouvertes d'après l'heure du marché
INPUT:
None
OUTPUT:
TRUE si l'heure est définie
L'heure de coupure de toutes les positions ouvertes
*/
bool CParameters::GetDateHardCut(datetime &i_date)
{
   // Variable locale
   //----------------
   int            l_Index;
   bool           l_DateOk;
   MqlDateTime    l_PTimeStruct;
   MqlDateTime    l_LTimeStruct;
   
   // Initialise la recherche
   //------------------------
   i_date = 0;
   if (!TimeToStruct(TimeCurrent(), l_LTimeStruct)) return(false);

   // Cherche dans les dates existantes
   //----------------------------------
   for (l_Index = 0; l_Index < ArraySize(m_PositionClosure); l_Index++)
   {
      if (!TimeToStruct(m_PositionClosure[l_Index], l_PTimeStruct)) continue;
      l_DateOk = ( (l_LTimeStruct.day  == l_PTimeStruct.day) &&
                   (l_LTimeStruct.mon  == l_PTimeStruct.mon) &&
                   (l_LTimeStruct.year == l_PTimeStruct.year) );
                   
      // Cherche la prochaine heure la plus proche
      //------------------------------------------
      if (l_DateOk && ((i_date == 0) || (m_PositionClosure[l_Index] < i_date)))
      {
         i_date = m_PositionClosure[l_Index];
      }
   }
   
   // Retourne TRUE si une date a été trouvée
   //----------------------------------------
   return(i_date != 0);    // date != 0 ???
}

/*
GetRiskLevel
Retourne le niveau de risque pour les nouveaux ordres
INPUT:
None
OUTPUT:
TRUE si le niveau est défini
Le niveau de risque pour chaque nouvel ordre
*/
bool CParameters::GetRiskLevel(double &i_risk)
{
   // Renseigne la date si elle est valide
   //---
   if (m_Risk.valid)
   {
      i_risk = m_Risk.value;
   }
   
   // Retourne la validité
   //---
   return(m_Risk.valid);
}

/*
GetMaxDayLoss
Retourne le niveau de perte max pour la journée
INPUT:
None
OUTPUT:
TRUE si le niveau est défini
Le niveau de perte maximum pour la journée
*/
bool CParameters::GetMaxDayLoss(double &i_dayMaxLoss)
{
   // Renseigne la date si elle est valide
   //---
   if (m_MaxDayLoss.valid)
   {
      i_dayMaxLoss = m_MaxDayLoss.value;
   }
   
   // Retourne la validité
   //---
   return(m_MaxDayLoss.valid);
}

/*
GetMaxWeekLoss
Retourne le niveau de perte max pour la journée
INPUT:
None
OUTPUT:
TRUE si le niveau est défini
Le niveau de perte maximum pour la journée
*/
bool CParameters::GetMaxWeekLoss(double &i_weekMaxLoss)
{
   // Renseigne la date si elle est valide
   //---
   if (m_MaxWeekLoss.valid)
   {
      i_weekMaxLoss = m_MaxWeekLoss.value;
   }
   
   // Retourne la validité
   //---
   return(m_MaxWeekLoss.valid);
}

/*
GetTrailingStop
Retourne la taille du trailing stop
INPUT:
None
OUTPUT:
TRUE si la taille est définie
La taille du trailing stop
*/
bool CParameters::GetTrailingStop(double &i_trailingStopSize)
{
   // Renseigne la date si elle est valide
   //---
   if (m_TrailingStop.valid)
   {
      i_trailingStopSize = m_TrailingStop.value;
   }
   
   // Retourne la validité
   //---
   return(m_TrailingStop.valid);
}


//|+-----------------------------------------------
/* 
GetVisuHeight
Retourne la taille d'affichage
INPUT:
None
OUTPUT:
TRUE si la taille est définie
La taille d'affichage
*/ 
//|+-----------------------------------------------
bool CParameters::GetVisuHeight(int &i_VisuHeight)
{
   // Renseigne la date si elle est valide
   //---
   if (m_VisuData.valid)
   {
      i_VisuHeight = m_VisuData.height;
   }
   
   // Retourne la validité
   //---
   return(m_VisuData.valid);
}

//|+-----------------------------------------------
/* 
HourOfTrading
Retourne si le créneau de trading est prévu
INPUT:
None
OUTPUT:
TRUE si le créneau de trading est prévu
*/ 
//|+-----------------------------------------------
bool CParameters::HourOfTrading(void)
{
   // Données locales
   //----------------
   datetime     l_HourStart;
   datetime     l_HourEnd;
   datetime     l_Time;
   MqlDateTime  l_PTimeStruct;
   MqlDateTime  l_LTimeStruct;

   // Lecture de la date actuelle
   //----------------------------
   if (!TimeToStruct(TimeCurrent(), l_LTimeStruct)) return(false);

   // Si pas d'heure de début, on fixe à 00:00
   //-----------------------------------------
   if (!this.GetHourStartTrading(l_Time))
   {
      l_LTimeStruct.hour = 0;
      l_LTimeStruct.min  = 0;
      l_LTimeStruct.sec  = 0;
   }

   // Si heure de début de stratégie existe, on l'enregistre
   //-------------------------------------------------------
   else
   {
      if (!TimeToStruct(l_Time, l_PTimeStruct)) return(false);
      l_LTimeStruct.hour = l_PTimeStruct.hour;
      l_LTimeStruct.min  = l_PTimeStruct.min;
      l_LTimeStruct.sec  = l_PTimeStruct.sec;
   }
   l_HourStart = StructToTime(l_LTimeStruct);

   // Si pas d'heure de fin, on contrôle directement
   //-----------------------------------------------
   if (!this.GetHourEndTrading(l_Time))
   {
      if (TimeCurrent() < l_HourStart) return(false);      
   }

   // Si heure de fin de stratégie existe, on l'enregistre
   //-----------------------------------------------------
   else
   {
      if (!TimeToStruct(l_Time, l_PTimeStruct)) return(false);
      l_LTimeStruct.hour = l_PTimeStruct.hour;
      l_LTimeStruct.min  = l_PTimeStruct.min;
      l_LTimeStruct.sec  = l_PTimeStruct.sec;
      l_HourEnd = StructToTime(l_LTimeStruct);
      
      // Contrôle le créneau horaire si début avant fin
      //-----------------------------------------------
      if (l_HourStart < l_HourEnd)
      {
         if ((TimeCurrent() < l_HourStart) || (TimeCurrent() >= l_HourEnd)) return(false);
      }

      // Contrôle le créneau horaire si début après fin
      //-----------------------------------------------
      else
      {
         if ((TimeCurrent() > l_HourEnd) && (TimeCurrent() < l_HourStart)) return(false);
      }
   }

   // Dans le créneau de trading
   //---------------------------
   return(true);
}
/*
DayOfTrading
Indique si le trading est autorisé pour la journée
INPUT:
None
OUTPUT:
TRUE si le trading est autorisé pour la journée
*/
bool CParameters::DayOfTrading(void)
{
   // Variables locales
   //------------------
   int          l_Index;
   MqlDateTime  l_StructureDateLocal;
   MqlDateTime  l_StructureDate;

   // Extraire les infos de la date locale
   //-------------------------------------
   if (!TimeToStruct(TimeCurrent(), l_StructureDateLocal)) return(false);

   // Recherche si une date pour interdir le trading
   //-----------------------------------------------
   for (l_Index = 0; l_Index < ArraySize(m_OffDay); l_Index++)
   {
      // Extraire les infos de la date
      //------------------------------
      if (!TimeToStruct(m_OffDay[l_Index], l_StructureDate)) return(false);

      // Si une date est cohérente, on interdit le trading
      //--------------------------------------------------
      if ((l_StructureDateLocal.year  == l_StructureDate.year) &&
          (l_StructureDateLocal.mon   == l_StructureDate.mon) &&
          (l_StructureDateLocal.day   == l_StructureDate.day))
      {
         return(false);
      }
   }

   // Trading autorisé
   //-----------------
   return(true);
}
/*
OutsideCutZone
Indique si on est dans les zones de coupure des positions
INPUT:
None
OUTPUT:
TRUE si on peut laisser les positions ouvertes
*/
bool CParameters::OutsideCutZone(void)
{
   // Variables locales
   //------------------
   datetime     l_Time;
   MqlDateTime  l_PTimeStruct;
   MqlDateTime  l_LTimeStruct;

   // Lecture de l'heure actuelle
   //----------------------------
   if (!TimeToStruct(TimeCurrent(), l_LTimeStruct)) return(false);

   // vérification si situation de coupure de positions journalières
   //---------------------------------------------------------------
   if (this.GetHourCutPosition(l_Time))
   {
      if (!TimeToStruct(l_Time, l_PTimeStruct)) return(false);
      l_LTimeStruct.hour = l_PTimeStruct.hour;
      l_LTimeStruct.min  = l_PTimeStruct.min;
      l_LTimeStruct.sec  = l_PTimeStruct.sec;
      l_Time = StructToTime(l_LTimeStruct);
      if (TimeCurrent() >= l_Time) return(false);
   }

   // vérification si situation de coupure totale des positions
   //----------------------------------------------------------
   if (this.GetDateHardCut(l_Time))
   {
      if (TimeCurrent() >= l_Time) return(false);
   }

   // Hors des zones de coupure obligatoire
   //--------------------------------------
   return(true);
}
/*
OutsideSecurityZone
Indique si on est hors des zones de sécurité pour une NEWS
INPUT:
None
OUTPUT:
TRUE si on peut trader
*/
bool CParameters::OutsideSecurityZone(void)
{
   // Données locales
   //----------------
   STRUCT_NEWS  l_News;

   // Lecture de la news la plus proche
   //----------------------------------
   if (this.GetNextNews(l_News))
   {
      // Contrôle la zone de sécurité
      //-----------------------------
      if (MathAbs(TimeGMT() - l_News.date) <= l_News.security) return(false);  
   }

   // Hors des zones de sécurité
   //---------------------------
   return(true);
}