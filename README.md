# Project Sentinel

---

### Overview

**Project Sentinel** is a customizable and lightweight network management system designed to act as a NAT gateway. It allows users to block domains, manage rate-limited network access, and monitor connected devices in real-time. Built using **Elixir** and **Nerves**, Project Sentinel can run on low-powered devices such as **ESP32** or **Raspberry Pi**, enabling efficient control over network traffic through a user-friendly API and static HTML interface.

Users interact with the system through simple API endpoints or a static HTML page, allowing seamless management of blacklists, traffic limits, and more. This project provides a flexible, scalable solution for local network control in home or small office environments.

---

### Features

- **NAT Gateway Functionality**: Acts as a network gateway, routing traffic for all connected devices and applying traffic management rules.
- **DNS-Based Blocking**: Uses a JSON-based blacklist stored on flash memory, with fast lookups using ETS for efficient domain blocking.
- **Dynamic User Management**: Manages connected devices with separate processes, allowing for per-user rate limits and traffic controls.
- **Rate Limiting**: Set and manage network traffic limits for each user dynamically through a GenServer process.
- **RESTful API**: Provides simple, accessible API endpoints to manage the blacklist, adjust rate limits, and monitor network traffic in real time.
- **Static HTML Interface**: An easy-to-use HTML interface allows non-technical users to interact with the device for basic network management.
- **Persistent Storage**: Configuration data such as the blacklist and rate limits are stored on flash memory to ensure persistence across reboots.
- **Real-Time Application**: Any changes made via the API or HTML interface take effect immediately, ensuring up-to-date traffic management.

---

### Hardware Requirements

- **Device**: ESP32, Raspberry Pi 3, Raspberry Pi 4, or Raspberry Pi Zero.
- **Storage**: Minimum 8GB microSD card or internal flash storage for configurations and logs.
- **Power Supply**: Micro-USB or USB-C based on the chosen device.
- **Optional**: External Wi-Fi adapter for enhanced connectivity (Raspberry Pi).

---

### Getting Started

1. **Install Elixir and Nerves**: Set up your development environment with Elixir and Nerves.
2. **Set Up a Nerves Project**: Create a Nerves project targeting your desired hardware, such as Raspberry Pi or ESP32.
3. **Configure Networking**: Configure the device as a Wi-Fi access point and NAT gateway to route traffic and manage connected devices.
4. **Manage Blacklist and Rate Limits**: Use dynamic supervision with GenServer processes to handle user-specific configurations such as rate limits and monitoring.
5. **Use the API**: Interact with the API or static HTML page to manage blacklists, rate limits, and view real-time traffic data.

---

### Usage

1. **Power on the device** and connect it to the network (or use its access point mode).
2. **Connect via Static HTML**: Open the static HTML page on your browser to interact with the device and manage configurations.
3. **Use the API**: Interact programmatically via API calls to modify the blacklist, retrieve traffic statistics, or set rate limits.
4. **Real-Time Configuration**: Any updates made via the API or HTML interface are applied instantly, ensuring up-to-date control of network traffic.

---

### Roadmap

- **Traffic Visualization**: Add tools for real-time traffic visualization, allowing users to see network activity via WebSockets or polling.
- **Support for Encrypted DNS (DoH, DoT)**: Add DNS over HTTPS and DNS over TLS support for enhanced privacy and security.
- **Multi-Device Scaling**: Enable multiple devices to share blacklist and configuration data for managing larger networks.
- **User Authentication**: Implement secure API authentication to allow only authorized users to manage the device.

---

### License

**Project Sentinel** is licensed under the MIT License. See the LICENSE file for more details.
