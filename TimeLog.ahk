#Requires AutoHotkey v2.0

/**
 * BLUEPRINT: Diagnostyka QPC (QueryPerformanceCounter)
 * 
 * Mechanizm do precyzyjnego mierzenia czasu wykonywania poszczególnych bloków kodu,
 * omijający standardowe (i mocno niedokładne) A_TickCount na rzecz sprzętowego stopera.
 * Zwraca wyniki w ułamkach milisekund.
 *
 * INSTRUKCJA UŻYCIA:
 * 1. Skopiuj funkcję QPC() do diagnozowanego pliku (na sam dół).
 * 2. Na początku mierzonego procesu wywołaj: QPC("START")
 *    (To wyzeruje stoper i utworzy nowy blok w logu).
 * 3. Po każdej operacji, którą chcesz zmierzyć, wywołaj: QPC("Nazwa Twojego Kroku").
 * 4. Uruchom skrypt - plik QPC_Log_[data_czas].txt wygeneruje się w A_ScriptDir.
 *
 * ⚠️ UWAGI DIAGNOSTYCZNE (Heisenbug I/O):
 * Operacja FileAppend odwołuje się do dysku. Pierwsze użycie pliku (lub utworzenie go) 
 * wybudza antywirusy (np. Windows Defender), co zatrzymuje wątek AHK na kilkadziesiąt 
 * lub kilkaset milisekund (tzw. I/O Interception). Zignoruj całkowicie pierwszą anomalię 
 * czasową w logu, ponieważ dotyczy ona narzutu operacyjnego systemu na otwarcie pliku, 
 * a nie wydajności Twojego kodu wewnątrz skryptu!
 */
QPC(krok) {
    static freq := 0, last := 0, sciezkaLogu := ""
    current := 0 ; <--- Inicjalizacja wymuszana przez AHK v2 przy DllCall z wyjściem w parametrze
    if !freq
        DllCall("QueryPerformanceFrequency", "Int64*", &freq)
    DllCall("QueryPerformanceCounter", "Int64*", &current)
    
    if (sciezkaLogu == "" || krok == "START") {
        if !DirExist(A_ScriptDir "\QPC_Logs")
            DirCreate(A_ScriptDir "\QPC_Logs")
        sciezkaLogu := A_ScriptDir "\QPC_Logs\QPC_Log_" FormatTime(A_Now, "yyyy_MM_dd__HH_mm_ss") ".txt"
    }

    if (krok == "START") {
        FileAppend("`n=== NOWY POMIAR (" FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " | Tick: " A_TickCount ") ===`n", sciezkaLogu)
    } else {
        ; Obliczenie czasu od ostatniego kroku (w milisekundach)
        czas := Round((current - last) * 1000 / freq, 2)
        FileAppend(krok . ": " . czas . " ms`n", sciezkaLogu)
    }
    last := current
}