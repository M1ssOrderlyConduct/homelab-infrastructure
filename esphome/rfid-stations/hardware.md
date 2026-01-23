# RFID Hardware Shopping List

## Per Station Cost: ~$4-5

## Component List

### ESP32 Boards
- **ESP32-WROOM-32 DevKit** - $2.50-4 each
- AliExpress: Search "ESP32 WROOM 32 development board"
- Get 5-pack for ~$12

### RFID Readers
- **RC522 RFID Module** - $0.80-1.50 each
- AliExpress: Search "RC522 RFID module"
- 5-pack ~$5

### NFC Tags
| Type | Price | Use |
|------|-------|-----|
| NTAG215 Stickers (25mm) | $0.08-0.15/ea | Stick anywhere |
| NTAG215 Keychains | $0.20-0.30/ea | Tim's daily carry |
| NTAG215 Wristbands | $0.40-0.60/ea | Kids love these |

### Misc
- Dupont wires (M-F, F-F) - $2 kit
- USB-A power adapters (5V 1A) - old phone chargers work

## Wiring Diagram

```
RC522 Module          ESP32 DevKit
────────────────────────────────────
SDA (SS)       →      GPIO5
SCK            →      GPIO18
MOSI           →      GPIO23
MISO           →      GPIO19
IRQ            →      (not connected)
GND            →      GND
RST            →      GPIO22
3.3V           →      3.3V
```

## Full Order (10 Stations + Tags)

```
AliExpress Order 1:
────────────────────
10x ESP32-WROOM-32 DevKit        $25
10x RC522 RFID Module            $10
1x  Dupont Wire Kit              $2
                          Total: ~$37

AliExpress Order 2 (Tags):
────────────────────
50x NTAG215 Sticker Tags         $5
20x NTAG215 Keychain Tags        $5
10x NTAG215 Silicone Wristbands  $5
                          Total: ~$15

Local (faster):
────────────────────
5x USB-A Wall Adapters           $10
Project boxes (optional)         $10
                          Total: ~$20

═══════════════════════════════════
GRAND TOTAL: ~$72 for 10 stations
═══════════════════════════════════
```

## Station Locations

| Priority | Location | Task Tracked |
|----------|----------|--------------|
| 1 | Laundry | Multi-step laundry workflow |
| 2 | Kitchen | Daily cleanup |
| 3 | Kid 9 Room | Room cleaned |
| 4 | Kid 6 Room | Room cleaned |
| 5 | Living Room | Tidied |
| 6 | Garage | Project work |
| 7 | Master Bedroom | Maintained |
| 8+ | Expand as needed | |
