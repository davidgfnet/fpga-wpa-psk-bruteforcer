
#ifndef __FTDI_DEV_HH__
#define __FTDI_DEV_HH__

#include <ftdi.h>

#define VENDOR_FTDI   0x0403
#define DEVICE_DEF    0x8350
#define channel_1   INTERFACE_C
#define channel_2   INTERFACE_D

#define fatal(...) { fprintf(stderr,  __VA_ARGS__); exit(1); }

#include "device.h"

class FTDIDevice : public Device {
public:
	FTDIDevice(libusb_device * dev, ftdi_interface iface) : Device() {
		
		ftdi_handle = ftdi_new();

		// Select iface
		if (ftdi_set_interface(ftdi_handle, iface) < 0)
			fatal("ERROR ftdi_set_interface: %s\n", ftdi_get_error_string(ftdi_handle));

		// Open device
		if (ftdi_usb_open_dev(ftdi_handle, dev) < 0)
			fatal("ERROR ftdi_usb_open: %s\n", ftdi_get_error_string(ftdi_handle));

		if (ftdi_set_bitmode(ftdi_handle, 0x00, BITMODE_RESET) < 0)
			fatal("ERROR ftdi_set_bitmode: %s\n", ftdi_get_error_string(ftdi_handle));

		if (ftdi_usb_purge_buffers(ftdi_handle) < 0)
			fatal("ERROR ftdi_usb_purge_buffers: %s\n", ftdi_get_error_string(ftdi_handle));

		ftdi_setflowctrl(ftdi_handle, SIO_DISABLE_FLOW_CTRL);

		if (ftdi_set_line_property(ftdi_handle, BITS_8, STOP_BIT_2, NONE ) < 0)
			fatal("ERROR ftdi_set_line_property: %s\n", ftdi_get_error_string(ftdi_handle));

		if (ftdi_set_baudrate(ftdi_handle, 115200) < 0)
			fatal("ERROR ftdi_set_baudrate: %s\n", ftdi_get_error_string(ftdi_handle));
	}

	virtual ~FTDIDevice() {
		
	}

	virtual ssize_t write(const void * buffer, size_t size) {
		return ftdi_write_data(ftdi_handle, (unsigned char*)buffer, size);
	}
	virtual ssize_t read(void * buffer, size_t size) {
		ssize_t ret = 0;
		while (ret == 0)
			ret = ftdi_read_data(ftdi_handle, (unsigned char*)buffer, size);
		//std::cerr << "READ "<< ret << std::endl;
		return ret;
	}

	// List all FTDI devices present in the system
	static std::vector<Device*> getAllDevs() {
		struct ftdi_context * listhandle = ftdi_new();
		struct ftdi_device_list * devlist;
		if (ftdi_usb_find_all(listhandle, &devlist, VENDOR_FTDI, DEVICE_DEF) < 0)
			fatal("ERROR ftdi_usb_find_all: %s\n", ftdi_get_error_string(listhandle));

		struct ftdi_device_list * curdev;
		std::vector<Device*> ret;
		for (curdev = devlist; curdev != NULL; curdev = curdev->next) {
			ret.push_back(new FTDIDevice(curdev->dev, channel_1));
			ret.push_back(new FTDIDevice(curdev->dev, channel_2));
		}
		return ret;
	}

private:
	struct ftdi_context *ftdi_handle;
};

#endif

