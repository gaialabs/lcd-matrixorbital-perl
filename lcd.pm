# Matrix Orbital LCD (20x4) helper (legacy)
#
# Original copyright (c) 1999-2026 Alexis Domjan <adomjan@horus.ch>
#
package lcd;

use strict;
use warnings;

use Carp qw(croak carp);
use IO::Handle ();
use parent qw(Exporter);

# All functions
our @EXPORT = qw(
  lcd_open
  lcd_close
  lcd_write
  lcd_read
  lcd_auto_scroll_on
  lcd_auto_scroll_off
  lcd_auto_line_wrapping_on
  lcd_auto_line_wrapping_off
  lcd_auto_repeat_mode_0
  lcd_auto_repeat_mode_1
  lcd_auto_xmit_keypress_on
  lcd_auto_xmit_keypress_off
  lcd_backlight_on
  lcd_backlight_off
  lcd_blink_on
  lcd_blink_off
  lcd_set_brightness_100
  lcd_set_brightness_75
  lcd_set_brightness_50
  lcd_set_brightness_25
  lcd_clear_display
  lcd_clear_key_buffer
  lcd_contrast
  lcd_contrastup
  lcd_contrastdown
  lcd_getcontrast
  lcd_cursor_on
  lcd_cursor_off
  lcd_cursor_left
  lcd_cursor_right
  lcd_set_debounce_time
  lcd_create_custom_char
  lcd_goto
  lcd_go_to_top_left
  lcd_poll_keypad
  lcd_large_digit_init
  lcd_place_large_digit
  lcd_hr_bar_graph_init
  lcd_make_hr_bar_graph
  lcd_vr_thick_bar_graph_init
  lcd_vr_thin_bar_graph_init
  lcd_make_vr_bar_graph
  lcd_backspace
  lcd_clear_screen
  lcd_map_keypad
);

# Keep these for compatibility with older code that accessed the filehandles/vars
# directly (not recommended, but it existed).
our @EXPORT_OK = qw( LCD KPD $cmd $contrast_value );

# --- Internal state ---------------------------------------------------------

our $DEFAULT_LCD_DEVICE    = '/dev/ttyS0';   # sensible default if no /dev/lcd symlink
our $DEFAULT_KEYPAD_DEVICE = '/dev/ttyS0';
our $DEFAULT_SPEED         = 19200;

our ($LCD, $KPD);           # package filehandles (exportable)
my  $opened = 0;

our $contrast_value = 230;
my  $contrast_incr  = 7;

# --- Keypad mapping ---------------------------------------------------------

my %keypad_map = (
  'Y' => '1',
  'T' => '2',
  'O' => '3',
  'J' => 'A',
  'X' => '4',
  'S' => '5',
  'N' => '6',
  'I' => 'B',
  'W' => '7',
  'R' => '8',
  'M' => '9',
  'H' => 'C',
  'V' => '.',
  'Q' => '0',
  'L' => '#',
  'G' => 'D',
);

# --- Command constants ------------------------------------------------------

our $cmd                     = "\xFE";
my  $auto_line_wrapping_on    = 'C';
my  $auto_line_wrapping_off   = 'D';
my  $auto_repeat_mode_0       = "~\x00";
my  $auto_repeat_mode_1       = "~\x01";
my  $auto_scroll_on           = 'Q';
my  $auto_scroll_off          = 'R';
my  $auto_xmit_keypress_on    = 'A';
my  $auto_xmit_keypress_off   = 'O';
my  $backlight_on             = "B\x00";
my  $backlight_off            = "F\n";
my  $blink_on                 = 'S';
my  $blink_off                = 'T';
my  $set_brightness_100       = "Y\x00";
my  $set_brightness_75        = "Y\x01";
my  $set_brightness_50        = "Y\x02";
my  $set_brightness_25        = "Y\x03";
my  $clear_display            = 'X';
my  $clear_key_buffer         = 'E';
my  $contrast                 = 'P';   # followed by 0..255
my  $cursor_on                = 'J';
my  $cursor_off               = 'K';
my  $cursor_left              = 'L';
my  $cursor_right             = 'M';
my  $set_debounce_time        = 'U';   # followed by a byte
my  $create_custom_char       = 'N';   # followed by 9 bytes
my  $goto                     = 'G';   # followed by 2 bytes
my  $go_to_top_left           = 'H';
my  $poll_keypad              = '&';
my  $large_digit_init         = 'n';
my  $place_large_digit        = '#';   # followed by 2 bytes
my  $hr_bar_graph_init        = 'h';
my  $make_hr_bar_graph        = '|';   # followed by 4 bytes
my  $vr_thick_bar_graph_init  = 'v';
my  $vr_thin_bar_graph_init   = 's';
my  $make_vr_bar_graph        = '=';   # followed by 2 bytes
my  $backspace                = "\x08";
my  $clear_screen             = "\x0C";

# --- Helpers ----------------------------------------------------------------

# Enable autoflush
sub _autoflush_on {
  my ($fh) = @_;
  return if !$fh;
  eval { $fh->autoflush(1) };
  if ($@) {
    # If it's not an IO::Handle object (older Perls), fall back.
    my $old = select($fh);
    $| = 1;
    select($old);
  }
}

# Configure serial port using stty
sub _configure_serial {
  my (%opt) = @_;
  my $dev   = $opt{device};
  my $speed = $opt{speed};

  # Try modern stty first.
  my @cmd_try = (
    [ 'stty', '-F', $dev, 'speed', $speed, 'clocal', '-echo', '-crtscts', 'raw', 'pass8' ],
    [ 'stty', '-f', $dev, 'speed', $speed, 'clocal', '-echo', '-crtscts', 'raw', 'pass8' ],
    [ 'stty', '-F', $dev, $speed, 'clocal', '-echo', '-crtscts', 'raw', 'pass8' ],
    [ 'stty', '-f', $dev, $speed, 'clocal', '-echo', '-crtscts', 'raw', 'pass8' ],
  );

  for my $argv (@cmd_try) {
    #my $ok = system(@$argv);
    my $ok = system(join(' ', @$argv) . ' >/dev/null 2>&1');
    return 1 if $ok == 0;
  }

  # Last resort (legacy): use redirection through a shell (kept for compatibility
  # with very old stty implementations). This is less safe; only use trusted paths.
  my $sh = "stty < $dev speed $speed clocal -echo -crtscts raw pass8";
  my $ok = system($sh);
  return 1 if $ok == 0;

  carp "Unable to configure serial port '$dev' at $speed baud (stty failed).";
  return 0;
}

# Fail if device is not opened
sub _require_open {
  croak "LCD not opened: call lcd_open() first" if !$opened;
}

# Check byte
sub _byte {
  my ($n) = @_;
  $n //= 0;
  $n = 0   if $n < 0;
  $n = 255 if $n > 255;
  return chr($n);
}

# Send a command to LCD
sub lcd_cmd {
  my ($txt) = @_;
  lcd_write($cmd . ($txt // ''));
}

# --- Public API -------------------------------------------------------------

# lcd_open()
# lcd_open('/dev/ttyS0')
# lcd_open({ lcd_device => '/dev/ttyUSB0', speed => 9600, keypad_device => '/dev/keypad' })
# lcd_open(lcd_device => '/dev/ttyUSB0', speed => 9600, keypad_device => '/dev/keypad')
sub lcd_open {
  my (@args) = @_;

  my %opt;
  if (@args == 1 && ref($args[0]) eq 'HASH') {
    %opt = %{ $args[0] };
  } elsif (@args == 1 && !ref($args[0])) {
    # Backwards compatible: single positional argument is the LCD device
    %opt = (lcd_device => $args[0]);
  } elsif (@args % 2 == 0) {
    %opt = @args;
  } elsif (@args) {
    croak "lcd_open: invalid arguments";
  }

  my $lcd_device    = $opt{lcd_device}    // $opt{device} // $DEFAULT_LCD_DEVICE;
  my $keypad_device = $opt{keypad_device} // $opt{device} // $DEFAULT_KEYPAD_DEVICE;
  my $speed         = $opt{speed}         // $DEFAULT_SPEED;

  # If already opened, close first to avoid leaking descriptors.
  lcd_close() if $opened;

  _configure_serial(device => $lcd_device, speed => $speed);

  open($LCD, '>', $lcd_device) or croak "can't open LCD device '$lcd_device': $!";
  _autoflush_on($LCD);

  open($KPD, '<', $keypad_device) or croak "can't open keypad device '$keypad_device': $!";
  binmode($KPD);

  $opened = 1;
  return 1;
}

sub lcd_close {
  return 1 if !$opened;
  $opened = 0;

  if ($LCD) {
    close($LCD) or carp "error closing LCD: $!";
    undef $LCD;
  }
  if ($KPD) {
    close($KPD) or carp "error closing keypad: $!";
    undef $KPD;
  }

  return 1;
}

sub lcd_write {
  my ($text) = @_;
  return if !defined $text;
  _require_open();

  print {$LCD} $text or carp "write to LCD failed: $!";
  return 1;
}

# raw read (reads one byte from keypad)
sub lcd_read {
  _require_open();

  my $key;
  my $n = read($KPD, $key, 1);
  return undef if !defined $n || $n == 0;
  return $key;
}

# --- Shortcut commands (kept 1:1 with original module) ----------------------

sub lcd_auto_scroll_on          { lcd_cmd($auto_scroll_on) }
sub lcd_auto_scroll_off         { lcd_cmd($auto_scroll_off) }
sub lcd_auto_line_wrapping_on   { lcd_cmd($auto_line_wrapping_on) }
sub lcd_auto_line_wrapping_off  { lcd_cmd($auto_line_wrapping_off) }
sub lcd_auto_repeat_mode_0      { lcd_cmd($auto_repeat_mode_0) }
sub lcd_auto_repeat_mode_1      { lcd_cmd($auto_repeat_mode_1) }
sub lcd_auto_xmit_keypress_on   { lcd_cmd($auto_xmit_keypress_on) }
sub lcd_auto_xmit_keypress_off  { lcd_cmd($auto_xmit_keypress_off) }
sub lcd_backlight_on            { lcd_cmd($backlight_on) }
sub lcd_backlight_off           { lcd_cmd($backlight_off) }
sub lcd_blink_on                { lcd_cmd($blink_on) }
sub lcd_blink_off               { lcd_cmd($blink_off) }
sub lcd_set_brightness_100      { lcd_cmd($set_brightness_100) }
sub lcd_set_brightness_75       { lcd_cmd($set_brightness_75) }
sub lcd_set_brightness_50       { lcd_cmd($set_brightness_50) }
sub lcd_set_brightness_25       { lcd_cmd($set_brightness_25) }
sub lcd_clear_display           { lcd_cmd($clear_display) }
sub lcd_clear_key_buffer        { lcd_cmd($clear_key_buffer) }
sub lcd_getcontrast             { return $contrast_value }

sub lcd_contrast {
  my ($val) = @_;
  $val //= $contrast_value;
  $contrast_value = ($val < 0) ? 0 : ($val > 255 ? 255 : $val);
  lcd_cmd($contrast . _byte($contrast_value));
}

sub lcd_contrastup {
  $contrast_value += $contrast_incr if $contrast_value < (255 - $contrast_incr);
  lcd_cmd($contrast . _byte($contrast_value));
}

sub lcd_contrastdown {
  $contrast_value -= $contrast_incr if $contrast_value > $contrast_incr;
  lcd_cmd($contrast . _byte($contrast_value));
}

sub lcd_cursor_on               { lcd_cmd($cursor_on) }
sub lcd_cursor_off              { lcd_cmd($cursor_off) }
sub lcd_cursor_left             { lcd_cmd($cursor_left) }
sub lcd_cursor_right            { lcd_cmd($cursor_right) }

sub lcd_set_debounce_time {
  my ($val) = @_;
  $val //= 0;
  lcd_cmd($set_debounce_time . _byte($val));
}

sub lcd_create_custom_char {
  my ($num, @v) = @_;
  $num //= 0;
  @v = map { $_ // 0 } @v;
  splice(@v, 8) if @v > 8;
  push(@v, (0) x (8 - @v));

  my $payload = $create_custom_char . _byte($num) . join('', map { _byte($_) } @v);
  lcd_cmd($payload);
}

sub lcd_goto {
  my ($col, $row) = @_;
  $col //= 0;
  $row //= 0;
  lcd_cmd($goto . _byte($col) . _byte($row));
}

sub lcd_go_to_top_left          { lcd_cmd($go_to_top_left) }
sub lcd_poll_keypad             { lcd_cmd($poll_keypad) }
sub lcd_large_digit_init        { lcd_cmd($large_digit_init) }

sub lcd_place_large_digit {
  my ($col, $row) = @_;
  $col //= 0;
  $row //= 0;
  lcd_cmd($place_large_digit . _byte($col) . _byte($row));
}

sub lcd_hr_bar_graph_init       { lcd_cmd($hr_bar_graph_init) }

sub lcd_make_hr_bar_graph {
  my ($col, $row, $dir, $len) = @_;
  $col //= 0;
  $row //= 0;
  $dir //= 0;
  $len //= 0;
  lcd_cmd($make_hr_bar_graph . _byte($col) . _byte($row) . _byte($dir) . _byte($len));
}

sub lcd_vr_thick_bar_graph_init { lcd_cmd($vr_thick_bar_graph_init) }
sub lcd_vr_thin_bar_graph_init  { lcd_cmd($vr_thin_bar_graph_init) }

sub lcd_make_vr_bar_graph {
  my ($col, $len) = @_;
  $col //= 0;
  $len //= 0;
  lcd_cmd($make_vr_bar_graph . _byte($col) . _byte($len));
}

sub lcd_backspace               { lcd_cmd($backspace) }
sub lcd_clear_screen            { lcd_cmd($clear_screen) }

sub lcd_map_keypad {
  my ($kpdk) = @_;
  return undef if !defined $kpdk;
  return $keypad_map{$kpdk};
}

1;

__END__

=head1 NAME

lcd - Legacy helper for Matrix Orbital serial LCDs and keypad input

=head1 SYNOPSIS

  use lcd;

  # Old style (still works)
  lcd_open();

  # New style: choose the serial device at init
  lcd_open(lcd_device => '/dev/ttyUSB0', speed => 19200, keypad_device => '/dev/keypad');

  lcd_clear_display();
  lcd_goto(1, 1);
  lcd_write("Bonjour");

  my $raw = lcd_read();
  my $mapped = lcd_map_keypad($raw);

  lcd_close();

=head1 DESCRIPTION

This module preserves the original 1999 procedural API (exported functions)
while making the serial device configurable and improving robustness.

=head1 CONFIGURATION

C<lcd_open> accepts either:

=over 4

=item * No arguments (uses defaults)

=item * One scalar (interpreted as C<lcd_device>)

=item * A hash or hashref with keys:

  lcd_device   (or device)
  keypad_device
  speed

=back

=head1 NOTES

Serial port configuration is attempted via C<stty> (using -F / -f when
available) and falls back to a legacy shell-based redirection.

=cut
