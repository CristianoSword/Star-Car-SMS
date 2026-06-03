# star-car

A racing game for the **Sega Master System**, written entirely in **Z80 Assembly**.

## Build

Requires [WLA-DX](https://github.com/vhelin/wla-dx) (win64):

```bash
wla-z80 -o racer.asm racer.o
wlalink -drvs linkfile star-car.sms
```

Output ROM: `build/star-car.sms`

## Status

Work in progress — the project already compiles and includes:

- Graphics headers
- Initial tileset / graphics
- Gameplay (coming eventually)

> There's still a lot to do, but I'll get back to it when I have the time and patience.

## Screenshot

![star-car screenshot](https://github.com/user-attachments/assets/97895bb6-9ba2-4c25-99a7-8c4b7e4bef3b)

## Notes

- Target platform: Sega Master System
- Language: Z80 Assembly only
- Assembler: [WLA-DX](https://github.com/vhelin/wla-dx)

