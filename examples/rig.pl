#!/usr/bin/env perl
#
# Another example which uses rigctl to display frequencies of my two
# ham radio transceivers

use strict;
use warnings;
# use lib '.';

use IO::Socket::INET;
use IO::Select;
use POSIX qw(strftime);
use lcd;

# ---- LCD config (adapt if needed)
my $LCD_DEV = '/dev/ttyS0';
my $BAUD    = 19200;

# ---- rigctld endpoints
my %rig = (
  '705' => { host => '127.0.0.1', port => 4532, name => '1' }, # IC-705
  '7300' => { host => '127.0.0.1', port => 4533, name => '2' }, # IC-7300
);

lcd_open(lcd_device => $LCD_DEV, speed => $BAUD);
lcd_clear_display();

$SIG{INT} = sub {
  lcd_clear_display();
  lcd_close();
  print "\nBye.\n";
  exit 0;
};

while (1) {
  my $blink = time() % 2; # 0/1 toggles each second

  # Line 1: local + UTC with blinking ":" (":" or " ")
  my $line1 = time_line($blink);

  # Query rigs (never blocks)
  my ($hz705, $st705) = get_freq_and_strength($rig{'705'}{host}, $rig{'705'}{port});
  my ($hz73,  $st73 ) = get_freq_and_strength($rig{'7300'}{host}, $rig{'7300'}{port});

  my $line2 = format_rig_line_mhz('1', $hz705, $st705);  # 705>145.60000 (-4)
  my $line3 = format_rig_line_khz('2', $hz73,  $st73);   # 7.3> 3700.00 (23)

  lcd_goto(1, 1); lcd_write(fix20($line1));
  lcd_goto(1, 2); lcd_write(fix20($line2));
  lcd_goto(1, 3); lcd_write(fix20($line3));
  lcd_goto(1, 4); lcd_write(' ' x 20);

  sleep 1;
}

# -------------------------------------------------------------------------

sub time_line {
  my ($blink) = @_;
  my $sep = $blink ? ':' : ' ';
  my $sep2 = ':';

  my ($lh, $lm, $ls) = (strftime("%H", localtime()), strftime("%M", localtime()), strftime("%S", localtime()));
  my ($uh, $um, $us) = (strftime("%H", gmtime()),    strftime("%M", gmtime()), strftime("%S", localtime()));

  # Example: "20:32 | 19:32Z |" (20 chars max)
  return sprintf("%s%s%s%s%s|%s%s%s%s%sZ", $lh, $sep2, $lm, $sep, $ls, $uh, $sep2, $um, $sep, $us);
}

sub get_freq_and_strength {
  my ($host, $port) = @_;

  my $sock = IO::Socket::INET->new(
    PeerAddr => $host,
    PeerPort => $port,
    Proto    => 'tcp',
    Timeout  => 0.5,     # connect timeout
  );
  return (undef, undef) if !$sock;

  $sock->autoflush(1);

  # Send both commands; many rigctld builds reply with:
  #   <value>\nRPRT 0\n
  # for each command.
  print $sock "f\n";
  print $sock "l STRENGTH\n";

  my $sel = IO::Select->new($sock);

  my $deadline = time() + 1;      # hard stop after ~1 second
  my $buf      = '';
  my @lines;

  while (time() < $deadline) {
    my @ready = $sel->can_read(0.2);
    last if !@ready;

    my $chunk = '';
    my $n = sysread($sock, $chunk, 4096);
    last if !defined $n || $n == 0;

    $buf .= $chunk;

    while ($buf =~ s/^(.*?\n)//) {
      my $line = $1;
      $line =~ s/\r?\n$//;
      push @lines, $line;
    }

    # Early exit if we already have enough numeric values
    last if count_numeric_values(\@lines) >= 2;
  }

  close $sock;

  my ($hz, $strength) = parse_freq_strength(\@lines);

  # Strength: round to int like your example
  my $st_int;
  if (defined $strength) {
    $st_int = int($strength + ($strength >= 0 ? 0.5 : -0.5));
  }

  return ($hz, $st_int);
}

sub count_numeric_values {
  my ($lines) = @_;
  my $c = 0;
  for my $l (@$lines) {
    next if $l =~ /^RPRT\s+/;
    $c++ if $l =~ /^-?\d+(?:\.\d+)?$/;
  }
  return $c;
}

sub parse_freq_strength {
  my ($lines) = @_;

  # We expect two numeric responses:
  #  - freq in Hz (integer, usually big)
  #  - strength (can be int/float, can be negative)
  my @nums;
  for my $l (@$lines) {
    next if $l =~ /^RPRT\s+/;
    push @nums, $l if $l =~ /^-?\d+(?:\.\d+)?$/;
  }

  return (undef, undef) if !@nums;

  # Heuristic: frequency is the first big integer (>= 100000)
  my $hz;
  my $strength;
  for my $n (@nums) {
    if (!defined $hz && $n =~ /^\d+$/ && $n >= 100_000) {
      $hz = $n;
      next;
    }
    if (defined $hz && !defined $strength) {
      $strength = $n;
      last;
    }
  }

  # Fallback if heuristic didn't work
  $hz       //= ($nums[0] =~ /^\d+$/ ? $nums[0] : undef);
  $strength //= $nums[1] if @nums > 1;

  return ($hz, $strength);
}

sub format_rig_line_mhz {
  my ($tag, $hz, $st) = @_;
  my $sttxt = defined $st ? $st : '--';
  return sprintf("%s|--------- (--)", $tag) if !defined $hz;

  my $mhz = $hz / 1_000_000.0;
  return sprintf("%s>%9.5f (%s)", $tag, $mhz, $sttxt);
}

sub format_rig_line_khz {
  my ($tag, $hz, $st) = @_;
  my $sttxt = defined $st ? $st : '--';
  return sprintf("%s|-------.-- (--)", $tag) if !defined $hz;

  my $khz = $hz / 1000.0;
  return sprintf("%s> %7.2f (%s)", $tag, $khz, $sttxt);
}

sub fix20 {
  my ($s) = @_;
  $s //= '';
  $s = substr($s, 0, 20) if length($s) > 20;
  $s .= ' ' x (20 - length($s)) if length($s) < 20;
  return $s;
}
