# BestBite

Uses the best food or water in your bags, for **World of Warcraft: Forever**.

- Two small buttons above your action bar hold your best food and best water: click one to eat or drink.
- Or drive them from a macro with `/click BestBiteFood` and `/click BestBiteWater`.
- "Best" means the most useful: food that grants a stat buff first, then the most it restores, and only items you can use right now count.
- Each button shows the item it holds, and its tooltip is that item's own tooltip.

## Why buttons rather than a command

The game blocks an addon from using an item from your bags. Calling it produces the dialog "BestBite has been blocked from an action only available to the Blizzard UI", because using an item is reserved for Blizzard's own code. No addon can get around that.

A secure button can, because the client performs the use itself and the addon only says which item. So BestBite keeps two of them stocked with your best food and water. That is the only route the client offers, for any addon.

`/bb food`, `/bb water` and `/bb consume` still exist, but all they can do is explain this.

## The two buttons

They sit above the action bar by default, the left one for food and the right for water. Both are drawn as action buttons: the square slot ring around the icon, a dark plate so light item art still reads, and a hover highlight. `/bb move` or a right-drag repositions them.

- **Click** to use the item. The client does the using, so nothing is blocked.
- The corner of each button counts how many of that item your bags hold, added up over every stack; holding just one shows no number, as on an action button.
- **Drag** to move them: right-drag any time out of combat, or type `/bb move` and left-drag, which is easier on a trackpad. The position of each is remembered for every character, and `/bb move` again locks them down.
- Moving waits for combat to end, like any frame the game protects, and says so if you try mid-fight.
- When your bags hold no usable food or water, that button hides rather than offering something wrong.
- Their contents follow your bags out of combat, since a secure button's item is the game's to lock during a fight. If you eat your last food mid-fight, that button is empty until the fight ends.

## Macros

Eat:

```text
#showtooltip
/click BestBiteFood
```

Drink:

```text
#showtooltip
/click BestBiteWater
```

Both, one after the other:

```text
/click BestBiteFood
/click BestBiteWater
```

The macro's action bar button is repainted with the icon of the item it will use, and hovering it shows that item's tooltip rather than the macro's text. `/bb icons` turns the repainting off.

`/bb macroicon` goes further and rewrites the macro's stored icon, so it keeps the right picture even without the repainting. It is off by default because writing a macro is a Blizzard-only action; if this client refuses, the attempt switches itself back off and says so.

## What "best" means

Food and water are one item for one bar, so the addon picks the one that does the most for you and leaves the weaker ones for later.

- **Well Fed food comes first.** Food that grants a stat buff outranks food that does not, however much the plain food restores: a buff outlasts one meal's worth of health.
- Among buffed food, the **most stat points** wins, whatever the stat. Then the most restored, then the higher item level, then the bigger stack.
- The buff is read from the item's own tooltip, either as "Well Fed: Stamina increased by 12" or "Increases Stamina by 12 for 15 min", and remembered per item.
- Only items you can use right now count: your level, your class, and an item on cooldown are all respected, and a locked bag slot is passed over.
- It tells food from water by the "Restores N health" or "Restores N mana" line, so items added by Forever work without a list to maintain.
- Potions and bandages are not food: only the game's "Food & Drink" items are considered.
- Conjured mage food and water are treated like any other food and water in your bags.
- The addon does not decide whether you need to eat. The client performs the use, so a press always uses the item, full bar or not.

## Commands

| Command | What it does |
| --- | --- |
| `/bb` | Shows the commands and the macros to use. |
| `/bb food` | Explains that this takes a button or a macro, and which one. |
| `/bb water` | The same, for water. |
| `/bb consume` | The same, for both. |
| `/bb move` | Turns on left-drag for placing the two buttons, and off again. |
| `/bb icons` | Keeps action bar buttons showing the item they will use. On by default. |
| `/bb macroicon` | Also rewrites the macro's own icon, if the client allows it. Off by default. |
| `/bb reset` | Forgets the item data it has learned. |
| `/bb debug` | Reports what the addon sees: the buttons, the bars, and every food or drink in the bags. |

`/bestbite` is a long form of `/bb`.

## If a macro does nothing

The button a macro clicks has to be showing, and it hides when your bags hold no usable item of that kind. So `/click BestBiteFood` on an empty food bag does nothing, by design.

`/bb debug` prints what each button is stocked with and whether it is showing:

```text
buttons: food item:4606 (shown true) | water item:1205
macros: /click BestBiteFood and /click BestBiteWater
```

If that reads `food nil`, the bags held no usable food at the time: it may be food you cannot use at your level, a potion rather than food, or an empty bag. The lines above it list every food or drink the addon found, with the amount it read from each tooltip.

## Install

1. Put the `BestBite` folder in `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game, or type `/reload`.
3. The two buttons appear above your action bar; drag them where you want them.

No dependencies.

## Tests

`Tests\` holds a harness that loads the addon against a fake client and checks the ranking, the stocking, both buttons, the macro handling and the printed messages. It is not part of the addon and is not in the `.toc`, so the game never loads it.

```text
pip install lupa
python Tests\run.py
```

It prints one line per check and exits non-zero if any fail. The fake client refuses to use an item from a bag exactly as the real one does, so a change that goes back to using bag items directly fails the suite instead of failing in game.

## Notes

- Everything it prints goes to your own chat frame. The addon never sends anything to other players, and it never announces which item it used.
- Button positions, the two icon settings and what the addon has learned are saved for the account in `BestBiteDB`.
- Detection reads the "Restores N health" or "Restores N mana" line of an item's tooltip. English clients are covered fully; the tooltips of a few other languages are matched too, while the chat messages are English only.
- If an item is ever classified wrongly, `/bb reset` clears what it has learned.