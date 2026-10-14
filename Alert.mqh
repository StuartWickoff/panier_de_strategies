//+-----------------------------------------------------------------+
//| Gère l'envoi des alertes                                        |
//|                                                                 |
//| - Configure le type d'alerte (son, message, notification)       |
//| - Envoi une alerte en fonction des types d'alerte sélectionnées |
//|                                                                 |
//+---------------------------------------------------------------+
//|
//| TODO avec Grok : Liste des fonctions et leur rôle
//|
//+-----------------------------------------------------------------
//|                                                                 |
//| L'application doit définir :                                    |
//| - Les types d'alerte                                            |
//| - Le nom du logiciel                                            |
//|                                                                 |
//| Pour envoyer un message, c'est juste la fonction SEND           |
//|                                                                 |
//| Utilise l'objet LOG                                             |
//|                                                                 |
//+-----------------------------------------------------------------+
//|
//| Dépendances :
//|
//| - Fichier OPR_Bot.mqx : Contient la source compilable
//| - Fichier Tools.mqh         : Contient les fonctions de mise en forme
//| - Fichier Type.mqh          : Contient l'énuméré des niveaux
//| - Fichier Log.mqh           : Contient la gestion des logs
//|
//|


//////////////////////////////////////////////////////////
//                                                      //
//                  C L A S S                           //
//                                                      //
//////////////////////////////////////////////////////////
class CAlert
{

//================================
//---  PRIVATE
//================================
private:
   // Données
   //--------
   string   m_AppName;      // Nom de l'application
   string   m_Sound;        // Fichier son à utiliser
   bool     m_TextAlert;    // Alerte sous la forme d'un texte à l'écran
   bool     m_SoundAlert;   // Alerte avec un son particulier
   bool     m_NotifAlert;   // Alerte sous la forme d'une notification envoyée

//================================
//---  PUBLIC
//================================
public:             
   // Fonctions
   //----------
   void Config(const string i_appName,
                       const string i_soundFile);
                       
   void AlertType(const bool i_text,
                  const bool i_sound,
                  const bool i_notification);
                  
   bool SEND(const string i_text = "",
             const bool   i_WithLog = true);
};


//////////////////////////////////////////////////////////
//                                                      //
//              F U N C T I O N S                       //
//                                                      //
//////////////////////////////////////////////////////////

//+----------------------------------------------------------------+
//| Config                                                         |
//| Renseigne les infos de l'objet                                 |
//| INPUT:                                                         |
//|  Nom de l'application                                          |
//|  Nom du fichier son                                            |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CAlert::Config(const string i_appName, const string i_soundFile)
{
   // Enregistre les données
   //-----------------------
   m_AppName    = i_appName;
   m_Sound      = i_soundFile;
   m_TextAlert  = false;
   m_SoundAlert = false;
   m_NotifAlert = false;
   
   // Contrôle du nom du fichier son
   //---
   SoundNameControl(m_Sound, __FUNCTION__);
   
}


//+----------------------------------------------------------------+
//| AlertType                                                      |
//| Définition de types d'alerte à utiliser                        |
//| INPUT:                                                         |
//|  Alerte avec un texte                                          |
//|  Alerte avec un son                                            |
//|  Alerte avec une notification                                  |
//| OUTPUT:                                                        |
//|  None                                                          |
//+----------------------------------------------------------------+
void CAlert::AlertType(const bool i_text,
                       const bool i_sound,
                       const bool i_notification)
                        
{
   // Enregistre les données
   //-----------------------
   m_TextAlert   = i_text;
   m_SoundAlert  = i_sound;
   m_NotifAlert  = i_notification;
}

//+----------------------------------------------------------------+
//| SEND                                                           |
//| Envoi un message formaté                                       |
//| INPUT:                                                         |
//|  Texte de l'alerte                                             |
//|  Indication si on veut un log en cas d'erreur                  |
//| OUTPUT:                                                        |
//|  TRUE si traitement sans erreur                                |
//+----------------------------------------------------------------+
bool CAlert::SEND(const string i_text="",
                  const bool i_WithLog=true)
{
   // Variable locale
   //----------------
   string l_FormatedMesssage;
   bool   l_WithoutError;
   
   // Vérification de l'initialisation de l'objet
   //--------------------------------------------
   if (m_AppName == "")
   {
      if (i_WithLog) LOG.WARNING("Objet ALERTE pas initialisé !!!", __FUNCTION__);
      return(false);
   }
   
   // Prépare le contexte
   //--------------------
   l_FormatedMesssage = m_AppName + " - " + i_text;
   l_WithoutError     = true;
   
   // Affiche une alerte
   //-------------------
   if (m_TextAlert)
   {
      Alert(l_FormatedMesssage);
   }
   
   // Envoi une notification
   //-----------------------
   if (m_NotifAlert)
   {
      ResetLastError();
      if (!SendNotification(l_FormatedMesssage))
      {
         // Si envoi de log autorisé
         //-------------------------
         if (i_WithLog) LOG.WARNING_CODE(GetLastError(), __FUNCTION__);
         l_WithoutError = false;
      }
   }
   
   // Emission d'un son
   //------------------
   if (m_SoundAlert && (m_Sound != ""))
   {
      if (!PlaySound(m_Sound))
      {
         if (i_WithLog) LOG.WARNING("Erreur PlaySound avec '" + m_Sound + "' !!!", __FUNCTION__);
         l_WithoutError = false;
      }
   }
   
   // Retourne le résultat des opérations
   //------------------------------------
   return(l_WithoutError);
}                   