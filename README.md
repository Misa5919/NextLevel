# NextLevel

A World of Warcraft (1.12 / Turtle WoW) addon that celebrates your level-ups with animated stat gains and skill unlock notifications.

![NextLevel in action](NextLevel.gif)

## Features

- **Animated stat gains**  Health, Strength, Agility, Stamina, Intellect, and Spirit increase smoothly with sliding numbers and a gold pop effect.
- **Skill unlocks**  Shows new abilities available from your class trainer (with icons and rank).
- **Talent point notification**  Reminds you when a new talent point is available (levels 10 - 60).
- **Persistent skill database**  Only need to visit your class trainer once per character; skills are saved across sessions.
- **Vanilla 1.12 compatible**  Works on Turtle WoW and other 1.12 clients.

## Installation

1. Download the latest release from [GitHub](https://github.com/Misa5919/NextLevel).
2. Extract the folder into your `World of Warcraft/Interface/AddOns/` directory.
3. Make sure the folder is named exactly `NextLevel`.
4. Launch the game and enable the addon in the character selection screen.

## Usage

### Slash Commands

| Command | Description |
|---------|-------------|
| `/nextlevel` | Test the addon with a simulated levelUp (default level 60). |
| `/nextlevel 20` | Test with a specific level (e.g., 20). |
| `/nextlevel reset` | Reset the stored trainer skills for your current class. Use this if skills change after a patch. |

The addon automatically scans your class trainer when you open the trainer window. After the first scan, all future levelUps will show the correct skills without needing to visit the trainer again.

## Customisation

All colors, fonts, and animations can be tweaked by editing the `THEME` table in `NextLevel.lua`. The code is well commented to guide you.

## Credits

- **Author**: Misa5919
- **Inspired by**: TrainerSkills addon (for skill scanning) and classic LevelUpFX.

## License

This addon is released under the MIT License. See the `LICENSE` file for details.

## Support

If you encounter any bugs or have suggestions, please [open an issue](https://github.com/Misa5919/NextLevel/issues) on GitHub.