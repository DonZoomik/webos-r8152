# Why

I have an LG OLED TV OLED65C41LA (2024 C4).
Like most (all?) TV-s, it has a 100M NIC that can be insufficient for Sunshine-Moonlight and high-bandwidth Plex streaming.
So I took some random USB-to-Ethernet adapters with Realtek chipsets.
While they worked, performance can be quite bad. On newer RTL8156 based ones (2.5G) it was even worse than built-in NIC.
RTL8153 based 1G was tolerable but had random drops when streaming even at low bitrates.
All my Realtek NICs bind to generic cdc_ncm driver that doesn't do so well.
So I started investigating. Apparently this TV's kernel has really old builtin r8152 driver that didn't recognize any USB NICs that I had lying around (even if forced).
This implies that I'd have to use a custom name for the module.
There's some random modules (for example https://github.com/mbenitez343/lg-webos-2024-ethernet-fix) but these are for different platforms and imply no built-in module.

# How I built it

The main problem was finding the correct kernel source - I never found the exactly correct one. LG's OpenSource page is a mess and my TV-s model has incorrect sources.
Eventually I found the most suitable one from bundle "webOS25 WM_ReNew", file "webOS25 WM_ReNew_3.zip", source file "linux-and-kdriver-1637.tar.gz".
I at first tried building manually but I was out of my league, when trying to build modules with no config for mismatched kernel source...
Then I started abused ChatGPT (both free and eventually paid one).
It integrates Realtek's latest driver (v2.22.1 right now) with some minor changes (PCI support is made optional as LG TV has no PCI bus).
Free ChatGPT produced many failed builds that didn't work properly for many reasons (wrong sources, ABI problems).
Payed Codex then did some magic, analyzed the existing kernel, spent a lot of tokens and after a lot of debug and back-and-forth spit out a module named r8152_oot.ko that actually seems to work.
Then I asked it to generate a script that would auto-attach the driver as the kernel still attaches cdc_ncm by default even if r8152_oot.ko is loaded.
It works both manually and via script.

# Disclaimer
So this module is *NOT* generic, I built it for *my* TV, it's unlikely to work anywhere else

* Kernel: Linux LGwebOSTV 5.4.268-329.ptl4tv.5 #1 SMP PREEMPT Mon Sep 8 05:02:25 UTC 2025 aarch64 GNU/Linux
* Model: OLED65C41LA.DEUQLJP
* Firmware version: 33.31.68
* WebOS25/10.3.1-3006

# How to use

* Root your TV https://cani.rootmy.tv/
* Install Homebrew Channel (comes with rooting...)
* Upload kernel module and script to /home/root (or really anywhere you like...)
* chmod +x /home/root/r8152-autobind.sh
* /home/root/r8152-autobind.sh start - this doesn't install permanent integration but will watch and replace the modules until reboot
* /home/root/r8152-autobind.sh status - shows what it's up to
* /home/root/r8152-autobind.sh install - installs permanent watcher that attaches to Homebrew Channel root startup hook.
* I uploaded all the stuff produced by Codex in output folder as well, look inside if you're interested, it has more details (including removal)

# Possible issues
* If both NICs (builtin and USB) are connected, Linux may route egress via built-in eth0 so you don't see increased bandwidth. TL;DR: disconnect builtin NIC when the module starts working.
* Having scatter-gather enabled causes TV's USB host to die after some time. It is disabled at driver attach. There's a minor performance impact, a few percent.
* 2.5G RTL8156 links at 1G but that's driver limitation as 2.5G is negotiated only on USB3+. At 480M USB2 it hardly matters.

# Performance

Tested with iperf3 towards a 10G endpoint. For UDP I used 1G bandwidth and just measured what got through.

| NIC | Ingress TCP | Retries | Egress TCP | Bidirectional ingress TCP | Bidirectional egress TCP | Ingress UDP | Egress UDP |
| Builtin | 96.7 Mbits/sec | 45 | 94.9 Mbits/sec | 94.0 Mbits/sec | 93.3 Mbits/sec | 95.6 Mbits/sec | 95.6 Mbits/sec |
| RTL8153 cdc_ncm | 208 Mbits/sec | 966 | 255 Mbits/sec | 203 Mbits/sec | 84.5 Mbits/sec | 346 Mbits/sec | 261 Mbits/sec |
| RTL8153 rt8152_oot | 333 Mbits/sec | 45 | 286 Mbits/sec | 176 Mbits/sec | 162 Mbits/sec | 343 Mbits/sec | 278 Mbits/sec |
| RTL8156 cdc_ncm | 195 Mbits/sec | 877 | 255 Mbits/sec | 199 Mbits/sec | 91.9 Mbits/sec | 346 Mbits/sec | 261 Mbits/sec |
| RTL8156 rt8152_oot | 333 Mbits/sec | 42 | 286 Mbits/sec | 174 Mbits/sec | 163 Mbits/sec | 343 Mbits/sec | 278 Mbits/sec |

These numbers can't tell how much more stable rt8152_oot performance is. TCP performance could previously drop to under 50 Mbits/sec and Moonlight/Aurora was just unusable.

# License

MIT - so use at your own peril.
Realtek stuff remains GPL-2.0.