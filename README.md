# FPGA Paint

A simple paint application for FPGA with VGA output and PS2 mouse input.

## Controls

### Drawing
- **SW[0]**: Enable/disable drawing mode
- **Left Mouse Button**: Draw with selected color
- **Right Mouse Button**: Erase (white)
- **Middle Mouse Button**: Draw rectangles (click two corners)

### Cursor Size
- **KEY[1]**: Cycle through cursor sizes
  - Size 1: 1x1 pixel
  - Size 2: 3x3 pixels
  - Size 3: 7x7 pixels
  - Size 4: 20x20 pixels

### Color Selection
- **SW[9:7]**: Select pen color (RGB)
  - SW[9]: Red
  - SW[8]: Green
  - SW[7]: Blue

### Screen Clearing
- **KEY[3]**: Clear entire screen
- **Left Click on Title Screen**: Also clears screen

### Reset
- **KEY[0]**: System reset

## Display
- Resolution: 320x240 pixels
- Color Depth: 9-bit (3 bits per RGB channel)
- Background: White (from background.mif file)

## Features
- Variable cursor size
- Color selection via switches
- Rectangle drawing tool
- Screen clearing
- Title screen mode

