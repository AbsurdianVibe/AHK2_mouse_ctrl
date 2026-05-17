#Requires AutoHotkey v2.0

class MouseCtrlLib {
    /**
     * Tymczasowo przejmuje kontrolę nad kółkiem myszy (WheelUp/WheelDown) wykonując zadane funkcje,
     * dopóki użytkownik trzyma wciśnięty określony klawisz (klawiszStop).
     * Opcjonalnie może symulować wciśnięcie modyfikatora (np. Ctrl) podczas trwania trybu.
     * 
     * @param {Func} akcjaGora - Funkcja (callback) wykonywana przy ruchu kółkiem w górę.
     * @param {Func} akcjaDol - Funkcja (callback) wykonywana przy ruchu kółkiem w dół.
     * @param {Func} [zwAkcjaON=0] - Funkcja wykonywana PRZED wejściem w pętlę oczekiwania (np. wciśnięcie Ctrl).
     * @param {Func} [zwAkcjaOFF=0] - Funkcja wykonywana PO wyjściu z pętli (np. puszczenie Ctrl).
     * @param {Func} [funkcjaCzyszczaca=0] - Opcjonalna funkcja wywoływana przy każdym ruchu kółkiem (np. () => ToolTip()).
     * @param {String} klawiszStop - Nazwa klawisza fizycznego, na którego zwolnienie funkcja czeka (np. "XButton1").
     * @param {String} [prefix="*"] - Prefiks hotkeya (np. "*" dla blokady, "~" dla przepuszczania).
     */
    static AktywujTrybKola(akcjaGora, akcjaDol, zwAkcjaON, zwAkcjaOFF, funkcjaCzyszczaca, klawiszStop, prefix := "*") {
        if (HasMethod(funkcjaCzyszczaca)) {
            _akcjaGora := akcjaGora, _akcjaDol := akcjaDol
            akcjaGora := (*) => (funkcjaCzyszczaca(), _akcjaGora())
            akcjaDol := (*) => (funkcjaCzyszczaca(), _akcjaDol())
        }
        
        (zwAkcjaON) && zwAkcjaON()
        try Hotkey(prefix . "WheelUp", akcjaGora, "On"), Hotkey(prefix . "WheelDown", akcjaDol, "On") 
        KeyWait(klawiszStop)
        try Hotkey(prefix . "WheelUp", "Off"), Hotkey(prefix . "WheelDown", "Off")
        (zwAkcjaOFF) && zwAkcjaOFF()
    }
}