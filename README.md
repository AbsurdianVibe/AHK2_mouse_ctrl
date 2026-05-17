# Mouse Control

This repository contains two AutoHotkey v2 scripts: `mouse_ctrl.ahk` (main script) and `mouse_ctrl_lib.ahk` (wheel control library). They provide advanced mouse shortcuts, screen brightness control, and volume control.

## About The Project
This is a highly personalized project. I made it for my own workflow. Setting it up for your needs (like changing hotkeys or the mouse hardware ID) requires manual code edits.

I originally planned to add a GUI for configuration. However, I abandoned this idea. I am freezing all my AHK2 projects to focus on learning a new programming language.

If you change any hotkey combinations in the code, you must also update the GUI text manually. The legend window text and the tooltips are independent. They will not update automatically.

## Submodules and Dependencies
This script uses my custom libraries. They are included as submodules (separate repositories):
* `AHK2_My_libs`: My custom utility functions.
* `AHK2ColorfulGUI`: My custom GUI engine used for settings and tooltips.

## Important Notes
* **Performance:** The script might be slightly unstable when your system is under heavy load (for example, when launching heavy software).
* **Admin Rights:** The script asks for Administrator privileges on startup. This is ONLY to make shortcuts work in system windows (like Task Manager). If you do not trust the script, you do not have to give it Admin rights. All features will still work in regular user mode. However, shortcuts will not work in system windows that require administrator rights (such as Task Manager).
* **Compiled Version (.exe):** I have not tested this script as a compiled `.exe` file. It might crash or cause critical errors if you compile it.
* **Language:** The current GUI interface is hardcoded in Polish. It requires localization.

## Legacy
This project is considered frozen. The codebase contains older solutions and hardcoded Polish text. I am no longer actively developing it. I will only add performance fixes and updates if I make important changes to the GUI library.