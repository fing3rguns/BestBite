# BestBite

<img src="Logo.png" width="220" alt="BestBite logo">

Uses the best food or water in your bags, for **World of Warcraft: Forever**.

Two buttons hold your best food and your best water: click one to eat or drink. Drag them anywhere you like, and a macro can press them:

```text
#showtooltip
/click BestBiteFood
```

```text
#showtooltip
/click BestBiteWater
```

Both in one macro is just the two `/click` lines together. Right-drag a button to move it, or type `/bb move` to left-drag instead.

Type `/bb` for the BestBite window: the two macros ready to copy, a switch for each setting, and a button for the rest. Drag it by its title bar, and Esc closes it.

The game blocks an addon from using an item itself, which is why the buttons exist: the click has to come from you or a macro, never from the addon. BestBite only decides which item the button holds.

## Install

1. Put the `BestBite` folder in `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game, or type `/reload`.

No dependencies.

## What "best" means

- Only what you can use right now counts: your level, your class, an item on cooldown, and a locked bag slot are all respected.
- Buff food comes first, until you have the buff. With Well Fed banked and more than 30 seconds to run, that buff is already paid for, so the biggest restore wins instead; in its last 30 seconds buff food leads again to top it up. Among buffed food, the most stat points win, then the most restored.
- Food is told from water by the tooltip's "Restores N health" or "Restores N mana" line, and any Well Fed bonus from the same tooltip, so nothing needs a list to maintain.
- It never decides whether you need to eat: a press always uses the item, full bar or not.

## Commands

| Command | What it does |
| --- | --- |
| `/bb` | Opens the window: the macros to copy, and a button for each of these commands. |
| `/bb food`, `/bb water`, `/bb consume` | Explain that eating takes a button or a macro, and which one. |
| `/bb move` | Left-drag the buttons into place; again to lock them down. |
| `/bb icons` | Action bar buttons show the item they will use. On by default. |
| `/bb macroicon` | Also rewrite the macro's own icon, if this client allows it. Off by default. |
| `/bb reset` | Forget what it has learned about items. |
| `/bb debug` | Opens the window on its debug page: what it sees, and every food or drink in the bags. |

`/bestbite` is a long form of `/bb`.

## If a macro does nothing

The button is holding no item, so there is nothing to use: no food or water you can use at your level in the bags, a potion rather than food, or an empty bag. Such a button stays where it is and greys out, and hovering it says what it is out of.

`/bb debug`, or the Debug button in the window, names what each button holds and lists every food or drink it found, with what it read from each tooltip.

## Tests

`Tests\` holds a harness that loads the addon against a fake client and checks the ranking, the food buff, the stocking, both buttons, the macro handling and the messages. It is not in the `.toc`, so the game never loads it.

```text
pip install lupa
python Tests\run.py
```

## Notes

- Everything it prints goes to your own chat frame; nothing is sent to other players, and it never announces which item it used.
- Button positions, the two icon settings and what it has learned are saved for the account in `BestBiteDB`.
- It knows the food buff by its aura, "Well Fed"; the window's debug page prints your auras if a client ever names it differently.
- Chat messages are English only. Item tooltips are matched in English and a few other languages.
- `Logo.png` is the logo shown above. `Portrait.png` is that art on a dark disc, which is what the window wears as its portrait, and `Icon.png` is the 128 by 128 image the game shows in its addon list.