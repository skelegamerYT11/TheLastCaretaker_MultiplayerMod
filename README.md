# The Last Caretaker - Multiplayer Mod (Early Access)

Welcome to the unofficial **Multiplayer Sync Mod** for *The Last Caretaker*! 

This mod was created because the game has immense potential for co-op gameplay. My hope is that the developers see this proof-of-concept and officially implement a native multiplayer mode in the future!

## ⚠️ Disclaimer & Current State
**This is an experimental proof-of-concept.** 
The mod syncs player coordinates and door states between two clients using UE4SS and memory-reading scripts. 

**What works right now:**
- You can see the other player moving around in your world.
- You can open and close doors together. *(Note: You must push the sliding doors all the way to the end of their track for the state to sync properly to the other player).*

**What does NOT work yet / Known Issues:**
- Item dropping and picking up is not synced (to prevent memory crashes and duplication glitches).
- You might experience occasional bugs or desyncs, though it has been quite stable in our recent tests.
- Animations are not fully synced (the avatar slides towards the target location).

## ⚙️ Requirements
1. **Game Version:** Tested on `v.0.8.0.612251` (Early Access).
2. **UE4SS:** You MUST use the specific version of UE4SS provided in the Nexus Mods page: 
   [Download UE4SS from NexusMods](https://www.nexusmods.com/thelastcaretaker/mods/4)

## 🚀 Installation & Usage
1. Download and extract this repository.
2. Place the `ue4ss` folder inside your game's binary directory: `\The Last Caretaker (Early Access)\Voyage\Voyage\Binaries\Win64\`
3. Run the `Avvia_Connessione.bat` (or your PowerShell sync script) on both PCs to bridge the network connection between the two clients.
4. Launch the game. If you did everything correctly, you'll see the other player's avatar load into your world!

## 📸 Demonstration
![Multiplayer Demo](demo.png)

## 🔮 Future Updates
I may release further updates to improve stability, add item sync, or refine the avatar movement. Keep an eye on this repository!

---
*Created by the community, for the community.*
