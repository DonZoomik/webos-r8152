/* Compile-time checks derived from the saved LG OLED65C41LA crash dump.
 * These cover the USB offsets involved in that fault, not the complete ABI.
 */
#ifndef LG_O22_TV_ABI_CHECKS_H
#define LG_O22_TV_ABI_CHECKS_H

#include <linux/build_bug.h>
#include <linux/stddef.h>
#include <linux/usb.h>

static_assert(sizeof(void *) == 8, "TV module must be AArch64");
static_assert(offsetof(struct usb_device, dev) == 0xa0,
              "usb_device.dev differs from the TV crash evidence");
static_assert(offsetof(struct usb_device, bos) == 0x3a0,
              "usb_device.bos differs from the TV BOS pointer location");
static_assert(offsetof(struct usb_device, config) == 0x3a8,
              "usb_device.config must follow the TV BOS pointer");
static_assert(offsetof(struct usb_device, descriptor) +
              offsetof(struct usb_device_descriptor, bNumConfigurations) == 0x399,
              "USB configuration-count offset differs from TV evidence");
static_assert(offsetof(struct usb_interface, dev) == 0x30,
              "usb_interface.dev differs from TV evidence");

#endif
