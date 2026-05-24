# Gaming Module

Optimized gaming setup with Steam and Proton support.

## Includes
- **Steam** — With Millennium theming override
- **Proton** — Linux game compatibility layer
- **MangoHUD** — In-game FPS and performance overlay
- **Blockbench** — 3D model editor for Minecraft

## Enabling MangoHUD

MangoHUD is installed but requires launch flag in Steam:

1. Right-click game in Steam
2. Properties → Launch Options
3. Add: `mangohud %command%`

## Millennium Steam Theme

Steam runs with Millennium override for custom UI theming. Configuration:
- Location: `files/modules/gaming/millennium/`
- Modifies Steam client appearance
- Does NOT affect game functionality

## AMD GPU Support

System includes 32-bit libraries for gaming:
- OpenGL 32/64-bit
- Vulkan 32/64-bit
- OpenCL support

## Performance Optimization

CPU governor set to "performance" for gaming (see performance.nix)
- Reduces latency
- Increases power consumption
- Automatic on system boot
