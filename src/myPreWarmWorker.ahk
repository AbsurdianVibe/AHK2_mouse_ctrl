#Requires AutoHotkey v2.0
#NoTrayIcon
#SingleInstance Force

#Include "..\AHK2_Colorful_GUI\AHK2ColorfulGUI.ahk"

; Wymuszenie twardego odczytu czcionek i GDI z dysku przez proces poboczny
SilnikGUI.InicjalizujSilnik()
ExitApp()