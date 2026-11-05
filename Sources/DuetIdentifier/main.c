#include "command.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>
#include <string.h>

static uint32_t device_transfer(void *context, uint8_t direction, uint8_t request,
                               uint16_t value, uint16_t index, uint16_t length,
                               void *data, uint16_t *actual) {
    IOUSBDeviceInterface197 **device = context;
    IOUSBDevRequestTO transfer = {
        .bmRequestType = direction, .bRequest = request, .wValue = value,
        .wIndex = index, .wLength = length, .pData = data,
        .noDataTimeout = 500, .completionTimeout = 500
    };
    IOReturn status = (*device)->DeviceRequestTO(device, &transfer);
    *actual = (uint16_t)transfer.wLenDone;
    return status;
}

int main(int argc, char **argv) {
    int session = argc == 2 && strcmp(argv[1], "--session") == 0;
    DuetCommand command;
    if (!session && !duet_parse(argc, argv, &command)) {
        fputs("Usage: openduet-identify [--meters | --events | --input-modes | --session | experimental command target value --apply]\n", stderr);
        return 64;
    }
    if (session) setvbuf(stdout, NULL, _IOLBF, 0);
    int result = 1;
    io_iterator_t iterator = 0;
    io_service_t target = 0;
    IOCFPlugInInterface **plugin = NULL;
    IOUSBDeviceInterface197 **device = NULL;
    SInt32 score = 0;
    IOReturn status = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOUSBHostDevice"), &iterator);
    if (status != kIOReturnSuccess) return result;
    for (io_service_t entry; (entry = IOIteratorNext(iterator)); IOObjectRelease(entry)) {
        CFTypeRef vendor = IORegistryEntryCreateCFProperty(entry, CFSTR("idVendor"), NULL, 0);
        CFTypeRef product = IORegistryEntryCreateCFProperty(entry, CFSTR("idProduct"), NULL, 0);
        int vid = 0, pid = 0;
        if (vendor && CFGetTypeID(vendor) == CFNumberGetTypeID())
            CFNumberGetValue(vendor, kCFNumberIntType, &vid);
        if (product && CFGetTypeID(product) == CFNumberGetTypeID())
            CFNumberGetValue(product, kCFNumberIntType, &pid);
        if (vendor) CFRelease(vendor);
        if (product) CFRelease(product);
        if (vid == 0x0c60 && pid == 7) {
            if (target) { IOObjectRelease(entry); puts("Multiple matching devices"); goto cleanup; }
            IOObjectRetain(entry);
            target = entry;
        }
    }
    if (!target) { puts("Duet not found"); goto cleanup; }
    status = IOCreatePlugInInterfaceForService(target, kIOUSBDeviceUserClientTypeID,
        kIOCFPlugInInterfaceID, &plugin, &score);
    if (status != kIOReturnSuccess || !plugin) {
        printf("Create USB interface: %#x\n", status); goto cleanup;
    }
    HRESULT query = (*plugin)->QueryInterface(plugin,
        CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID197), (LPVOID *)&device);
    if (query || !device) { printf("Query USB interface: %#x\n", (unsigned)query); goto cleanup; }
    status = (*device)->USBDeviceOpen(device);
    printf("Normal USB open: %#x\n", status);
    if (status != kIOReturnSuccess) goto cleanup;
    DuetDisplayCache displayCache = {0};
    DuetTransport transport = {.context = device, .transfer = device_transfer, .displayCache = &displayCache};
    result = session ? duet_session(&transport) : duet_execute(&transport, &command, stdout);
    IOReturn closeStatus = (*device)->USBDeviceClose(device);
    printf("USB close: %#x\n", closeStatus);
    if (closeStatus != kIOReturnSuccess) result = 1;
cleanup:
    if (device) (*device)->Release(device);
    if (plugin) IODestroyPlugInInterface(plugin);
    if (target) IOObjectRelease(target);
    IOObjectRelease(iterator);
    return result;
}
