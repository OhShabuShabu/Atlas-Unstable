#!/usr/bin/env python3
import sys
import colorsys

def fix_color(hex_color):
    hex_color = hex_color.lstrip('#').upper()
    if len(hex_color) != 6:
        return hex_color

    r = int(hex_color[0:2], 16) / 255
    g = int(hex_color[2:4], 16) / 255
    b = int(hex_color[4:6], 16) / 255

    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    
    if s < 1.0 and v > 0.2:
        s = 1.0
    
    r, g, b = colorsys.hsv_to_rgb(h, s, v)
    
    r = min(255, int(r * 255))
    g = min(255, int(g * 255))
    b = min(255, int(b * 255))

    return f"{r:02X}{g:02X}{b:02X}"

if __name__ == "__main__":
    if len(sys.argv) > 1:
        color = sys.argv[1]
    else:
        color = input().strip()

    print(fix_color(color))