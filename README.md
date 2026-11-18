# BestBite

<img src="Logo.png" width="220" alt="BestBite logo">

Uses the best food or water in your bags, for **World of Warcraft: Forever**.

- Two small buttons above your action bar hold your best food and best water: click one to eat or drink.
- Or drive them from a macro with `/click BestBiteFood` and `/click BestBiteWater`.
- "Best" means the most useful: food that grants a stat buff first, then the most it restores, and only items you can use right now count, except once that buff is already on you, when the biggest restore wins until the buff is nearly spent.
- Each button shows the item it holds, and its tooltip is that item's own tooltip. With nothing to use it greys out and keeps its place.

## Why buttons rather than a command

The game blocks an addon from using an item from your bags. Calling it produces the dialog "BestBite has been blocked from an action only available to the Blizzard UI", because using an item is reserved for Blizzard's own code. No addon can get around that.

A secure button can, because the client performs the use itself and the addon only says which item. So BestBite keeps two of them stocked with your best food and water. That is the only route the client offers, for any addon.

An addon cannot press that button for you either. A click the addon makes itself is blocked the same way, which this addon confirmed by trying it. So nothing here can eat on your behalf: all BestBite can do is decide which item the button holds, and wait for your press.

`/bb food`, `/bb water` and `/bb consume` still exist, but all they can do is explain this.

## The two buttons

They sit above the action bar by default, the left one for food and the right for water. Both are drawn as action buttons: the square slot ring around the icon, a dark plate so light item art still reads, and a hover highlight. `/bb move` or a right-drag repositions them.

- **Click** to use the item. The client does the using, so nothing is blocked.
- The corner of each button counts how many of that item your bags hold, added up over every stack; holding just one shows no number, as on an action button.
- **Drag** to move them: right-drag any time out of combat, or type `/bb move` and left-drag, which is easier on a trackpad. The position of each is remembered for every character, and `/bb move` again locks them down.
- Moving waits for combat to end, like any frame the game protects, and says so if you try mid-fight.
- When your bags hold no usable food or water, that button stays where it is with its icon greyed, rather than vanishing or offering something wrong. A greyed button has no item to use, so clicking it does nothing; hovering it says "Out of food" or "Out of water" and what fills the slot again.
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

- **Well Fed food comes first, until you have the buff.** With no food buff, food that grants a stat buff outranks food that does not, however much the plain food restores: a buff outlasts one meal's worth of health. Once that buff is on you with more than 30 seconds to run, it is already paid for, so the food that restores the most wins instead. In the buff's last 30 seconds the buff food leads again, ready to top it up before it lapses.
- Among buffed food, the **most stat points** wins, whatever the stat. Then the most restored, then the higher item level, then the bigger stack.
- The button follows that on its own: eat the buff food, and the button switches to your best plain food as soon as the buff lands; press it a second time for the bigger restore. Nothing can press it for you: the client blocks a click the addon makes, so it is your press, not an automatic one.
- It knows the buff by its aura, "Well Fed", and how long that aura has left; `/bb debug` prints your auras if a client ever names it differently.
- The buff is read from the item's own tooltip, either as "Well Fed: Stamina increased by 12" or "Increases Stamina by 12 for 15 min", and remembered per item.
- Only items you can use right now count: your level, your class, and an item on cooldown are all respected, and a locked bag slot is passed over.
- It tells food from water by the "Restores N health" or "Restores N mana" line, so items added by Forever work without a list to maintain.
- Potions and bandages are not food: only the game's "Food & Drink" items are considered.
- Conjured mage food and water are treated like any other food and water in your bags.
- The addon does not decide whether you need to eat. The client performs the use, so a press always uses the item, full bar or not.

## Commands

| Command         | What it does                                                                                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/bb`           | Shows the commands and the macros to use.                                                                                                                                                        |
| `/bb food`      | Explains that this takes a button or a macro, and which one.                                                                                                                                     |
| `/bb water`     | The same, for water.                                                                                                                                                                             |
| `/bb consume`   | The same, for both.                                                                                                                                                                              |
| `/bb move`      | Turns on left-drag for placing the two buttons, and off again.                                                                                                                                   |
| `/bb icons`     | Keeps action bar buttons showing the item they will use. On by default.                                                                                                                          |
| `/bb macroicon` | Also rewrites the macro's own icon, if the client allows it. Off by default.                                                                                                                     |
| `/bb reset`     | Forgets the item data it has learned.                                                                                                                                                            |
| `/bb debug`     | Reports what the addon sees: the buttons, your auras, the bars, and every food or drink in the bags.                                                                                             |
| ` `             | Presses the food button from its own code and reports whether the client honoured the click. A diagnostic, not a feature: it is how we learn whether a second bite could ever happen on its own. |

`/bestbite` is a long form of `/bb`.

## If a macro does nothing

`/click BestBiteFood` with no usable food in your bags does nothing, by design: the button is there, but greyed and holding no item, so the click finds nothing to use.

`/bb debug` prints what each button is stocked with:

```text
buttons: food item:4606 | water empty
macros: /click BestBiteFood and /click BestBiteWater
```

If that reads `food empty`, the bags held no usable food at the time: it may be food you cannot use at your level, a potion rather than food, or an empty bag. The lines above it list every food or drink the addon found, with the amount it read from each tooltip.

## Install

1. Put the `BestBite` folder in `World of Warcraft\_forever_\Interface\AddOns\`.
2. Restart the game, or type `/reload`.
3. The two buttons appear above your action bar; drag them where you want them.

No dependencies.

## Tests

`Tests\` holds a harness that loads the addon against a fake client and checks the ranking, the food buff, the stocking, both buttons, the macro handling and the printed messages. It is not part of the addon and is not in the `.toc`, so the game never loads it.

```text
pip install lupa
python Tests\run.py
```

It prints one line per check and exits non-zero if any fail. The fake client refuses to use an item from a bag exactly as the real one does, so a change that goes back to using bag items directly fails the suite instead of failing in game.

## Notes

- Everything it prints goes to your own chat frame. The addon never sends anything to other players, and it never announces which item it used.
- Button positions, the two icon settings and what the addon has learned are saved for the account in `BestBiteDB`.
- `Logo.png` is the addon's logo, shown at the top of this page; `Icon.png` is the same art at 128 by 128, which is what the game shows in its addon list.
- Detection reads the "Restores N health" or "Restores N mana" line of an item's tooltip. English clients are covered fully; the tooltips of a few other languages are matched too, while the chat messages are English only.
- If an item is ever classified wrongly, `/bb reset` clears what it has learned.
