# Hex Tactics

A Godot 4.x MVP for a hex-grid tactical game playable **locally** (hot-seat) or **online** via P2P (ENet).

## Requirements

- [Godot 4.2+](https://godotengine.org/download)

## Run

1. Open this folder in Godot (`project.godot`).
2. Press **F5** to run.

## Game Flow

1. **Main Menu** — Local hot-seat, host online, or join with IP.
2. **Character Select** — Each player picks a team (leader + 2 followers + unique tile).
3. **Match** — Hex board with fog-of-war tiles, 3 actions per turn.
4. **End Game** — Rematch, new character select, or disconnect.

## Architecture

### Abstract base classes

| Class | File | Extend for |
|-------|------|------------|
| `UnitBase` | `scripts/entities/unit_base.gd` | New units (stats, ability, attack die) |
| `TileBase` | `scripts/entities/tile_base.gd` | New tile types (reveal, interact, modifiers) |

### Registries (add new content here)

- `scripts/units/unit_registry.gd` — Register unit factories by type ID.
- `scripts/tiles/tile_registry.gd` — Register tile factories by type ID.
- `scripts/teams/team_registry.gd` — Define teams linking leaders, followers, unique tiles, max RP.

### Placeholder factions

| Team | Leader | Followers | Unique Tile | Max RP |
|------|--------|-----------|-------------|--------|
| Sentinels | Sentinel Prime | 2× Sentinel Guard | Bastion | 6 |
| Veilborne | Veil Archon | 2× Veil Scout | Mirror Veil | 5 |
| Emberclad | Ember Warlord | 2× Ember Raider | Ember Forge | 4 |

### Turn actions (3 per player per turn)

- **Move** — Each of your units moves 0–move_range hexes; gain 1 resource point.
- **Attack** — One unit rolls `1..attack_die_sides` damage against an enemy in range.
- **Ability** — Spend unit-specific RP for a special effect.
- **Tile Interact** — Use your team's unique tile at a unit's position.

### Win condition

Defeat the opponent's **team leader**.

### Online P2P

- Host listens on port **7777** (configurable in `network_manager.gd`).
- Client joins with host IP.
- Character select and match start are synced via RPC.
- For production, add authoritative action sync and rollback; this MVP runs full rules locally after match start.

## Project layout

```
scripts/
  autoload/       GameState, NetworkManager
  core/           HexCoords, HexGrid, TurnManager, MatchController
  entities/       UnitBase, TileBase (abstract)
  units/          UnitRegistry + placeholder units
  tiles/          TileRegistry + placeholder tiles
  teams/          TeamDefinition, TeamRegistry
  ui/             Scene controllers
scenes/           main_menu, character_select, game_board, end_game
```

## Extending

**New unit:** Subclass `UnitBase` in `unit_registry.gd`, override `use_ability()` and `get_ability_description()`, register in `_factories`.

**New tile:** Subclass `TileBase` in `tile_registry.gd`, override `on_unit_enter()`, `interact()`, register in `_factories`.

**New team:** Add a `TeamDefinition` entry in `team_registry.gd`.
