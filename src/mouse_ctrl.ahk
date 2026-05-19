#Requires AutoHotkey v2.0
; test commit
; TODO: Zmiana wskaźnika głośności na dymek %
#SingleInstance Force
A_MaxHotkeysPerInterval := 200 ; Anti-spam scrolla
ProcessSetPriority "High"
DllCall("User32\ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", 0x0044, "UInt", 1, "Ptr", 0) ; Przepustka UIPI dla restartu (#SingleInstance)
#Include "..\TimeLog.ahk"

class _StoperStart {
    static __New() {
        QPC("START")
        global StartZakonczony := false ; TARCZA: Blokada skrótów sprzętowych na czas ładowania interpretera
    }
}

#Include "..\AHK2_external_code\UIA.ahk"
#Include "..\AHK2_Colorful_GUI\AHK2ColorfulGUI.ahk"
#Include "mouse_ctrl_lib.ahk"
#Include "..\AHK2_My_libs\MojeFunkcje.ahk"

QPC("Auto-Execute: Poczatek")
; #region --- SPRAWDZANIE UPRAWNIEŃ ---
; TODO: Fix skalowania (refaktor legendy do silnika)

global IniPath := A_ScriptDir . "\mouse_ctrl_settings.ini"

; Wczytaj config przed sprawdzeniem uprawnień
global Uprawnienia := Number(IniRead(IniPath, "Settings", "Uprawnienia", 1))
QPC("Odczyt parametru Uprawnienia z INI")

; Wymuszenie Admina (jeśli config pozwala)
if (!A_IsAdmin && Uprawnienia && !RegExMatch(DllCall("GetCommandLine", "str"), " /restart(?!\S)"))
    try Run('*RunAs "' . (A_IsCompiled ? A_ScriptFullPath . '" /restart' : A_AhkPath . '" /restart "' . A_ScriptFullPath . '"')), ExitApp()
QPC("Sprawdzenie UAC")
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- INICJALIZACJA I PLIK INI ---

if !FileExist(IniPath) { ; Init default INI
    IniWrite(0, IniPath, "Settings", "DefaultProfile")
    IniWrite(3, IniPath, "Settings", "BrightnessStepMouse")
    IniWrite(5, IniPath, "Settings", "BrightnessStepKbd")
    IniWrite(2, IniPath, "Settings", "VolStepMouse")
    IniWrite(true, IniPath, "Settings", "Uprawnienia")
    IniWrite(1, IniPath, "Settings", "PokazPodpowiedzi")
    IniWrite(0.15, IniPath, "Settings", "HoldThreshold") ; Domyślny DoubleClick (s)
    IniWrite(0, IniPath, "Settings", "LastGenesisActive")
    IniWrite(10, IniPath, "Settings", "LastBrightness")
    QPC("Utworzenie domyslnego pliku INI")
}

; Wczytywanie ustawień
class DaneGlobalne {
    static __New() {
        QPC("DaneGlobalne: Start")
        global DefaultProfile      := Number(IniRead(IniPath, "Settings", "DefaultProfile", 0))
        global BrightnessStepMouse := Number(IniRead(IniPath, "Settings", "BrightnessStepMouse", 3))
        global BrightnessStepKbd   := Number(IniRead(IniPath, "Settings", "BrightnessStepKbd", 5))
        global VolStepMouse        := Number(IniRead(IniPath, "Settings", "VolStepMouse", 2))
        global PokazPodpowiedzi    := Number(IniRead(IniPath, "Settings", "PokazPodpowiedzi", 1))
        global HoldThreshold       := Float(IniRead(IniPath, "Settings", "HoldThreshold", 0.15))
        global ListaProfili        := ["AUTO (Wykrywanie)", "Mysz Genesis + Klawiatura", "Mysz zwykła + Klawiatura", "Tylko Klawiatura", "Tryb OFF"]

        if FileExist(A_ScriptDir . "\mouse_ctrl.ico")
            TraySetIcon(A_ScriptDir . "\mouse_ctrl.ico")
        global AktywneOkna := []
        global CurrentProfile := DefaultProfile 
        global currentBrightness := Number(IniRead(IniPath, "Settings", "LastBrightness", 10))
        global LegendaGui := 0
        global GlUs := 0
        global AktywnyTip := 0
        global GuiControls := {} 
        global szerListy := 200
        global Szerokośćpopupow := 500 
        global SzerkokośćOknaLegendy := 200
        global TargetMouseID := "HID\VID_4E53&PID_5407" 
        global GenesisActive := Number(IniRead(IniPath, "Settings", "LastGenesisActive", 0))
        global DystansDoZamkniecia := 100 ; Dystans w px do zamknięcia popupu
        global MyszNadIkona := false
        global TipLive := 5000 ; Czas życia tooltipa (ms)
        global WasMutedAction := false
        global EkranWygaszony := false
        
        ; --- KONFIGURACJA MOTYWU (Centralne sterowanie z biblioteki) ---
        SilnikGUI.Konfiguruj("363533", 0.2, 0.4, 0.8, "bd4646", 0.1, 0.1) ; 363533, 0.2  - ramka
        SilnikGUI.TipDelayON := 0
        ; Kompatybilność wsteczna (Globalne)
        global KolorMotywu     := SilnikGUI.Motyw.Tlo
        global KolorRamki      := SilnikGUI.Motyw.Ramka
        global KolorNieaktywny := SilnikGUI.Motyw.Nieaktywny
        global KolorTekst      := SilnikGUI.Motyw.Tekst
        global KolorWarn       := SilnikGUI.Motyw.Ostrzezenie
        global KolorPrzycisku  := SilnikGUI.Motyw.Przycisk
        global ParametrFocus   := SilnikGUI.Motyw.ParamFocus
        OnExit(ZapiszStanSprzetowy)

        QPC("DaneGlobalne: Koniec __New")
    }
}

OnMessage(0x0200, ObslugaTooltipow)
OnMessage(0x211, DetectMenuEntry) ; WM_ENTERMENULOOP
DetectMenuEntry(wParam, lParam, msg, hwnd) => UsunTip()
QPC("Rejestracja OnMessage (Tooltip/Menu)")
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- KONFIGURACJA MENU TRAY ---
A_TrayMenu.Delete()
A_TrayMenu.Add("Pokaż skróty", PokazListeSkrotow)
A_TrayMenu.Default := "Pokaż skróty"
A_TrayMenu.ClickCount := 1
A_TrayMenu.Add()
A_TrayMenu.Add("Ustawienia", PokazUstawienia)
A_TrayMenu.Add()
for i, nazwa in ListaProfili
    A_TrayMenu.Add(nazwa, ((idx, *) => UstawProfil(idx)).Bind(i-1))
A_TrayMenu.Add() 
A_TrayMenu.Add("Odblokuj Klawisze (Ctrl+Alt+R)", (*) => AwaryjneOdblokowanie())
A_TrayMenu.Add("Wyjdź", (*) => ExitApp())

OnMessage(0x219, OnDeviceChange)

global SplashRozruch := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000")
SplashRozruch.BackColor := KolorMotywu
SplashRozruch.SetFont("s20 c" KolorNieaktywny, "Segoe UI") ;KolorTekst
SplashRozruch.Add("Text", "Center w" . Szerokośćpopupow . " y15", "MouseCtrl: Wczytywanie modułów...")
SplashRozruch.Add("Text", "Center w" . Szerokośćpopupow . " y+5", "Profil: " PobierzNazweProfilu())
SplashRozruch.Show("NA w" . Szerokośćpopupow . " y0")
QPC("Wyswietlenie natywnego ekranu rozruchowego")
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- STARTOWE POWIADOMIENIA I DETEKCJA ---
OnMessage(0x404, OnTrayMouseEvent) ; Obsługa najechania myszą na ikonę
global klawiszeZamykajace := ["~LButton", "~MButton", "~RButton Up", "~WheelUP", "~WheelDown", "~XButton1", "~XButton2"]

ZamknijWszystkie(*) {
    global AktywneOkna, ih
    (IsSet(ih) && ih is InputHook && ih.Stop())
    for okno in AktywneOkna
        try okno.Destroy()
    AktywneOkna := []
    
    for klawisz in klawiszeZamykajace
        Hotkey(klawisz, ZamknijWszystkie, "Off")
}

stworzPowiadomienieStartowe(tekst, kolor, yPoz) => AktywneOkna.Push(GenerujGuiPowiadomienia(tekst, kolor, yPoz))

global StartZakonczony := true ; TARCZA OFF: Skrypt poprawnie zweryfikował uprawnienia i narysował ekran rozruchowy
SetTimer(AsynchronicznaInicjalizacja, -1) ; Uruchom WMI w tle
QPC("KONIEC AUTO-EXECUTE (Przekazano do Async)")

AsynchronicznaInicjalizacja() {
    QPC("FAST INIT: Start")
    SilnikGUI.InicjalizujSilnik()
    QPC("FAST INIT: SilnikGUI.InicjalizujSilnik")
    
    global InicjalizacjaTrwa := false
    A_IconTip := "Mouse Control"
    
    global SplashRozruch
    if IsSet(SplashRozruch) && SplashRozruch
        SplashRozruch.Destroy()
        
    stworzPowiadomienieStartowe(PobierzNazweProfilu(), TipColor(), 0)
    stworzPowiadomienieStartowe(A_IsAdmin ? "PEŁNE UPRAWNIENIA" : "OGRANICZNONE  UPRAWNIENIA`nSkróty nie będą działać w oknach systemowych, takich jak`n Menedżer zadań.", A_IsAdmin ? "9FFB88" : "FA8072", 70)
    
    global ih := InputHook("L1 M", "{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}{BS}{ScrollLock}{Del}{Ins}{Home}{End}{PgUp}{PgDn}{Up}{Down}{Left}{Right}{CapsLock}{F1}{F2}{F3}{F4}{F5}{F6}{F7}{F8}{F9}{F10}{F11}{F12}") 
    ih.KeyOpt("{All}", "+N")
    ih.OnEnd := ZamknijWszystkie
    ih.Start()
    
    for klawisz in klawiszeZamykajace
        Hotkey(klawisz, ZamknijWszystkie, "On")
        
    QPC("FAST INIT: Koniec (Powiadomienia aktywne)")
    SetTimer(myDeferredInit, -3000)
}

/** Synchronizes INI cache with actual hardware state after fast boot */
myDeferredInit() {
    QPC("DEFERRED INIT: Start (WMI/COM in background)")
    AudioMonitor.Update()
    QPC("DEFERRED INIT: AudioMonitor.Update")
    
    global currentBrightness := PobierzAktualnaJasnosc()
    QPC("DEFERRED INIT: WMI Jasnosc")
    
    global CurrentProfile
    if (CurrentProfile == 0)
        SprawdzMysz()
    QPC("DEFERRED INIT: WMI Mysz & Koniec")
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- MODUŁ AUTOWYKRYWANIA MYSZY ---
OnDeviceChange(wParam, lParam, msg, hwnd) {
    SetTimer(SprawdzMysz, -1000)
    SetTimer(() => AudioMonitor.Update(), -500) ; Odśwież cache audio po zmianie sprzętu
}

SprawdzMysz() {
    global GenesisActive, TargetMouseID, CurrentProfile
    if (CurrentProfile != 0) 
    return

    staryStan := GenesisActive, GenesisActive := false
    try GenesisActive := ComObjGet("winmgmts:\\.\root\cimv2").ExecQuery("SELECT * FROM Win32_PnPEntity WHERE DeviceID LIKE '%" . StrReplace(TargetMouseID, "\", "\\") . "%' AND Status='OK'").Count > 0

    if (staryStan != GenesisActive) {
        if (!IsSet(InicjalizacjaTrwa) || !InicjalizacjaTrwa)
            PokazTip((GenesisActive ? "WYKRYTO" : "ODŁĄCZONO") . " Mysz : Genesis", GenesisActive ? "9FFB88" : "FA8072")
        LegendaIstnieje() && AktualizujListe()
    }
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- FUNKCJE SYSTEMOWE ---

ZapiszStanSprzetowy(ExitReason, ExitCode) {
    IniWrite(GenesisActive, IniPath, "Settings", "LastGenesisActive")
    IniWrite(currentBrightness, IniPath, "Settings", "LastBrightness")
}

TipColor() => ["9FFB88", "fbf988", "fbf988", "fbc088", "FA8072"][CurrentProfile + 1]

LegendaIstnieje() => (IsSet(LegendaGui) && IsObject(LegendaGui) && WinExist("ahk_id " LegendaGui.Hwnd))
UstawieniaIstnieje() {
    try {
        return (IsSet(GlUs) && IsObject(GlUs) && WinExist("ahk_id " GlUs.GuiObj.Hwnd))
    }
    return false
}

OnTrayMouseEvent(wParam, lParam, msg, hwnd) {
    if (lParam != 0x200) 
    return
    global AktywnyTip, MyszNadIkona
    
    if (MyszNadIkona) 
        return SetTimer(UsunTip, -TipLive)

    MyszNadIkona := true
    
    if !TipIstnieje()
        PokazTip(PobierzNazweProfilu(), TipColor())

    SetTimer(UsunTip, -TipLive)
}

; Pobiera dynamicznie wyliczoną nazwę aktywnego profilu.
PobierzNazweProfilu() => ["AUTO: " . (GenesisActive ? "Mysz Genesis" : "Mysz Standardowa"), "MANUAL: Mysz Genesis", "MANUAL: Mysz Standardowa", "Tylko Klawiatura", "Tryb OFF (Skróty wyłączone)"][CurrentProfile + 1]

UstawProfil(nr, pokazacTip := false) {
    global CurrentProfile := nr
    if (nr == 0)
        SprawdzMysz()

    A_IconTip := "Mouse Control"

    ; Tip tylko gdy Legenda ukryta
    if (pokazacTip && !(LegendaIstnieje() && DllCall("IsWindowVisible", "Ptr", LegendaGui.Hwnd))) {
        PokazTip(PobierzNazweProfilu(), TipColor())
    }

    LegendaIstnieje() && AktualizujListe()
}
; #endregion
; #region teśc popupów
TipText := {
AdminTip : (A_IsAdmin 
                    ? "POZIOM UPRAWNIEŃ:`nSkrypt MA DOSTĘP do okien systemowych.`nMożesz używać skrótów wszędzie." 
                    : "POZIOM UPRAWNIEŃ:`nSkrypt NIE MA DOSTĘPU do okien systemowych.`nSkróty nie będą tam działać.")
}
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- GENEROWANIE POPUPÓW ---

TipIstnieje() => (IsSet(AktywnyTip) && IsObject(AktywnyTip) && WinExist(AktywnyTip))

PokazTip(txt1, col1) { 
    global AktywnyTip, Szerokośćpopupow, KumulatywnyDystans, LastTrayX, LastTrayY, MyszNadIkona
    KumulatywnyDystans := 0 ; Reset licznika
    MouseGetPos(&LastTrayX, &LastTrayY) ; Start poz
    ; Blokada gdy Legenda widoczna
    if (LegendaIstnieje() && DllCall("IsWindowVisible", "Ptr", LegendaGui.Hwnd)) {
        MyszNadIkona := false ; Reset flagi (dla startu monitora)
        return
    }
    (AktywnyTip is Gui) && (AktywnyTip.Destroy(), AktywnyTip := 0)
    try (AktywnyTip := GenerujGuiPowiadomienia(txt1, col1, 0), SetTimer(MonitorujMysz, 100), SetTimer(UsunTip, -TipLive))
}
GenerujGuiPowiadomienia(tekst, kolor, yPoz) { ; Też dla powiadomień
    global Szerokośćpopupow
    g := Gui("+AlwaysOnTop -Caption +ToolWindow")
    g.BackColor := kolor
    g.SetFont("s20")
    g.Add("Text", "x0 W" . Szerokośćpopupow . " Center cBlack", tekst)
    g.Show("W" . Szerokośćpopupow . " Center NA y" . yPoz)
    return g
}
UsunTip() {
    global AktywnyTip
    (IsSet(AktywnyTip) && (AktywnyTip is Gui) && AktywnyTip.Destroy()), AktywnyTip := 0
}

MonitorujMysz() {
    global LastTrayX, LastTrayY, AktywnyTip, KumulatywnyDystans, MyszNadIkona
    global DystansDoZamkniecia
    
    ; Stop monitora, gdy brak okna
    if !TipIstnieje()
        return (SetTimer(MonitorujMysz, 0), MyszNadIkona := false)

    Step := SprawdzRuchMyszy(&LastTrayX, &LastTrayY, 0, true)
    
    ; 1. LOGIKA DYSTANSU (działa zawsze)
    if (Step > 0 && (KumulatywnyDystans += Step, KumulatywnyDystans >= DystansDoZamkniecia))
        return UsunTip()

    ; 2. Opuszczenie
    ; Ruch > 5px = wyjazd
    (MyszNadIkona && Step > 5) && MyszNadIkona := false && SetTimer(UsunTip, -TipLive/2) 
    
    (MyszNadIkona && Step == 0) && SetTimer(UsunTip, -TipLive/2) 
}


; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
;   #region --- OKNO USTAWIEŃ ---
PokazUstawienia(*) {
    global DefaultProfile, BrightnessStepMouse, BrightnessStepKbd, VolStepMouse, IniPath, GlUs, Uprawnienia
    global StartProf, Edit_BM, Edit_BK, Edit_VM, Edit_VD
    global StatusTextControl, Check_Autostart, Check_Podpowiedzi, UprawnieniaCheckbox,
    SzerOknUst := 220 
    pad := 10
    ;STATUS AUTOSTARU
    ShortcutPath := A_Startup . "\mouse_ctrl.lnk"
    TaskName := "MouseCtrlAutostart"
    TaskExists := !RunWait('schtasks /query /tn "' . TaskName . '"', , "Hide")
    ShortcutExists := FileExist(ShortcutPath) ? 1 : 0
    
    GlUs := SilnikGUI("USTAWIENIA", "", {unikalny: 1, pokazPasek: 1, PadD: pad, PadR: pad, PadL: pad})
    if (!GlUs.nowaInstancja)
        return GlUs.Pokaz()
    szerDD := 200
    AdminInfoCtrl := GlUs.Add("Text", "vadmininfoU +0x0100  y+10", (A_IsAdmin ? " ADMIN " : " REGULAR "))
    AdminInfoCtrl.SetFont("bold")    
    AdminInfoCtrl.GetPos(,,&Adw)
    AdminInfoCtrl.move(((SzerOknUst+pad)-Adw)/2)
    AdminInfoCtrl.HoverAction := (*) => SilnikGUI.CustomTooltip((TipText.AdminTip), {delayoff:500, delayon:500, trybPozycji:AdminInfoCtrl, Align:"up-5", Transparent: 0.1, TransClick: 1}) ;

    Tytul := GlUs.Add("Text", "Center x" . ((SzerOknUst+pad)-szerDD)/2 . " w" . szerDD, "Domyślny profil startowy:")
    Tytul.SetFont("norm")
    
    StartProf := GlUs.DodajDDList(ListaProfili, 0, DefaultProfile + 1, szerDD, "x" . ((SzerOknUst+pad)-szerDD)/2 . " y+10")

    Edit_BM := GlUs.DodajWierszKonfiguracji("Jasność (Mysz):", BrightnessStepMouse, {trybWalidacji: 0, minVal: 1, maxVal: 100, skok: 1, pozycja: "x20 y+25", SzerText: 140})
    Edit_BK := GlUs.DodajWierszKonfiguracji("Jasność (Klawiatura):", BrightnessStepKbd, {trybWalidacji: 0, minVal: 1, maxVal: 100, skok: 1, pozycja: "x20 y+10", SzerText: 140})
    Edit_VM := GlUs.DodajWierszKonfiguracji("Głośność (Mysz):", VolStepMouse, {trybWalidacji: 0, minVal: 1, maxVal: 100, skok: 1, pozycja: "x20 y+10", SzerText: 140})
    Edit_VD := GlUs.DodajWierszKonfiguracji("Podwójny klik (s):", Format("{:.2f}", HoldThreshold), {trybWalidacji: 1, minVal: 0.05, maxVal: 1.0, skok: 0.05, pozycja: "x20 y+10", SzerText: 140})
    GlUs.Ramka(Edit_BM, Edit_VD, 8)

    StatusOpis := TaskExists ? "Status: Harmonogram (Admin)" : (ShortcutExists ? "Status: Folder Autostart (Regular)" : "Status: Wyłączony")
    IsAutostartActive := TaskExists || ShortcutExists

    Check_Autostart := GlUs.DodajCheckbox("Uruchamiaj ze startem systemu", {czyZaznaczony: IsAutostartActive, pozycja: "xm  y+15"})
    Check_Autostart.OnEvent("Click", WeryfikujKlikniecieAutostartu)
    ; Czcionka statusu
    StatusTextControl := GlUs.Add("Text", "x" . Check_Autostart.LabelX . " y+2", StatusOpis)
    StatusTextControl.KolorBazowy := "Gray" ; [FIX] Customowy kolor z obsługą przyciemniania
    ; Reset czcionki
    GlUs.GuiObj.SetFont("s10 " . SilnikGUI.Motyw.Tekst)
    
    UprawnieniaCheckbox := GlUs.DodajCheckbox("pytaj o uprawnienia `nadministratora przy starcie", {czyZaznaczony: Uprawnienia, pozycja: "xm y+10"})

    Check_Podpowiedzi := GlUs.DodajCheckbox("Wyświetlaj podpowiedzi", {czyZaznaczony: PokazPodpowiedzi, pozycja: "y+10"})

    GlUs.DodajPrzycisk("Zastosuj", (*) => ZapiszIUstaw(GlUs.GuiObj, StartProf, Edit_BM, Edit_BK, Edit_VM, Edit_VD, Check_Podpowiedzi, false), "y+20 w80 h30")
    GlUs.DodajPrzycisk("Zapisz", (*) => ZapiszIUstaw(GlUs.GuiObj, StartProf, Edit_BM, Edit_BK, Edit_VM, Edit_VD, Check_Podpowiedzi, true), "x" . (SzerOknUst-80) . " yp w80 h30")
    GlUs.Pokaz()
    WinActivate("ahk_id " GlUs.GuiObj.Hwnd)
    Edit_BM.Focus()
}
WeryfikujKlikniecieAutostartu(ctrl, *) {
    TaskName := "MouseCtrlAutostart"
    ; czy istnieje zadanie Admina
    TaskExists := !RunWait('schtasks /query /tn "' . TaskName . '"', , "Hide")
    
    ; Blokada zmiany adania bez uprawnień
    if (TaskExists && !A_IsAdmin) {
        ctrl.Value := !ctrl.Value ; Cofnij zmianę wizualną (odbij haczyk)
        SilnikGUI.OknoBledu("⚠️ ODMOWA DOSTĘPU", "Nie można zmienić ustawień autostartu administratora bez odpowiednich uprawnień.", "Uruchom program jako Administrator.", GlUs.GuiObj.Hwnd)
    }
}
ZastosujZmianyAutostartu() {
    global StatusTextControl, Check_Autostart, GlUs
    
    czyWlaczone := Check_Autostart.Value
    ManageAutostart(czyWlaczone)
    
    ; 2. Weryfikacja stanu (0/1)
    TaskName := "MouseCtrlAutostart"
    ShortcutPath := A_Startup . "\mouse_ctrl.lnk"
    
    ; Check zadania (0=sukces)
    TaskExists := (RunWait('schtasks /query /tn "' . TaskName . '"', , "Hide") = 0)
    ShortcutExists := FileExist(ShortcutPath) ? 1 : 0
    
    StanFaktyczny := (TaskExists || ShortcutExists) ? 1 : 0
    
    ; 3. Cofnij zmianę przy braku uprawnień
    if (czyWlaczone != StanFaktyczny) {
        Check_Autostart.Value := StanFaktyczny 
        SilnikGUI.OknoBledu("⚠️ ODMOWA DOSTĘPU", "Nie można zmienić ustawień autostartu administratora bez odpowiednich uprawnień.", "Uruchom program jako Administrator.", GlUs.GuiObj.Hwnd)
    }

    ; 4. Aktualizacja terści
    NowyStatus := TaskExists ? "Status: Harmonogram (Admin)" : (ShortcutExists ? "Status: Folder Autostart (Regular)" : "Status: Wyłączony")
    StatusTextControl.Value := NowyStatus
}
ZapiszIUstaw(G, D, BM, BK, VM, VD, CP, ZamknijOkno := true) {
    global DefaultProfile, BrightnessStepMouse, BrightnessStepKbd, VolStepMouse, HoldThreshold, PokazPodpowiedzi, IniPath, Uprawnienia, UprawnieniaCheckbox, Check_Autostart
    
    ; 1. Pobranie wartości (SilnikGUI gwarantuje typ i zakres)
    DefaultProfile      := D.SelectedIndex - 1 
    BrightnessStepMouse := Number(BM.Value)
    BrightnessStepKbd   := Number(BK.Value)
    VolStepMouse        := Number(VM.Value)
    HoldThreshold       := Number(StrReplace(VD.Value, ",", ".")) ; Safety check dla float
    PokazPodpowiedzi    := CP.Value
    Uprawnienia         := UprawnieniaCheckbox.Value

    ; 2. Zapis INI
    IniWrite(DefaultProfile, IniPath, "Settings", "DefaultProfile") 
    IniWrite(Uprawnienia, IniPath, "Settings", "Uprawnienia")
    IniWrite(PokazPodpowiedzi, IniPath, "Settings", "PokazPodpowiedzi")
    IniWrite(BrightnessStepMouse, IniPath, "Settings", "BrightnessStepMouse") 
    IniWrite(BrightnessStepKbd, IniPath, "Settings", "BrightnessStepKbd") 
    IniWrite(VolStepMouse, IniPath, "Settings", "VolStepMouse")
    IniWrite(HoldThreshold, IniPath, "Settings", "HoldThreshold") 
   
    ZastosujZmianyAutostartu()

    if (ZamknijOkno)
        WinClose("ahk_id " G.Hwnd)
    PokazTip(ZamknijOkno ? "Ustawienia Zapisane!" : "Zastosowano ustawienia", "9FFB88")
}

ManageAutostart(enable) { 
    TaskName := "MouseCtrlAutostart"
    ShortcutPath := A_Startup . "\mouse_ctrl.lnk"
    
    ; Sprawdź harmonogram
    TaskExists := !RunWait('schtasks /query /tn "' . TaskName . '"', , "Hide")

    if (enable) {
        if A_IsAdmin {
            ; Admin: COM (szybki)
            try {
                Service := ComObject("Schedule.Service")
                Service.Connect()
                RootFolder := Service.GetFolder("\")

                ; Nowe zadanie
                TaskDef := Service.NewTask(0)
                TaskDef.RegistrationInfo.Description := "Uruchamia Mouse Control z uprawnieniami administratora"
                TaskDef.RegistrationInfo.Author := "MouseCtrl"
                
                ; Konfiguracja: Admin, Priorytet, Bateria
                TaskDef.Principal.RunLevel := 1 ; (admin=1/normal=0)
                TaskDef.Settings.Priority := 3  ; 4 = Normal
                TaskDef.Settings.DisallowStartIfOnBatteries := false
                TaskDef.Settings.StopIfGoingOnBatteries := false
                TaskDef.Settings.ExecutionTimeLimit := "PT0S" ; Brak limitu czasu

                ; Wyzwalacz: Logowanie
                Triggers := TaskDef.Triggers
                Trigger := Triggers.Create(9) ; 9 = TASK_TRIGGER_LOGON
                Trigger.Enabled := true

                ; Akcja: Skrypt
                Actions := TaskDef.Actions
                Action := Actions.Create(0) ; 0 = TASK_ACTION_EXEC
                Action.Path := A_AhkPath
                Action.Arguments := '"' . A_ScriptFullPath . '"'
                Action.WorkingDirectory := A_ScriptDir ; Ustawienie katalogu roboczego

                ; Zapis (Aktualizacja)
                RootFolder.RegisterTaskDefinition(TaskName, TaskDef, 6, "", "", 3)
            } catch as err {
                MsgBox("Nie udało się utworzyć harmonogramu: " . err.Message, "Błąd", "Icon!")
            }

            if FileExist(ShortcutPath)
                FileDelete(ShortcutPath)
        } else {
            ; Zwykły: Skrót (jeśli brak zadania)
            if !TaskExists {
                try FileCreateShortcut(A_IsCompiled ? A_ScriptFullPath : A_AhkPath, ShortcutPath, A_ScriptDir, A_IsCompiled ? "" : '"' . A_ScriptFullPath . '"')
            }
        }
    } else {
        ; Wyłącz: Usuń oba
        RunWait('schtasks /delete /tn "' . TaskName . '" /f', , "Hide")
        if FileExist(ShortcutPath)
            FileDelete(ShortcutPath)
    }
}

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- OKNO LEGENDY ---

; ============================================================================================================================================================
; SEKCJA 1: TWORZENIE I AKTUALIZACJA GUI
; ============================================================================================================================================================

PokazListeSkrotow(*) {
    global LegendaGui, CurrentProfile, GuiControls, GruboscRamki
    global SzerkokośćOknaLegendy, GenesisActive
    global WymiaryLegendy 

    ; 1. Odśwież istniejące
    if LegendaIstnieje() {
        AktualizujListe()
        AktualizujTooltipWLocie()
        return
    }

    ; 2. Wstepnie Oblicz szerokość
    dane_startowe := TrescLegendy(CurrentProfile, GenesisActive)
    WymiaryLegendy := ObliczSzerokoscLegendy(dane_startowe)
    SzerkokośćOknaLegendy := WymiaryLegendy.Total
    
    ; 3. Inicjalizacja GUI
    LegendaGui := Gui("+AlwaysOnTop +Border -Caption", "LEGENDA")
    kolorTla := KolorMotywu
    LegendaGui.BackColor := kolorTla
    GruboscRamki := 2
    GuiControls.RamkaTla := SilnikGUI.RysujObrys(LegendaGui, 0, 0, 0, 0, KolorRamki, GruboscRamki)
    
    ; 4. Kontrolki (Pozycjonowanie w AktualizujListe)
    
    ; --- Nagłówek i Profil ---
    LegendaGui.SetFont("s15 bold " . KolorTekst, "Segoe UI")
    GuiControls.UprawnieniaText := LegendaGui.Add("Text", "vUprawnieniaText +0x0100 Center x0 w" . SzerkokośćOknaLegendy, (A_IsAdmin ? "ADMIN" : "REGULAR"))
    
    LegendaGui.SetFont("s10 norm")
    GuiControls.DDL := LegendaGui.Add("DropDownList", "x0 w" . szerListy . " Background" . KolorMotywu . " " . KolorTekst . " Choose" . (CurrentProfile + 1), ListaProfili)
    GuiControls.DDL.OnEvent("Change", (ctrl, *) => UstawProfil(ctrl.Value - 1, false)) 
    
    ; --- Nagłówki Sekcji ---
    LegendaGui.SetFont("s15 bold")
    GuiControls.Header     := LegendaGui.Add("Text", "vAutoTryb +0x0100 Center x0 " . KolorTekst, "")
    GuiControls.KlawHeader := LegendaGui.Add("Text", "vNaglowekKlawiatury +0x0100 Center x0 " . KolorTekst, "")
    GuiControls.MyszHeader := LegendaGui.Add("Text", "Center x0 " . KolorTekst, "")
    
    ; --- Treść (Kolumny) ---
    LegendaGui.SetFont("s13 w100")
    ; Sekcja Klawiatury
    GuiControls.KlawTextL      := LegendaGui.Add("Text", "vListaLKlawiatury +0x0100 Right x0 " . KolorTekst, "")
    GuiControls.KlawTextR      := LegendaGui.Add("Text", "vListaRKlawiatury +0x0100 Left x+0 " . KolorTekst, "")
    GuiControls.KlawTextCenter := LegendaGui.Add("Text", "Center x0 c" . KolorNieaktywny . " Hidden", "")
    ; Mysz
    GuiControls.MyszTextL      := LegendaGui.Add("Text", "Right x0 " . KolorTekst, "")
    GuiControls.MyszTextR      := LegendaGui.Add("Text", "Left x+0 " . KolorTekst, "")
    GuiControls.MyszTextCenter := LegendaGui.Add("Text", "Center x0 c" . KolorNieaktywny . " Hidden", "")
    
    ; Stopka
    LegendaGui.SetFont("s13 bold")
    GuiControls.BtnSettings := LegendaGui.Add("Text", "w140 h30 Center Background" . KolorPrzycisku . " " . KolorTekst . " +Border +0x0200", "Ustawienia (F1)")
    GuiControls.BtnSettings.OnEvent("Click", (*) => (LegendaGui.Hide(), PokazUstawienia()))
    
    LegendaGui.SetFont("s9", "Segoe UI")
    GuiControls.Exit := LegendaGui.Add("Text", "Center x0 c" . KolorNieaktywny, "(Kliknij na to okno, aby zamknąć)")
    
    AktualizujListe()
    UsunTip()
}

AktualizujListe() { 
    global CurrentProfile, GuiControls, GenesisActive, SzerkokośćOknaLegendy, LegendaGui, WymiaryLegendy, GruboscRamki
    
    try GuiControls.DDL.Choose(CurrentProfile + 1)
    
    ; 1. Dane i wymiary
    dane := TrescLegendy(CurrentProfile, GenesisActive)
    WymiaryLegendy := ObliczSzerokoscLegendy(dane)
    SzerkokośćOknaLegendy := WymiaryLegendy.Total
    
    start_x_klaw := (SzerkokośćOknaLegendy - (WymiaryLegendy.KL + WymiaryLegendy.KR)) / 2
    start_x_mysz := (SzerkokośćOknaLegendy - (WymiaryLegendy.ML + WymiaryLegendy.MR)) / 2
    
    ; 2. Układ
    
    ; A. Góra
    GuiControls.UprawnieniaText.Move((SzerkokośćOknaLegendy - WymiaryLegendy.wUpr) / 2, 10, WymiaryLegendy.wUpr)
    GuiControls.UprawnieniaText.Redraw()
    GuiControls.UprawnieniaText.GetPos(,,,&hUpr)
    
    y_curr := 10 + hUpr + 10
    GuiControls.DDL.Move((SzerkokośćOknaLegendy-szerListy)/2, y_curr)
    GuiControls.DDL.Redraw()
    GuiControls.DDL.GetPos(,,,&hDDL)
    y_curr += hDDL + 10

    ; B. Sekcje
    y_curr := OdswiezNaglowek(y_curr, GuiControls.Header, dane.Header, WymiaryLegendy.wMainHead)
    y_curr := OdswiezSekcje(y_curr, GuiControls.KlawHeader, GuiControls.KlawTextL, GuiControls.KlawTextR, GuiControls.KlawTextCenter, dane.KlawHeader, dane.KlawText, dane.KlawKolor, WymiaryLegendy.KL, WymiaryLegendy.KR, WymiaryLegendy.KS, WymiaryLegendy.hK, start_x_klaw, WymiaryLegendy.wHeadK)
    y_curr := OdswiezSekcje(y_curr, GuiControls.MyszHeader, GuiControls.MyszTextL, GuiControls.MyszTextR, GuiControls.MyszTextCenter, dane.MyszHeader, dane.MyszText, dane.MyszKolor, WymiaryLegendy.ML, WymiaryLegendy.MR, WymiaryLegendy.MS, WymiaryLegendy.hM, start_x_mysz, WymiaryLegendy.wHeadM)
    
    ; C. Dół (Przyciski)
    GuiControls.BtnSettings.Move((SzerkokośćOknaLegendy-140)/2, y_curr)
    GuiControls.BtnSettings.Redraw()
    
    y_exit := y_curr + 30 + 10
    GuiControls.Exit.Move((SzerkokośćOknaLegendy - WymiaryLegendy.wExit) / 2, y_exit, WymiaryLegendy.wExit)
    GuiControls.Exit.Redraw()
    GuiControls.Exit.GetPos(,,, &hExit) ; Pobieramy wysokość ostatniego elementu

    ; 3. Finalizacja
    wysokosc_okna := y_exit + hExit + 10
    GuiControls.RamkaTla.Move(0, 0, SzerkokośćOknaLegendy, wysokosc_okna)
    UsunTip()
    LegendaGui.Show("w" . SzerkokośćOknaLegendy . " h" . wysokosc_okna . " Center NA")
}

; ============================================================================================================================================================
; SEKCJA 2: FUNKCJE POMOCNICZE (LAYOUT I FORMATOWANIE)
; ============================================================================================================================================================

AktualizujSekcje(tekst, ctrlL, ctrlR, ctrlC, kolor) {
    if (tekst = "Skróty nieaktywne") {
        ctrlL.Visible := false, ctrlR.Visible := false
        ctrlC.Visible := true, ctrlC.Value := tekst
        if (kolor != "")
            ctrlC.SetFont(kolor)
    } else {
        ctrlL.Visible := true, ctrlR.Visible := true
        ctrlC.Visible := false
        RozdzielNaKolumny(tekst, ctrlL, ctrlR, kolor)
    }
}

RozdzielNaKolumny(tekst, ctrlL, ctrlR, kolor, separator := "=") {
    txtL := "", txtR := ""
    Loop Parse, tekst, "`n", "`r" {
        if (separator != "" && InStr(A_LoopField, separator)) {
            czesc := StrSplit(A_LoopField, separator, , 2)
            txtL .= czesc[1] . "`n"
            txtR .= separator . czesc[2] . "`n"
        } else {
            txtL .= A_LoopField . "`n"
            txtR .= "`n"
        }
    }
    ctrlL.Value := txtL
    ctrlR.Value := txtR
    if (kolor != "") {
        ctrlL.SetFont(kolor)
        ctrlR.SetFont(kolor)
    }
}

OdswiezNaglowek(yStart, cHead, txtHead, szerokosc) {
    global SzerkokośćOknaLegendy
    cHead.Value := txtHead
    cHead.GetPos(,,,&hHead)
    
    if (txtHead == "") {
        hHead := 0
        marginHead := 0
        cHead.Visible := false
        startX := 0
    } else {
        if (hHead < 10) hHead := 25
        marginHead := 10
        cHead.Visible := true
        startX := (SzerkokośćOknaLegendy - szerokosc) / 2
    }
    cHead.Move(startX, yStart, szerokosc, hHead)
    cHead.Redraw()
    return yStart + hHead + marginHead
}

OdswiezSekcje(yStart, cHead, cL, cR, cC, txtHead, txtContent, kolor, wL, wR, wSingle, hContent, startX, szerokoscNaglowka) {
    global SzerkokośćOknaLegendy
    
    ; 1. Treść i styl
    cHead.Value := txtHead
    cHead.SetFont(kolor)
    AktualizujSekcje(txtContent, cL, cR, cC, kolor)
    
    ; 2. Pozycjonowanie nagłówka
    yPoNaglowku := OdswiezNaglowek(yStart, cHead, txtHead, szerokoscNaglowka)
    
    ; 3. Pozycjonowanie Treści
    hRealContent := (txtContent == "") ? 0 : hContent
    marginContent := (txtContent == "") ? 0 : 10
    
    cL.Move(startX, yPoNaglowku, wL, hRealContent)
    cR.Move(startX + wL, yPoNaglowku, wR, hRealContent)
    
    if (txtContent == "Skróty nieaktywne") {
        cC.Move((SzerkokośćOknaLegendy - wSingle) / 2, yPoNaglowku, wSingle, hRealContent)
    } else {
        cC.Move(0, yPoNaglowku, SzerkokośćOknaLegendy, hRealContent)
    }
    
    cL.Redraw(), cR.Redraw(), cC.Redraw()
    return yPoNaglowku + hRealContent + marginContent
}

; ============================================================================================================================================================
; SEKCJA 3: DANE I OBLICZENIA
; ============================================================================================================================================================

TrescLegendy(profil, genesisState) {
    dane := {Header: "", KlawHeader: "", KlawText: "", MyszHeader: "", MyszText: "", KlawKolor: KolorTekst, MyszKolor: KolorTekst}
    
    ; Definicje tekstów
    txtKlawiatura := "Ctrl+Alt+R = Odblokuj klawisze`nCtrl+Alt+P = PrintScreen`nCtrl+F1/F2 = Jasność`nCtrl+F12 = Zmień profil`nShift + `` = ~"
    txtGenesis    := "Prawy = Shift`nPrawy + Wheel = Głośność`nPrawy + Środkowy = Wycisz`nX1+Wheel = Jasność`nX1 + Prawy = Wygaszenie`nX1(2x) = Esc`nX1(2xHold) + Wheel  🡱 🡳 = 🡰 🡲`nX2(Hold) = Ctrl`nX2(2x) = Zapisz`nX2(2xHold) + Wheel  🡱 🡳 = Wheel  🡰 🡲`nX2 + X1 + Wheel  🡱 🡳 = Cofnij / Ponów`nAlt + Wheel  🡱 🡳 =    - | | -`nX2 + Lewy = Ctrl+V`nX2 + Lewy(Hold) = Lewy+Ctrl+V`nX2 + Prawy = Ctrl+C`nX2 + Prawy(Hold) = Ctrl+X`nX2 + Prawy(2x) = Lewy+Ctrl+C`nX2 + Prawy(2xHold) = Lewy+Ctrl+X"
    txtStandard   := "Prawy = Shift`nPrawy + Wheel = Głośność`nPrawy + Środkowy = Wycisz`nPrawy + Lewy = Alt+Tab`nLewy + Wheel = Jasność`nLewy + Środkowy = Wygaszenie`nMButton + Wheel  🡱 🡳 = Wheel  🡰 🡲"

    ; Wartości domyślne
    dane.Header     := (profil == 0) ? "AUTO" : ((profil == 4) ? "" : "MANUAL")
    dane.KlawHeader := (profil == 4) ? "WSZYSTKO WYŁĄCZONE" : "— KLAWIATURA —"
    dane.KlawText   := (profil == 4) ? "Skróty nieaktywne" : txtKlawiatura
    dane.KlawKolor  := (profil == 4) ? "c" . KolorWarn : KolorTekst
    dane.MyszHeader := [(genesisState ? "—  MYSZ GENESIS —" : "— MYSZ STANDARD —"), "—  MYSZ GENESIS —", "— MYSZ STANDARD —", "--- MYSZ ---", ""][profil + 1]
    dane.MyszText   := [(genesisState ? txtGenesis : txtStandard), txtGenesis, txtStandard, "Skróty nieaktywne", ""][profil + 1]
    dane.MyszKolor  := (profil == 3) ? "c" . KolorNieaktywny : KolorTekst
    return dane
}

ObliczSzerokoscLegendy(dane) {
    dummyGui := Gui()
    dummyGui.SetFont("s13 w100", "Segoe UI") ; Czcionka standard

    ; Lokalna funkcja pomiarowa dla legendy (bez zaleznosci od usuniętego MojeFunkcje)
    ZmierzWymiarySekcji(tekst, separator := "") {
        maxLeft := 0, maxRight := 0, maxSingle := 0
        Loop Parse, tekst, "`n", "`r" {
            if (A_LoopField == "")
                continue
            if (separator != "" && InStr(A_LoopField, separator)) {
                parts := StrSplit(A_LoopField, separator, , 2)
                dummyGui.Add("Text",, parts[1]).GetPos(,, &wL)
                dummyGui.Add("Text",, separator . parts[2]).GetPos(,, &wR)
                maxLeft := Max(maxLeft, wL), maxRight := Max(maxRight, wR)
            } else {
                dummyGui.Add("Text",, A_LoopField).GetPos(,, &wS)
                maxSingle := Max(maxSingle, wS)
            }
        }
        return {L: maxLeft, R: maxRight, Single: maxSingle}
    }

    ; Mierzymy sekcję Klawiatury
    wymiaryK := ZmierzWymiarySekcji(dane.KlawText, "=")
    ; Mierzymy sekcję Myszy
    wymiaryM := ZmierzWymiarySekcji(dane.MyszText, "=")
    
    ; Pomocnik pomiaru
    MierzElement(txt, &w:=0, &h:=0) => dummyGui.Add("Text",, txt).GetPos(,, &w, &h)

    MierzElement(dane.KlawText,, &hK)
    MierzElement(dane.MyszText,, &hM)
    
    ; Czcionka nagłówków (S15 Bold)
    dummyGui.SetFont("s15 bold", "Segoe UI")
    
    MierzElement(dane.KlawHeader, &wHeadK)
    MierzElement(dane.MyszHeader, &wHeadM)
    MierzElement(dane.Header, &wMainHead)
    MierzElement((A_IsAdmin ? "ADMIN" : "REGULAR"), &wUpr)

    ; Pomiar stopki (S9)
    dummyGui.SetFont("s9", "Segoe UI")
    MierzElement("(Kliknij na to okno, aby zamknąć)", &wExit)
    
    dummyGui.Destroy()
    
    ; Szerokość całkowita okna
    szerokoscK := wymiaryK.L + wymiaryK.R
    szerokoscM := wymiaryM.L + wymiaryM.R
    maxContent := Max(szerokoscK, szerokoscM, wymiaryK.Single, wymiaryM.Single)
    maxHeader := Max(wHeadK, wHeadM, wMainHead, wUpr)
    
    ; Marginesy (+40px czyli 20 na stronę)
    totalW := Max(maxContent, maxHeader, szerListy) + 40
        
    return {Total: totalW, KL: wymiaryK.L, KR: wymiaryK.R, ML: wymiaryM.L, MR: wymiaryM.R, KS: wymiaryK.Single, MS: wymiaryM.Single, hK: hK, hM: hM, wHeadK: wHeadK, wHeadM: wHeadM, wMainHead: wMainHead, wUpr: wUpr, wExit: wExit}
}

; ============================================================================================================================================================
; SEKCJA 4: OBSŁUGA TOOLTIPÓW (DLA ELEMENTÓW LEGENDY)
; ============================================================================================================================================================

ObslugaTooltipow(wParam, lParam, msg, hwnd) {
    global LegendaGui, CurrentProfile, GlUs
    static OstatniCtrl := 0, OstatniaTresc := ""

    ; Walidacja HWND
    if !IsInteger(hwnd)
        return

    currCtrl := GuiCtrlFromHwnd(hwnd)
    if !currCtrl
        return
        
    ; Detekcja okna (Legenda lub Ustawienia)
    isLegenda := (IsSet(LegendaGui) && IsObject(LegendaGui) && currCtrl.Gui == LegendaGui)
    isUstawienia := (IsSet(GlUs) && IsObject(GlUs) && GlUs.GuiObj && currCtrl.Gui == GlUs.GuiObj)

    Tresc := ""
    if (isLegenda || isUstawienia) {
        switch currCtrl.Name {
            case "UprawnieniaText", "admininfoU":
                Tresc := TipText.AdminTip
            ;case "AutoTryb":
            ;    Tresc := (CurrentProfile == 4 ? "" : (CurrentProfile == 0 ? "Wykrywanie myszy" : "Brak wykrywania myszy"))
            ;case "NaglowekKlawiatury":
            ;    Tresc := TrescLegendy(CurrentProfile, GenesisActive).KlawHeader
            ;case "ListaLKlawiatury", "ListaRKlawiatury":
            ;    Tresc := TrescLegendy(CurrentProfile, GenesisActive).KlawText
        }
        
    }

    if (currCtrl == OstatniCtrl && Tresc == OstatniaTresc)
        return

    OstatniCtrl := currCtrl
    OstatniaTresc := Tresc

    if (Tresc != "")
        SilnikGUI.CustomTooltip(Tresc, {trybPozycji: currCtrl, Align:"+Down+10"})
} 

; Odświeżanie tipa pod myszą
AktualizujTooltipWLocie() => LegendaIstnieje() && (MouseGetPos(,,, &hCtrl, 2), ObslugaTooltipow(0, 0, 0, hCtrl))

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- OBSŁUGA ZMIANY JASNOŚCI ---

PobierzAktualnaJasnosc() {
    try {
        for monitor in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT CurrentBrightness FROM WmiMonitorBrightness")
            return monitor.CurrentBrightness
    }
    return 10 ; Domyślnie
}

ZmianaJasnosci(delta) {
    global currentBrightness
    currentBrightness := Min(Max(currentBrightness + delta, 10), 100)
    try {
        for method in ComObjGet("winmgmts:\\.\root\WMI").ExecQuery("SELECT * FROM WmiMonitorBrightnessMethods")
            method.WmiSetBrightness(0, currentBrightness)
    }
    SilnikGUI.CustomTooltip("Jasność: " . currentBrightness . "%  ◑", {czas: 1500})
}

ZmianaGlosnosci(delta) {
    SoundSetVolume((delta > 0 ? "+" : "-") . Abs(delta))
    SilnikGUI.CustomTooltip(PobierzStatusAudio(), {czas: 1500})
}

PrzelaczWyciszenie() {
    global WasMutedAction := true
    SoundSetMute(-1)
    SilnikGUI.CustomTooltip(PobierzStatusAudio(), {czas: 1500})
}

WygasEkran(klawisz := "LButton") {
    global EkranWygaszony
    static BlackScreenGui := 0
    static ZegarCtrl := 0
    static OdswiezZegar := () => (ZegarCtrl ? ZegarCtrl.Value := FormatTime(,"dd.MM.yyyy") "`n" FormatTime(,"HH:mm:ss") : "")
    static WymusZgaszenie := () => ((BlackScreenGui && WinExist(BlackScreenGui.Hwnd)) ? SendMessage(0x112, 0xF170, 2,, "Program Manager") : WygasEkran())
    static hPowerNotify := 0
    static mX := 0, mY := 0
    static ResetNaRuch := () => (SprawdzRuchMyszy(&mX, &mY, 3, true) ? SetTimer(WymusZgaszenie, -3000) : 0)
    static ObslugaWybudzenia := (wParam, lParam, msg, hwnd) => ((wParam == 0x8013) ? ((NumGet(lParam, 20, "UInt") == 1) ? (SetTimer(WymusZgaszenie, -3000), MouseGetPos(&mX, &mY), SetTimer(ResetNaRuch, 100)) : SetTimer(ResetNaRuch, 0)) : 0)

    if (BlackScreenGui) {
        if (hPowerNotify) {
            DllCall("User32\UnregisterPowerSettingNotification", "Ptr", hPowerNotify)
            hPowerNotify := 0
        }
        OnMessage(0x0218, ObslugaWybudzenia, 0) ; Wyrejestruj nasłuch
        SetTimer(WymusZgaszenie, 0)
        SetTimer(ResetNaRuch, 0) ; Stop Watchdoga
        SetTimer(OdswiezZegar, 0) ; Stop zegara
        try BlackScreenGui.Destroy()
        BlackScreenGui := 0
        ZegarCtrl := 0
        EkranWygaszony := false
        SendMessage(0x112, 0xF170, -1,, "Program Manager") ; Wymusza wybudzenie
        return
    }

    SilnikGUI.CustomTooltip("PUŚĆ PRZYCISKI")
    KeyWait(klawisz)
    KeyWait("MButton") ; Dodatkowa blokada, aby przypadkowe puszczenie przycisku nie wybudziło ekranu
    SilnikGUI.CustomTooltip()

    EkranWygaszony := true

    BlackScreenGui := Gui("+AlwaysOnTop -Caption -SysMenu +ToolWindow -DPIScale")
    BlackScreenGui.BackColor := "Black"
    BlackScreenGui.OnEvent("Close", (*) => WygasEkran()) ; Obsługa Alt+F4
        
        BlackScreenGui.SetFont("s25 c3a3a3a")
        ZegarCtrl := BlackScreenGui.Add("Text", "x0 y50 w" A_ScreenWidth " Center Hidden", FormatTime(,"dd.MM.yyyy") "`n" FormatTime(,"HH:mm:ss"))
        
        kombinacjaKlawiszy := (klawisz = "XButton1") ? "X1 + PRAWY" : "LEWY + ŚRODKOWY"
        BlackScreenGui.SetFont("s35 bold")
        tekstInfo := BlackScreenGui.Add("Text", "x0 y" (A_ScreenHeight // 2 - 100) " w" A_ScreenWidth " Center Hidden", "NACIŚNIJ PONOWNIE`n`n" kombinacjaKlawiszy "`n`nABY ODBLOKOWAĆ")
        
        SetTimer(() => (ZegarCtrl ? tekstInfo.Visible := ZegarCtrl.Visible := true : 0), -1000) ; Safe-check
        SetTimer(OdswiezZegar, 1000)

    BlackScreenGui.Show(" NA") ; Pokrywa wszystkie monitory
    BlackScreenGui.Maximize()
    WinActivate(BlackScreenGui.Hwnd) ; Zapewnia, że ekran blokady jest na wierzchu

    ; Rejestracja natywnego event-driven detekcji ekranu (GUID_SESSION_DISPLAY_STATUS)
    GUID_DISPLAY := Buffer(16)
    NumPut("UInt", 0x2B84C20E, "UShort", 0xAD23, "UShort", 0x4DDF, "UChar", 0x93, "UChar", 0xDB, "UChar", 0x05, "UChar", 0xFF, "UChar", 0xBD, "UChar", 0x7E, "UChar", 0xFC, "UChar", 0xA5, GUID_DISPLAY)
    hPowerNotify := DllCall("User32\RegisterPowerSettingNotification", "Ptr", BlackScreenGui.Hwnd, "Ptr", GUID_DISPLAY, "UInt", 0, "Ptr")
    OnMessage(0x0218, ObslugaWybudzenia, 1) ; Start nasłuchu

    WymusZgaszenie()
}

PobierzStatusAudio() {
    return AudioMonitor.Cache . Round(SoundGetVolume()) . "%" . (SoundGetMute() ? "  🔉X" : "  🔊 ")
}
; #region --- HOTKEYE DLA OKNA LEGENDY ---

#HotIf StartZakonczony && LegendaIstnieje() 
WheelDown::{
    if (CurrentProfile != 4)
        UstawProfil((CurrentProfile+1), true)      
        AktualizujTooltipWLocie() 
}
WheelUp::{
    if (CurrentProfile != 0)
        UstawProfil((CurrentProfile-1), true)
        AktualizujTooltipWLocie() ; Odśwież tooltip
}
~LButton::
{
    LButtonStandardTip()
    
    if !LegendaIstnieje()
        return
    
    ; Ignoruj gdy lista rozwinięta
    try {
        if SendMessage(0x0157, 0, 0, , "ahk_id " . GuiControls.DDL.Hwnd) ; CB_GETDROPPEDSTATE
            return
    }

    MouseGetPos(,, &idPodMysza, &hCtrl, 2)
    
    try klasaOkna := WinGetClass("ahk_id " idPodMysza)
    catch 
        klasaOkna := ""

    if (klasaOkna == "ComboLBox")
        return

    if (idPodMysza == LegendaGui.Hwnd) {
        if (hCtrl == GuiControls.DDL.Hwnd || hCtrl == GuiControls.BtnSettings.Hwnd)
            return
        LegendaGui.Hide()
    } else {
        LegendaGui.Hide()
    }
}
~Esc::
~MButton::
~RButton:: {
    LegendaGui.Hide()
}
#HotIf

#HotIf StartZakonczony && LegendaIstnieje() && WinGetMinMax("ahk_id " LegendaGui.hwnd) != -1
F1:: (LegendaGui.Hide(), PokazUstawienia())
; #endregion

;----------------------------------------------------------------------------------------------------------------------------------------------
; #region --- GŁÓWNE SKRÓTY PRZEŁĄCZANIA ---
; #region Skróty Dla Myszy Genesis

#HotIf StartZakonczony && (CurrentProfile = 1 or (CurrentProfile = 0 and GenesisActive))
   
    *RButton:: AkcjaRButton()
    
    XButton1:: {
        Multiklik("XButton1", 
            (*) => Wyslij("{XButton1}"),
            (*) => (!PokazPodpowiedzi ? (SilnikGUI.CustomTooltip("Jasność: " . currentBrightness . "%  ◑", {ON: !EkranWygaszony, czas: 1500})) : (SilnikGUI.CustomTooltip("SCROLL  ➠  ZMIANA JASNOŚCI  ◑`n..`nŚRODKOWY  ➠  WYGASZENIE  💻`n.[2].`n(x2)  ➠  ESC  🡰`n..`n(2xHOLD)+SCROLL  🡱 🡳  ➠  STRZAŁKI  🡰 🡲`n.[2].`nJasność: " . currentBrightness . "%  ◑", {ON: !EkranWygaszony, MargPoz: 4})), MouseCtrlLib.AktywujTrybKola((*) => ZmianaJasnosci(BrightnessStepMouse), (*) => ZmianaJasnosci(-BrightnessStepMouse),(*) => Hotkey("*RButton", (*) => (UsunTip(), WygasEkran("XButton1")), "On"), (*) => Hotkey("*RButton", (*) => AkcjaRButton(), "On"), 0, "XButton1"), SilnikGUI.CustomTooltip("")),
            (*) => Wyslij("{Escape}", true),
            (*) => (SilnikGUI.CustomTooltip("SCROLL  🡱 🡳   ➠  STRZAŁKI  🡰 🡲", {ON: (!EkranWygaszony && PokazPodpowiedzi)}), UstawFocusPodMysz(), MouseCtrlLib.AktywujTrybKola((*) => Wyslij("{Left}", true), (*) => Wyslij("{Right}", true), 0, 0, () => SilnikGUI.CustomTooltip(""), "XButton1"), SilnikGUI.CustomTooltip("")),
            HoldThreshold ; Czas przytrzymania
        )
    }

    ~RButton & XButton1:: AltTab
    ~RButton & XButton2:: ShiftAltTab

    XButton2:: {
        Multiklik("XButton2",
            (*) => Wyslij("{XButton2}"),
                (*) => (SilnikGUI.CustomTooltip("CTRL  ✲`n..`nSCROLL  🡱 🡳  ➠  ZOOM   ( + ) 🔍 ( - )`n.[4].`n- L E W Y -`n.[3].`n(x2) ➠  CTRL+V  📄`n..`n(2xHOLD)  ➠  CTRL+V+LEWY  📄🡳`n.[4].`n- P R A W Y -`n.[3].`n(x1)  ➠  CTRL+C  📄📄`n..`n(HOLD)  ➠  CTRL+X  ✂`n..`n(x2)  ➠  CTRL+C+LEWY   📄📄🡳`n..`n(2xHOLD)  ➠  CTRL+X+LEWY  ✂🡳`n.[4].`nX1+SCROLL  🡱 🡳  ➠  CTRL+Z/Y  🡷 🡵`n.[3].`n(x2)  ➠  CTRL+SHIFT+S  ✍`n..`n(2xHOLD)+SCROLL  🡱 🡳  ➠  SCROLL  🞀 ❘❙❚❙❘ 🞂", {ON: (!EkranWygaszony && PokazPodpowiedzi), MargPoz: 2}), MouseCtrlLib.AktywujTrybKola((*) => Wyslij("{WheelUp}"), (*) => Wyslij("{WheelDown}"), (*) => Wyslij("{Ctrl Down}"), (*) => Wyslij("{Ctrl Up}"), () => SilnikGUI.CustomTooltip(""), "XButton2"), SilnikGUI.CustomTooltip("")),
            (*) => Wyslij("^a", true),
                (*) => (SilnikGUI.CustomTooltip("SCROLL  🡱 🡳  ➠  SCROLL  🞀 ❘❙❚❙❘ 🞂", {ON: (!EkranWygaszony && PokazPodpowiedzi)}), MouseCtrlLib.AktywujTrybKola((*) => (SendLevel(1), Wyslij("{WheelLeft}", true)), (*) => (SendLevel(1), Wyslij("{WheelRight}", true)), 0, 0, () => SilnikGUI.CustomTooltip(""), "XButton2"), SilnikGUI.CustomTooltip("")),
            HoldThreshold
        )
    }

   ~XButton2 & LButton:: {
        Multiklik("LButton",
        (*) => (SilnikGUI.CustomTooltip(""), Click("Left")),
        (*) => (SilnikGUI.CustomTooltip(""), Wyslij("{Blind}{LButton Down}"), KeyWait("LButton"), Wyslij("{Blind}{LButton Up}")),
        (*) => (SilnikGUI.CustomTooltip(""), Wyslij("^v")),
        (*) => (SilnikGUI.CustomTooltip(""), (Click("Left"), Wyslij("^v"))),
        HoldThreshold)
    }
 
    ~XButton2 & RButton:: {
        Multiklik("RButton", 
        (*) => (SilnikGUI.CustomTooltip(""), Wyslij("^c")), 
        (*) => (SilnikGUI.CustomTooltip(""), Wyslij("^x")), 
        (*) => (SilnikGUI.CustomTooltip(""), (Wyslij("{Ctrl Up}"), Click("Left"), Wyslij("^c"))), 
        (*) => (SilnikGUI.CustomTooltip(""), (Wyslij("{Ctrl Up}"), Click("Left"), Wyslij("^x"))), 
        HoldThreshold)
    }
    
   XButton2 & XButton1:: {
        SilnikGUI.CustomTooltip("SCROLL  🡱 🡳  ➠  CTRL+Z/Y  🡷 🡵", {ON: (!EkranWygaszony && PokazPodpowiedzi)})
        MouseCtrlLib.AktywujTrybKola((*) => Wyslij("^z"), (*) => Wyslij("^y"), 0, 0, () => SilnikGUI.CustomTooltip(""), "xbutton2")
     }
          
#HotIf

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region Skróty Dla Myszy Standardowej
#HotIf StartZakonczony && (CurrentProfile = 2 or (CurrentProfile = 0 and !GenesisActive))
    RButton:: AkcjaRButton()
#HotIf StartZakonczony && (CurrentProfile = 2 or (CurrentProfile = 0 and !GenesisActive))  && !CzyNadZablokowanymElementem()
    ~LButton & WheelUp:: (UsunTip(), ZmianaJasnosci(BrightnessStepMouse))
    ~LButton & WheelDown:: (UsunTip(), ZmianaJasnosci(-BrightnessStepMouse))
    ~LButton & MButton::  (UsunTip(), WygasEkran("LButton"))
    ~LButton & RButton:: AltTab
    ~LButton Up::Wyslij("{Alt Up}") ; Wymuszone zwolnienie Alt po AltTab
    ~LButton:: LButtonStandardTip()
#HotIf
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region Funkcje Pomocnicze - główne skróty
LButtonStandardTip(czasUspienia := HoldThreshold*1000) {
    if !(CurrentProfile = 2 or (CurrentProfile = 0 and !GenesisActive))
        return

    (!PokazPodpowiedzi) ? (SilnikGUI.CustomTooltip("Jasność: " . currentBrightness . "%  ◑", {DelayON: czasUspienia, ON: !EkranWygaszony, czas: 1500})) : SilnikGUI.CustomTooltip("SCROLL  ➠  ZMIANA JASNOŚCI  ◑`n.[1].`nŚRODKOWY  ➠  WYGASZENIE  💻`n.[1].`nPRAWY  ➠  ALT+TAB`n.[2].`nJasność: " . currentBrightness . "%  ◑", {DelayON : czasUspienia, ON: !EkranWygaszony})
    KeyWait("LButton")
    SilnikGUI.CustomTooltip()
}

CzyNadZablokowanymElementem() {
    MouseGetPos(,,, &hCtrl, 2)
    ; Sprawdź globalne tagi WinAPI (działają między procesami)
    return (hCtrl && (Utils.GetTag(hCtrl, "IsSilnikScrollbarBtn") || Utils.GetTag(hCtrl, "IsSilnikScrollbarThumb") || Utils.GetTag(hCtrl, "IsSilnikScrollbarTrack")))
}

; Ukrywa ramki fokusu (WM_UPDATEUISTATE) po symulacji klawiatury
Wyslij(Klawisze, Event := false) {
    Event ? SendEvent(Klawisze) : Send(Klawisze)
    try PostMessage(0x0128, 0x00010001, 0,, "A")
}

; Funkcja pomocnicza dla AkcjaRButton, wywoływana przy przytrzymaniu
_AkcjaRButton_Hold() {
    PokazDymek := () => !PokazPodpowiedzi ? (SilnikGUI.CustomTooltip(PobierzStatusAudio(), {ON: !EkranWygaszony, czas: 1500})) : SilnikGUI.CustomTooltip("SHIFT  🡱`n..`n" . ((CurrentProfile = 1 or (CurrentProfile = 0 and GenesisActive))? "X1  ➠  Alt+Tab`nX2  ➠  Shift+Alt+Tab`n..`n" : "LEWY  ➠  Alt+Tab`n..`n") . "SCROLL  🡱 🡳  ➠  VOLUME(+/-)`nŚRODKOWY  ➠  WYCISZ  🔉X`n.[2].`n" . PobierzStatusAudio(), {ON: !EkranWygaszony}) 
    CzyscDymek := (*) => SilnikGUI.CustomTooltip()

    ; Timer dymka
    SetTimer(PokazDymek, -Round(HoldThreshold * 1000))

    ; LButton czyści dymek
    try Hotkey("~*LButton", CzyscDymek, "On")
    try Hotkey("*MButton", (*) => PrzelaczWyciszenie(), "On")

    MouseCtrlLib.AktywujTrybKola(
        (*) => (SetTimer(PokazDymek, 0), ZmianaGlosnosci(VolStepMouse)), 
        (*) => (SetTimer(PokazDymek, 0), ZmianaGlosnosci(-VolStepMouse)), 
        (*) => Wyslij("{LShift Down}"), 
        (*) => Wyslij("{LShift Up}"),
        (*) => "", 
        "RButton"
    )

    ; Sprzątanie
    try Hotkey("~*LButton", "Off")
    try Hotkey("*MButton", "Off")
    SetTimer(PokazDymek, 0)
    CzyscDymek()
}

AkcjaRButton() {
    Multiklik("RButton", 
        (*) => (SendInput("{RButton Down}"), Sleep(1), SendInput("{RButton Up}")),
        _AkcjaRButton_Hold,
        "", "", HoldThreshold, 5
    )
}

; Focus pod myszą (dla XButton1)
UstawFocusPodMysz() {
    try UIA.ElementFromPoint().SetFocus()
}

; Awaryjny zrzut zablokowanych klawiszy logicznych
AwaryjneOdblokowanie() {
    klawisze := ["LButton", "RButton", "MButton", "XButton1", "XButton2", "LCtrl", "RCtrl", "LAlt", "RAlt", "LShift", "RShift"]
    sekwencja := ""
    for k in klawisze
        if GetKeyState(k)
            sekwencja .= "{" k " Up}"
    if (sekwencja != "")
        Send("{Blind}" sekwencja)
    SilnikGUI.CustomTooltip("ODBLOKOWANO`nKLAWISZE", {Transparent: 0.2, trybPozycji:"Screen",Align:"UP+20",czas: 2000,rozmiarCzcionki: 25})
}

; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------
; #region Skróty Dla Klawiatury 
#HotIf StartZakonczony && CurrentProfile != 4
    ^!p::(SilnikGUI.CustomTooltip("Zrzut ekranu 📸", {Transparent: 0.2,trybPozycji:"Screen",Align:"Up+20",rozmiarCzcionki: 25,DelayON:50,czas: 1500}), Wyslij("{PrintScreen}")) ; Ctrl+Alt+P
    ^F1::ZmianaJasnosci(-BrightnessStepKbd) ; Ctrl+F1
    ^F2::ZmianaJasnosci(BrightnessStepKbd) ; Ctrl+F2
    +`::SendText "~" ; Shift + `
#HotIf
#HotIf StartZakonczony
    ^!r::AwaryjneOdblokowanie()
    ^f12:: {
        if CurrentProfile < 3 {
            UstawProfil(CurrentProfile+1, true)   
            AktualizujTooltipWLocie() ; Odśwież tooltip
        } else if (CurrentProfile = 3) {
            UstawProfil(0, true)
            AktualizujTooltipWLocie() ; Wymusza odświeżenie tooltipa po zmianie danych
        }
    }


#HotIf
;#endregion
;#endregion 
;----------------------------------------------------------------------------------------------------------------------------------------------
;#region skróty KILL-TIP

    #HotIf StartZakonczony && TipIstnieje() && !LegendaIstnieje() && !GetKeyState("XButton2", "P")
    ~LButton:: {
        (sleep(100), UsunTip())
        LButtonStandardTip(HoldThreshold*1000-100)
    }
    ~MButton:: (sleep(100), UsunTip())
    ~RButton:: (sleep(100), UsunTip())
    ~Esc:: UsunTip()
    #HotIf   
; #endregion
;----------------------------------------------------------------------------------------------------------------------------------------------

; #region --- OBSŁUGA OKNA USTAWIEŃ (SILNIK GUI) ---
; skróty tylko w oknie ustawień

#HotIf StartZakonczony && UstawieniaIstnieje() && WinGetMinMax("ahk_id " GlUs.GuiObj.Hwnd) != -1 && WinActive("ahk_id " GlUs.GuiObj.Hwnd)

    ; Nawigacja (Tab) PPM+Rolka
    RButton & WheelDown::Send("{shift up}{Tab}")
    RButton & WheelUp::Send("+{Tab}")

#HotIf
; #endregion

; #region --- KLASA AUDIO MONITOR (COM) ---
class AudioMonitor {
    static Cache := "🔊?   "
    
    ; Odświeża cache ikon (wywoływane rzadko: start/zmiana sprzętu)
    static Update() {
        try {
            ; CLSID_MMDeviceEnumerator
            enumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
            ; GetDefaultAudioEndpoint(eRender=0, eConsole=1, &ppDevice)
            ComCall(4, enumerator, "Int", 0, "Int", 1, "Ptr*", &device := 0)
            if !device
                return
            
            ; OpenPropertyStore(STGM_READ=0, &ppStore)
            ComCall(4, device, "Int", 0, "Ptr*", &storePtr := 0)
            ObjRelease(device)
            if !storePtr
                return
            
            store := ComValue(13, storePtr) ; Wrap
            
            ; PKEY_AudioEndpoint_FormFactor (VT_UI4 = 19)
            formFactor := this.GetProp(store, "{1DA5D803-D492-4EDD-8C23-E0C0FFEE7F0E}", 0)
            
            ; PKEY_Device_EnumeratorName {A45C254E...}, 24 (Kluczowe dla typu magistrali)
            devEnum := this.GetProp(store, "{A45C254E-DF1C-4EFD-8020-67D146A850E0}", 24)
            
            ; PKEY_Device_InstanceId (VT_LPWSTR = 31)
            devId := this.GetProp(store, "{78C34FC8-E0AF-4E42-AAEC-27220C63243C}", 256)
            
            ; Agregacja danych do analizy (Enum + ID + Nazwa)
            fullInfo := devEnum . " " . devId . " " . SoundGetName()
            
            ; 1. Typ połączenia
            iconConn := "💻" ; Domyślnie Internal
            if (fullInfo ~= "i)(USB|UAC)")
                iconConn := "ψ"
            else if (fullInfo ~= "i)(Blue|BT|BTH)")
                iconConn := "ᛒ"
            else if (fullInfo ~= "i)(HDAUDIO|PCI|Realtek|High Def)")
                iconConn := (formFactor == 3 || formFactor == 5) ? "Jack ⊙" : "💻" ; Jack vs Internal
            
            ; 2. Typ urządzenia (FormFactor)
            iconForm := (formFactor == 3) ? "🎧" : ((formFactor == 5) ? "📞" : "🔊")
            
            ; 3. Budowanie stringa
            this.Cache := iconConn . ((iconConn == "💻" || iconConn == "⊙") ? "" : " " . iconForm) . "   "
            
        } catch 
            this.Cache := "🔊?   "
    }

    static GetProp(store, guid, pid) {
        pk := Buffer(20, 0)
        DllCall("Ole32\CLSIDFromString", "Str", guid, "Ptr", pk)
        NumPut("UInt", pid, pk, 16)
        
        val := Buffer(24, 0)
        try ComCall(5, store, "Ptr", pk, "Ptr", val) ; IPropertyStore::GetValue
        catch 
            return ""
            
        vt := NumGet(val, 0, "UShort")
        res := ""
        if (vt == 19) ; VT_UI4
            res := NumGet(val, 8, "UInt")
        else if (vt == 31) ; VT_LPWSTR
            res := StrGet(NumGet(val, 8, "Ptr"))
        
        DllCall("Ole32\PropVariantClear", "Ptr", val) ; Ważne czyszczenie
        return res
    }
}
; #endregion
