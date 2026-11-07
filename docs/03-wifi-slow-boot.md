# Slow 5 GHz SSID appearance at boot

## Symptom

After powering on or rebooting the router, the 5 GHz SSID takes **~90 s or more**
to appear in Wi-Fi scan results on client devices. The 2.4 GHz SSID shows up
fast. Some clients never find the 5 GHz SSID until a manual re-scan.

## Cause

The vendor firmware ships with 5 GHz **auto-channel selection enabled**
(`mtcwireless.wlan_5g.channel='auto'` + `AutoChannelSelect='3'` in the UCI).
At boot, the MediaTek driver scans every channel in the 5 GHz band before
choosing one. That band includes the **DFS channels 52-140**, where the
regulator requires a 60-second Channel Availability Check (CAC) during which
the AP must stay silent, and clients can only discover the SSID passively
(no probe response).

On top of that, when the vendor ACS happens to pick a DFS channel, your clients
switch to passive scan on that channel too, which is slow.

## Fix

Pin 5 GHz to a **non-DFS channel**. In EU/FR, the usable non-DFS 5 GHz channels
are **36, 40, 44, 48**. We use **48** below (the boot-time ACS scan from one
observed unit reported it as the least busy of those four, but any of 36/40/44/48
is equivalent).

Three changes (all three required — the vendor pipeline reads the UCI, the
driver reads the `.dat`, and the live driver needs to be told the new channel):

```sh
# 1. UCI (source of truth, used at next reboot to regenerate the .dat)
uci set mtcwireless.wlan_5g.channel='48'
uci set mtcwireless.wlan_5g.AutoChannelSelect='0'
uci commit mtcwireless

# 2. The .dat file read by the driver at wifi startup
sed -i -e 's/^Channel=0$/Channel=48/' \
       -e 's/^AutoChannelSelect=3$/AutoChannelSelect=0/' \
       /etc/wireless/mediatek/mt7915.dbdc.b1.dat

# 3. Push to the live driver so it takes effect immediately
iwpriv rax0 set Channel=48

sync
```

Verify with:

```sh
iwconfig rax0 | grep -E 'Channel|Freq'
# expect: Channel=48 (or Frequency:5.24 GHz)
```

Also included in [`scripts/apply-ipv6-fix.sh`](../scripts/apply-ipv6-fix.sh).

## Alternative: UCI-only, let the vendor pipeline resync at next boot

If you prefer to only touch the UCI and let the vendor's own machinery sync the
`.dat`:

```sh
uci set mtcwireless.wlan_5g.channel='48'
uci set mtcwireless.wlan_5g.AutoChannelSelect='0'
uci commit mtcwireless
wifi reload
```

In practice we saw cases where the `.dat` was not resynced correctly by `wifi
reload` alone, which is why the three-way change above is more reliable.

## Band map

Useful reference if you want to touch 2.4 GHz too:

| Band | UCI section | VAP prefix | `.dat` file |
|---|---|---|---|
| 2.4 GHz | `mtcwireless.wlan_24g` | `ra` (`ra0..ra3`) | `mt7915.dbdc.b0.dat` |
| 5 GHz | `mtcwireless.wlan_5g` | `rax` (`rax0..rax3`) | `mt7915.dbdc.b1.dat` |
