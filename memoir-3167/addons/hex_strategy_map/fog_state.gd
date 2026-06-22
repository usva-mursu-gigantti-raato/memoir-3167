class_name FogState
## Fog of war states.
##
## Enum shared by HexCell (storage) and FogOfWar (reveal logic).
## Use as an ordinary integer in match/comparisons — does not require instantiating anything.
##   HIDDEN   → hex never seen by the player (total darkness).
##   EXPLORED → hex seen in the past but outside the current range (partial shadow).
##   VISIBLE  → inside the current vision range (completely revealed).
enum { HIDDEN, EXPLORED, VISIBLE }
