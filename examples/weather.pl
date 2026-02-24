#!/usr/bin/env perl
# 
# This example script will get weather conditions at lat/lon on open-meteo.com
# and display some values on LCD
#
# Copyright (c) 2026 Alexis Domjan <adomjan@horus.ch>
#

use lib '.';
use strict;
use warnings;

use HTTP::Tiny;
use JSON::MaybeXS;
use Time::HiRes qw(sleep);
use lcd;

# ---- LCD configuration
my $LCD_DEV = '/dev/ttyS0';
my $BAUD    = 19200;

# ---- Location
my ($lat, $lon) = (47.000, 7.00);

# Open LCD
lcd_open(lcd_device => $LCD_DEV, speed => $BAUD);
lcd_clear_display();

$SIG{INT} = sub {
    lcd_clear_display();
    lcd_close();
    print "\nBye.\n";
    exit 0;
};

while (1) {
    # Build Open-Meteo URL
    my $url = sprintf(
      "https://api.open-meteo.com/v1/forecast?latitude=%f&longitude=%f&current=temperature_2m,relative_humidity_2m,pressure_msl&forecast_days=1",
      $lat, $lon,
    );
    print $url;

    # Fetch JSON
    my $res = HTTP::Tiny->new->get($url);

    unless ($res->{success}) {
        lcd_goto(1,1); lcd_write(fix20("Weather API error"));
        sleep 60;
        next;
    }

    my $data = decode_json($res->{content});

    # Extract current values
    my $temp = $data->{current}{temperature_2m} // 'N/A';
    my $humidity = $data->{current}{relative_humidity_2m} // 'N/A';
    my $pressure = $data->{current}{pressure_msl} // 'N/A';
    my $time = $data->{current}{time}        // '';

    # Format lines
    my $l1 = sprintf("Temp: %2.1f C", $temp);
    my $l2 = sprintf("Hum : %3s%", $humidity);
    my $l3 = sprintf("Pres: %5s hPa", $pressure);
    my $l4 = sprintf("%s", $time);

    lcd_goto(1,1); lcd_write(fix20($l1));
    lcd_goto(1,2); lcd_write(fix20($l2));
    lcd_goto(1,3); lcd_write(fix20($l3));
    lcd_goto(1,4); lcd_write(fix20($l4));

    sleep 60;  # update every minute
}

sub fix20 {
    my ($s) = @_;
    $s //= '';
    $s = substr($s, 0, 20) if length($s) > 20;
    $s .= ' ' x (20 - length($s)) if length($s) < 20;
    return $s;
}
