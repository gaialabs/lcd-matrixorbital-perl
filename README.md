# lcd-matrixorbital-perl

Legacy **Matrix Orbital** serial LCD (e.g., 20x4 modules common in the late 1990s) helper for Perl.  
This repository contains a single procedural Perl module, `lcd.pm`, plus Debian packaging to build an installable `.deb`.

The module was originally written in **1999** and has been **modernised** while keeping the **same exported functions** for backward compatibility:

- `strict` / `warnings`
- safer serial initialisation
- configurable serial **device** (no hard-coded `/dev/ttyS0`)
- better error handling (`Carp`)
- cleaner internal state

---

## Contents

- [`lcd.pm`](./lcd.pm) — the Perl module
- [`debian/`](./debian/) — Debian packaging files

---

## Requirements

### Runtime
- Perl (any modern Debian/Ubuntu Perl should work)
- A serial device for the LCD (e.g. `/dev/ttyS0`, `/dev/ttyUSB0`)
- A keypad device file if you use keypad input (default: `/dev/ttyS0`)

> **Note:** `lcd.pm` configures the serial port using `stty`, so `stty` must be available (typically from `coreutils`).

### Build (Debian package)
- `debhelper` (compat 13)
- `dh-perl`
- `devscripts` (for `dpkg-buildpackage`, etc.)

---

## Build a Debian package

From the repository root (the directory containing `debian/`):

```bash
sudo apt-get install devscripts debhelper dh-perl fakeroot lintian
dpkg-buildpackage -us -uc
```

The resulting `.deb` will be created in the parent directory, for example:

- `liblcd-matrixorbital-perl_1.0-1_all.deb`

Install locally:

```bash
sudo apt install ../liblcd-matrixorbital-perl_1.0-1_all.deb
```

---

## Install without Debian packaging (manual)

If you just want the module:

- Copy `lcd.pm` into a directory in `@INC`, e.g.:

```bash
sudo install -m 0644 lcd.pm /usr/local/share/perl/5.36.0/lcd.pm
```

(Adjust the path for your Perl version / distro.)

---

## Quick start

```perl
use lcd;

# Old style (still works, uses defaults)
lcd_open();

lcd_clear_display();
lcd_goto(1, 1);
lcd_write("Hello, LCD!");

# Read one raw keypad byte, then map it to a friendly key (if any)
my $raw = lcd_read();
my $key = lcd_map_keypad($raw);

lcd_close();
```

---

## Serial port / device configuration

`lcd_open` now supports multiple calling styles:

### 1) Defaults
```perl
lcd_open();
```

Defaults are:
- LCD device: `/dev/ttyS0`
- Keypad device: `/dev/keypad`
- Speed: `19200`

### 2) Backward-compatible single argument (LCD device)
```perl
lcd_open('/dev/ttyUSB0');
```

### 3) Named arguments
```perl
lcd_open(
  lcd_device    => '/dev/ttyUSB0',
  keypad_device => '/dev/keypad',
  speed         => 19200,
);
```

### 4) Hashref
```perl
lcd_open({
  lcd_device    => '/dev/ttyUSB0',
  keypad_device => '/dev/keypad',
  speed         => 19200,
});
```

---

## API reference (exported functions)

The module exports the following procedural functions by default:

### Connection / I/O

#### `lcd_open( ... ) -> true`
Open the LCD serial device for writing and the keypad device for reading (binary).  
See **Serial port / device configuration** above.

#### `lcd_close() -> true`
Close the LCD and keypad handles if open.

#### `lcd_write($text) -> true`
Write raw text/bytes to the LCD device.

#### `lcd_read() -> $byte | undef`
Read **one byte** from the keypad device (raw). Returns `undef` on EOF/no data.

---

### Display behaviour

#### `lcd_auto_scroll_on()`
Enable auto-scroll.

#### `lcd_auto_scroll_off()`
Disable auto-scroll.

#### `lcd_auto_line_wrapping_on()`
Enable automatic line wrapping.

#### `lcd_auto_line_wrapping_off()`
Disable automatic line wrapping.

#### `lcd_auto_repeat_mode_0()`
Set repeat mode (device-specific).

#### `lcd_auto_repeat_mode_1()`
Set repeat mode (device-specific).

#### `lcd_auto_xmit_keypress_on()`
Enable automatic keypress transmission.

#### `lcd_auto_xmit_keypress_off()`
Disable automatic keypress transmission.

---

### Backlight / blink / brightness

#### `lcd_backlight_on()`
Turn backlight on.

#### `lcd_backlight_off()`
Turn backlight off.

#### `lcd_blink_on()`
Enable blinking cursor/indicator (device-specific).

#### `lcd_blink_off()`
Disable blinking cursor/indicator.

#### Brightness presets
- `lcd_set_brightness_100()`
- `lcd_set_brightness_75()`
- `lcd_set_brightness_50()`
- `lcd_set_brightness_25()`

---

### Clear / cursor / positioning

#### `lcd_clear_display()`
Clear the LCD display (device command).

#### `lcd_clear_screen()`
Send form-feed (`\x0C`) to clear screen (legacy behaviour).

#### `lcd_clear_key_buffer()`
Clear the keypad key buffer.

#### `lcd_cursor_on()`
Enable cursor.

#### `lcd_cursor_off()`
Disable cursor.

#### `lcd_cursor_left()`
Move cursor left.

#### `lcd_cursor_right()`
Move cursor right.

#### `lcd_backspace()`
Send backspace (`\x08`) (legacy behaviour).

#### `lcd_goto($col, $row)`
Position cursor at column/row. Values are sent as bytes.

#### `lcd_go_to_top_left()`
Move cursor to top-left.

---

### Contrast

The module maintains an internal `contrast_value` (0..255) and updates the device when you change it.

#### `lcd_contrast($value)`
Set contrast explicitly (0..255).

#### `lcd_contrastup()`
Increase contrast by an internal increment (default: 7).

#### `lcd_contrastdown()`
Decrease contrast by an internal increment (default: 7).

#### `lcd_getcontrast() -> $value`
Return the current internal contrast value.

---

### Keypad

#### `lcd_poll_keypad()`
Poll keypad (device command).

#### `lcd_set_debounce_time($value)`
Set keypad debounce time (byte value 0..255).

#### `lcd_map_keypad($raw_byte) -> $mapped | undef`
Map a raw keypad byte to a more friendly key (if known).  
Mapping table:

| Raw | Mapped |
|-----|--------|
| Y   | 1      |
| T   | 2      |
| O   | 3      |
| J   | A      |
| X   | 4      |
| S   | 5      |
| N   | 6      |
| I   | B      |
| W   | 7      |
| R   | 8      |
| M   | 9      |
| H   | C      |
| V   | .      |
| Q   | 0      |
| L   | #      |
| G   | D      |

---

### Custom characters

#### `lcd_create_custom_char($num, @bytes)`
Create a custom character.

- `$num` is the character slot (sent as one byte).
- `@bytes` must contain up to 8 byte values (missing values are padded with zeros).
- Values are clamped to 0..255.

---

### Large digits / bar graphs (device-specific)

These functions send device-specific commands used by some Matrix Orbital firmware.

#### `lcd_large_digit_init()`
Initialise large-digit mode.

#### `lcd_place_large_digit($col, $row)`
Place a large digit at column/row.

#### `lcd_hr_bar_graph_init()`
Initialise horizontal bar graph mode.

#### `lcd_make_hr_bar_graph($col, $row, $direction, $length)`
Draw a horizontal bar graph.

#### `lcd_vr_thick_bar_graph_init()`
Initialise vertical thick bar graph mode.

#### `lcd_vr_thin_bar_graph_init()`
Initialise vertical thin bar graph mode.

#### `lcd_make_vr_bar_graph($col, $length)`
Draw a vertical bar graph.

---

## Notes / caveats

- This module uses `stty` to configure the serial port. Behaviour can vary between platforms.
- The module writes directly to the serial device (`open '>'`), so your user needs permission to access the device.
- Keypad reading is **blocking** by default (depends on the device). If you need non-blocking reads, consider configuring the keypad fd externally.

---

## License

GPL-2.0-or-later (see `debian/copyright` or the license text on Debian systems in `/usr/share/common-licenses/GPL-2`).

---

## Contributing

Issues and PRs are welcome.  
