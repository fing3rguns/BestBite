# Changelog

## Unreleased

- An item counts as stock, and may be restocked, whenever its own level requirement is one you already meet. The ten-level band that kept modest food and water out of the count is gone, so an innkeeper's food counts again.
- What a visit did is said in the game's own dialog now, raised through `StaticPopup_Show` with a dialog of the addon's own: `Restocked <count> <item> for <coins>`, or a line saying why nothing was bought. It closes itself and only you see it. It is no longer a frame drawn over your character: this client gives an addon no chat bubble to borrow, so every drawn version looked unlike the client's own.

## 1.5.0

Restocking at vendors. Off until you switch it on in the window.

- Opening a vendor that sells food or water tops your bags up to the amount you keep for each kind (5 by default, 5 to 100 in steps of 5), buying the item BestBite would have used itself.
- Only items good for your level count as stock and are restocked. When the vendor sells nothing good for your level it restocks the best it has  -  once per visit, and only when you carry none of that kind already.
- It never restocks more than you are short of, than the vendor has, or than you can afford.
- Stands aside when Polestar's Restock is already set to keep food or water.
- What it restocked is said in a bubble over your character  -  `Restocked`, then one line per kind  -  rather than in chat, and money is written in gold, silver and copper with the client's own coin icons.
- `Buy now` in the window restocks on demand, even with the feature switched off.

### Fixed

- Settings now survive logging out: the addon reads the saved table the client hands it instead of one remembered from before it arrived, which had been discarding the restock setting, and what it had learned, at every logout.
- Merchant food and drink are read through the item's own link and then the spell its use is filed under, for this client's merchant tooltip, which carries no "Use:" line.
- Stock and price come from the client's fixed item tuple, and a missing availability reads as unlimited rather than sold out.
- Purchases are split within the merchant's per-purchase limit, and items still on their way are not bought a second time.

## 1.2.0

- Buff food is preferred until the Well Fed buff is banked, and the biggest restore once it is; in the buff's last 30 seconds buff food leads again.
- The window: the two macros ready to copy, a switch for each setting, and the rest of the commands as buttons.
- A logo, used as the addon icon and as the window's portrait.
- The buttons stay in place and grey out when there is nothing to use, saying what they are out of on hover.

## 1.1.0

- Empty-state buttons: a button with nothing to use no longer disappears.
- Food and water are told apart, and ranked, from their own tooltips.

## 1.0.0

- First release: two secure buttons holding the best food and water in your bags, pressed by a macro.
