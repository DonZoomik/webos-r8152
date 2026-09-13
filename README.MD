# Why

I have an LG OLED TV OLED65C41LA (2024 C4).
Like most (all?) TV-s, it has a 100M NIC that can be insufficient for Sunshine-Moonlight and high-bandwidth Plex streaming.
So I took some random USB-to-Ehternet adapters with Realtek chipsets.
While they worked, performance can be quite bad. On newer RTL8156 based ones (2.5G) it was even worse than built-in NIC.
RTL8153 based 1G was tolerable but had random drops when streaming even at low bitrates.
All Realtek NICs bind to generic cdc_ncm driver that doesn't do so well.
So I started investigating. Apparently this TV's kernel has a stub or basically nonfunctional r8152 driver builtin that doesn't register basically anything.
This implies that i'd have to use a custom name for the module.
There's some random modules (for example https://github.com/mbenitez343/lg-webos-2024-ethernet-fix) but these are for different platforms and imply no built-in module.

# How i built it

The main problem was finding the correct kernel source - I never found the exactly correct one. LG's OpenSource page is a mess and my TV-s model has incorrect sources.
Eventually I found the most suitable one from bundle "webOS25 WM_ReNew", file "webOS25 WM_ReNew_3.zip", source file "linux-and-kdriver-1637.tar.gz".
I at first tried building manually but I was out of my league, when trying to build modules with no config for mismatched kernel source...
Then I started abused ChatGPT (both free and eventually payed one).
It integrates Realtek's latest driver (v2.22.1 right now) with some minor changes (PCI support is made optional as LG TV has no PCI bus).
Free ChatGPT produced many failed builds that didn't work properly for many reasons (wrong sources, ABI problems).
Payed Codex then did some magic, analyzed the existing kernel, spent a lot of tokens and after a lot of debug and back-and-forth spit out a module named r8152_oot.ko that actually seems to work.
Then I asked it to generate a script that would auto-attach the driver as the kernel still attaches cdc_ncm by default even if r8152_oot.ko is loaded.
It works both manually

# Disclaimer
So this module is NOT generic, I built it for *my* TV, it's unlikely to work anywhere else

* Kernel: Linux LGwebOSTV 5.4.268-329.ptl4tv.5 #1 SMP PREEMPT Mon Sep 8 05:02:25 UTC 2025 aarch64 GNU/Linux
* Model: OLED65C41LA.DEUQLJP
* Firmware version: 33.31.68
* WebOS25/10.3.1-3006

# How to use

* Root your TV https://cani.rootmy.tv/
* Upload kernel module and script to /home/root (or really anywhere you like...)
* Chmod +x /home/root/r8152-autobind.sh
* /home/root/r8152-autobind.sh start - this doesnt install permanent integation but will replace the modules until reboot
* /home/root/r8152-autobind.sh status - shows what it's up to
* /home/root/r8152-autobind.sh install - installs permament agent
* I uploaded all the stuff produced by Codex in output folder as well, look inside if you're interested, it has more details (including removal)

#License
MIT - so use at your own peril.