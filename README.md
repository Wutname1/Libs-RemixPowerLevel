Displays power level information for Timerunner characters in both MOP Remix and Legion Remix. Track your thread count or Infinite Power buff and see other players' progression.

## Features

### Power Level Display

- **Character Screen**: View your power level directly on the character sheet
  - MOP Remix: Thread count displayed next to Cloak of Infinite Potential
  - Legion Remix: Infinite Power total shown above main weapon slot
- **Tooltips**: Mouse over yourself or other players to see detailed power information
  - MOP Remix: Total thread count
  - Legion Remix: Infinite Power total, Versatility stat, and estimated Limits Unbound
- **Minimap Button**: Hover to see your stats and top 10 power levels in your group or raid
  - Shows your current Infinite Power/Threads, Versatility, and estimated Limits Unbound
  - Lists top 10 players by total power level

### Auto Scrapper (Legion Remix)

The addon includes an auto-scrapping system that appears when you open a scrapping machine:

- **Automatic Scrapping**: Automatically fills the scrapping machine with items matching your filters
- **Quality Filtering**: Set maximum item quality to scrap (Common, Uncommon, Rare, or Epic)
- **Item Level Filtering**: Only scrap items below your currently equipped gear by a specified item level difference
- **Affix Blacklist**: Exclude items with specific stats or affixes from being scrapped
  - Preset list of Legion Remix affixes (with spell icons and tooltips)
  - Common stats dropdown (Avoidance, Critical Strike, Haste, Leech, Mastery, Speed, Versatility)
  - Custom text entry for other affixes or stats
- **Item Preview**: Side panel shows all items matching your filters
- **Scrapping Queue**: Bottom panel displays items currently loaded in the scrapping machine
- **Settings**: Configure all options either in-game through the scrapping UI or via `/rpl` command

The auto scrapper helps manage large amounts of gear during Legion Remix by automating the tedious process of manually selecting items to scrap.

**Auto Scrapper UI:**

![Auto Scrapper Example](https://media.forgecdn.net/attachments/1360/376/autoscrap-png.png)

**Legion Remix:**

![Legion Remix Example](https://media.forgecdn.net/attachments/1314/573/legion-png.png)

**MOP Remix:**

![MOP Remix Example](https://media.forgecdn.net/attachments/872/876/examplescreen.png)

## Technical Notes

### MOP Remix
- Tracks the "Timerunner's Advantage" buff which contains thread counts across 9 different thread types
- Displays total thread count from all equipped threads on the Cloak of Infinite Potential

### Legion Remix
- Tracks the "Infinite Power" buff which provides multiple stats including Versatility
- The buff contains an array of stat values (powerData.points)
- **Infinite Power Total**: Sum of all stat values in the buff
- **Versatility**: The first point value (index 1) from the Infinite Power buff
- **Est. Limits Unbound**: Estimated from the Versatility value (same as Versatility)
- Unlike MOP Remix threads, Legion power is tracked through buff values rather than item-based currencies

## Support

- **Discord**: [![Discord](https://img.shields.io/discord/265564257347829771.svg?logo=discord&style=for-the-badge)](https://discord.gg/Qc9TRBv)
- **Issues**: [![Issues](https://img.shields.io/github/issues/wutname1/Libs-RemixThreadCount?style=for-the-badge)](https://github.com/Wutname1/Libs-RemixThreadCount/issues)
